"""注册 / 登录 / 验证码 / 找回密码 / 会话。"""
from __future__ import annotations

import hmac
import re
import secrets
import sqlite3
import time
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel, Field

from core import (BOOTSTRAP_TOKEN, ROLE_LEVEL, SECRET, audit, check_password,
                  client_ip, consume_code, current_user, db, deliver_code, fail,
                  hash_password, issue_token, public_user, setting_bool,
                  setting_int, sha)

router = APIRouter(prefix="/api/auth", tags=["auth"])

EMAIL_RE = re.compile(r"[^@\s]+@[^@\s]+\.[^@\s]+")
USERNAME_RE = re.compile(r"[\w\u4e00-\u9fa5\-]{2,32}")


class CodeIn(BaseModel):
    target: str = Field(min_length=2, max_length=120)
    purpose: str = "register"


class RegisterIn(BaseModel):
    username: str = Field(min_length=2, max_length=32)
    password: str = Field(min_length=8, max_length=128)
    email: str = Field(min_length=5, max_length=120)
    code: str = ""
    bootstrap_token: str = ""


class LoginIn(BaseModel):
    username: str = Field(min_length=1, max_length=120)
    password: str = Field(min_length=1, max_length=128)
    code: str = ""


class ResetIn(BaseModel):
    email: str = Field(min_length=5, max_length=120)
    code: str
    password: str = Field(min_length=8, max_length=128)


def _email_of(login: str) -> Optional[sqlite3.Row]:
    with db() as c:
        return c.execute("SELECT * FROM users WHERE username=? OR email=?",
                         (login, login.lower())).fetchone()


@router.post("/code")
def send_code(body: CodeIn, request: Request):
    """发验证码：有效期、重发间隔、每小时上限；开发模式直接回显。"""
    if body.purpose not in ("register", "login", "reset"):
        fail(400, "验证码用途不合法")
    target = body.target.strip()
    if body.purpose == "register" and not setting_bool("email_verification", True):
        fail(400, "管理员已关闭邮箱验证，注册不需要验证码")
    if body.purpose in ("login", "reset"):
        # 登录/找回密码允许填账号或邮箱：一律解析成该账号绑定的邮箱再发信
        row = _email_of(target)
        if not row:
            fail(404, "该账号不存在，请检查拼写")
        if not row["enabled"]:
            fail(403, "该账号已被停用，请联系管理员")
        target = row["email"]
        if body.purpose == "reset" and not setting_bool("email_verification", True):
            fail(400, "管理员已关闭邮箱验证，暂无法自助找回密码，请联系管理员重置")
    target = target.lower()
    if not EMAIL_RE.fullmatch(target):
        fail(400, "请填写正确的邮箱地址")
    now = time.time()
    resend = setting_int("code_resend_seconds", 60)
    maxh = setting_int("code_max_per_hour", 5)
    ttl = setting_int("code_ttl_seconds", 600)
    with db() as c:
        # BEGIN IMMEDIATE 先拿写锁再做「重发间隔/每小时上限」检查，
        # 否则并发请求会同时读到旧计数、双双通过限流再各自插入验证码。
        c.execute("BEGIN IMMEDIATE")
        recent = c.execute(
            "SELECT created_at FROM codes WHERE target=? AND purpose=?"
            " ORDER BY created_at DESC LIMIT ?", (target, body.purpose, maxh)).fetchall()
        if recent and now - recent[0]["created_at"] < resend:
            left = int(resend - (now - recent[0]["created_at"]))
            fail(429, f"发送太频繁，请 {left} 秒后再试")
        if len(recent) >= maxh and now - recent[-1]["created_at"] < 3600:
            fail(429, f"一小时内最多发送 {maxh} 次验证码，请稍后再试")
        code = f"{secrets.randbelow(1_000_000):06d}"
        c.execute(
            "INSERT INTO codes(target,purpose,code_hash,expires_at,ip,created_at)"
            " VALUES(?,?,?,?,?,?)",
            (target, body.purpose, sha(code + SECRET), now + ttl, client_ip(request), now))
        # 顺手清理已过期的验证码，避免 codes 表只增不减、无限膨胀
        c.execute("DELETE FROM codes WHERE expires_at < ?", (now,))
    try:
        dev, note = deliver_code(target, code, body.purpose)
    except HTTPException:
        # 发信失败：删掉刚插入的验证码，别让它占住重发间隔，
        # 否则用户因一次 SMTP 抖动被迫白等 60 秒才能重试。
        with db() as c:
            c.execute(
                "DELETE FROM codes WHERE target=? AND purpose=? AND code_hash=?"
                " AND consumed=0",
                (target, body.purpose, sha(code + SECRET)))
        raise
    audit(request, None, "code.send", target, f"purpose={body.purpose}, dev={dev}")
    out = {"ok": True, "message": note, "expires_in": ttl, "resend_in": resend,
           "dev_mode": dev, "sent_to": target}
    if dev:
        out["dev_code"] = code
    return out


@router.post("/register")
def register(body: RegisterIn, request: Request,
             x_bootstrap_token: Optional[str] = Header(None, alias="X-Bootstrap-Token")):
    username, email = body.username.strip(), body.email.strip().lower()
    if not USERNAME_RE.fullmatch(username):
        fail(400, "账号需为 2-32 位中文、字母、数字、下划线或短横线")
    if not re.search(r"[A-Za-z]", body.password) or not re.search(r"\d", body.password):
        fail(400, "密码至少 8 位，且同时包含字母和数字")
    if not EMAIL_RE.fullmatch(email):
        fail(400, "请填写正确的邮箱地址")
    with db() as c:
        if c.execute("SELECT 1 FROM users WHERE username=?", (username,)).fetchone():
            fail(409, "该账号已被注册，换一个试试")
        if c.execute("SELECT 1 FROM users WHERE email=?", (email,)).fetchone():
            fail(409, "该邮箱已被注册，可直接登录")
        first = c.execute("SELECT COUNT(*) AS n FROM users").fetchone()["n"] == 0
    need_email = setting_bool("email_verification", True)
    if need_email and not consume_code(email, "register", body.code):
        fail(400, "验证码错误或已过期，请重新获取")
    supplied = x_bootstrap_token or body.bootstrap_token
    if first and BOOTSTRAP_TOKEN and not hmac.compare_digest(
            supplied.encode(), BOOTSTRAP_TOKEN.encode()):
        fail(403, "首个管理员注册需要有效的引导令牌")
    role = "super_admin" if first else "viewer"
    now = time.time()
    with db() as c:
        try:
            # 与「首个用户」判定同一把写锁（BEGIN IMMEDIATE）：多 worker 并发
            # 首注册时，都数到 0 会各自插出 super_admin，此处重判保证恰一个超管
            c.execute("BEGIN IMMEDIATE")
            first_locked = c.execute("SELECT COUNT(*) AS n FROM users").fetchone()["n"] == 0
            if first_locked:
                role = "super_admin"
            cur = c.execute(
                "INSERT INTO users(username,email,password_hash,role,enabled,email_verified,created_at)"
                " VALUES(?,?,?,?,1,?,?)",
                (username, email, hash_password(body.password), role,
                 1 if need_email else 0, now))
        except sqlite3.IntegrityError:
            # 并发注册撞了用户名/邮箱唯一约束：前面的 SELECT 检查存在竞态窗口
            fail(409, "该账号或邮箱刚被别人注册，请换一个再试")
        row = c.execute("SELECT * FROM users WHERE id=?", (cur.lastrowid,)).fetchone()
    token, ttl = issue_token(row["id"])
    audit(request, row, "user.register", username,
          f"email={email}, role={role}, email_verification={need_email}")
    return {
        "ok": True, "token": token, "expires_in": ttl, "user": public_user(row),
        "message": "注册成功，已登录" if need_email else "注册成功（管理员已关闭邮箱验证，邮箱未验证）",
        "email_verification": need_email,
    }


@router.post("/login")
def login(body: LoginIn, request: Request):
    name = body.username.strip()
    row = _email_of(name)
    if not row:
        audit(request, None, "user.login_failed", name, "账号不存在")
        fail(401, "账号或密码错误")
    now = time.time()
    if row["locked_until"] > now:
        fail(429, f"密码错误次数过多，请 {int((row['locked_until'] - now) / 60) + 1} 分钟后再试")
    if not check_password(body.password, row["password_hash"]):
        with db() as c:
            attempts = row["failed_attempts"] + 1
            locked = now + 15 * 60 if attempts >= 5 else 0
            c.execute("UPDATE users SET failed_attempts=?, locked_until=? WHERE id=?",
                      (attempts, locked, row["id"]))
        audit(request, None, "user.login_failed", name, f"密码错误，第 {attempts} 次")
        fail(401, "账号或密码错误" + ("；再错 1 次将锁定 15 分钟" if attempts == 4 else
                                     "；已锁定 15 分钟" if attempts >= 5 else ""))
    if not row["enabled"]:
        fail(403, "账号已被停用，请联系管理员")
    if setting_bool("login_code_required", False) and not consume_code(row["email"], "login", body.code):
        fail(401, "登录验证码错误或已过期，请重新获取")
    with db() as c:
        c.execute("UPDATE users SET failed_attempts=0, locked_until=0, last_login_at=? WHERE id=?",
                  (now, row["id"]))
        fresh = c.execute("SELECT * FROM users WHERE id=?", (row["id"],)).fetchone()
    token, ttl = issue_token(row["id"])
    audit(request, fresh, "user.login", name, "登录成功")
    return {"ok": True, "token": token, "expires_in": ttl,
            "user": public_user(fresh), "message": "登录成功"}


@router.post("/reset")
def reset_password(body: ResetIn, request: Request):
    email = body.email.strip().lower()
    if not EMAIL_RE.fullmatch(email):
        fail(400, "请填写正确的邮箱地址")
    if not setting_bool("email_verification", True):
        fail(400, "管理员已关闭邮箱验证，暂无法自助找回密码，请联系管理员")
    if not consume_code(email, "reset", body.code):
        fail(400, "验证码错误或已过期，请重新获取")
    if not re.search(r"[A-Za-z]", body.password) or not re.search(r"\d", body.password):
        fail(400, "密码至少 8 位，且同时包含字母和数字")
    with db() as c:
        row = c.execute("SELECT * FROM users WHERE email=?", (email,)).fetchone()
        if not row:
            fail(404, "该邮箱没有注册账号")
        c.execute("UPDATE users SET password_hash=?, failed_attempts=0, locked_until=0 WHERE id=?",
                  (hash_password(body.password), row["id"]))
        c.execute("DELETE FROM tokens WHERE user_id=?", (row["id"],))
    audit(request, row, "user.reset", row["username"], "通过邮箱验证码重置密码")
    return {"ok": True, "message": "密码已重置，请用新密码登录"}


@router.post("/logout")
def logout(request: Request, authorization: Optional[str] = Header(None),
           user: sqlite3.Row = Depends(current_user)):
    if authorization:
        with db() as c:
            c.execute("DELETE FROM tokens WHERE token_hash=?", (sha(authorization[7:].strip()),))
    audit(request, user, "user.logout", user["username"], "退出登录")
    return {"ok": True, "message": "已退出登录"}


@router.get("/me")
def me(user: sqlite3.Row = Depends(current_user)):
    level = ROLE_LEVEL.get(user["role"], 0)
    return {"ok": True, "user": public_user(user), "permissions": {
        "level": level, "can_edit_models": level >= 2,
        "can_manage_users": level >= 3, "can_edit_settings": level >= 3}}
