"""服务端基础设施：SQLite、设置、密码、令牌、权限、验证码、审计日志、密钥加密。"""
from __future__ import annotations

import base64
import hashlib
import hmac
import os
import re
import secrets
import smtplib
import sqlite3
import time
from contextlib import contextmanager
from email.message import EmailMessage
from pathlib import Path
from typing import Any, Optional

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from fastapi import Depends, Header, HTTPException, Request

ROOT = Path(__file__).resolve().parent
DB_PATH = os.getenv("WM_DB", str(ROOT / "data" / "wardrobe.db"))
SECRET = os.getenv("WM_SECRET", "dev-secret-change-me-in-production")
DEV_CODE = os.getenv("WM_DEV_CODE", "1") == "1"
BOOTSTRAP_TOKEN = os.getenv("WM_BOOTSTRAP_TOKEN", "")
SMTP_HOST = os.getenv("WM_SMTP_HOST", "")
SMTP_PORT = int(os.getenv("WM_SMTP_PORT", "465"))
SMTP_USER = os.getenv("WM_SMTP_USER", "")
SMTP_PASS = os.getenv("WM_SMTP_PASS", "")
SMTP_FROM = os.getenv("WM_SMTP_FROM", SMTP_USER)

ROLE_LEVEL = {"viewer": 1, "admin": 2, "super_admin": 3}
ROLE_LABELS = {"viewer": "只读", "admin": "管理员", "super_admin": "超级管理员"}

MODEL_KINDS = {
    "vision": "视觉识别 · 拆衣",
    "text": "文本分析 · 风格建议",
    "edit": "图像编辑 · 试穿",
    "avatar": "照片数字人 · 多视角形象",
    "white_bg": "白底商品图",
}
KIND_HINTS = {
    "vision": "看照片把整套穿搭拆成单件，需要「图片输入」能力",
    "text": "根据统计数据写风格建议，纯文本对话模型即可",
    "edit": "把搭配穿到用户人像上，需要「图像编辑」能力",
    "avatar": "根据本人全身照生成正面、侧面、背面形象；未单独配置时复用试穿模型",
    "white_bg": "把生活照转成白底商品图，需要「图像编辑」能力",
}

DEFAULT_SETTINGS = {
    # 账号与验证码
    "email_verification": "1",
    "login_code_required": "0",
    "code_ttl_seconds": "600",
    "code_resend_seconds": "60",
    "code_max_per_hour": "5",
    # App 服务
    "ai_service_enabled": "1",
    "direct_ai_enabled": "1",            # v1.9：允许 App 申请直连凭证
    "credential_ttl_hours": "24",        # v1.9：直连凭证有效期（1-168 小时）
    "device_auto_register": "1",
    "device_rate_limit": "30",
    "white_bg_mode": "local",           # local | server | off
    "app_min_version": "1.7.0",
    "app_notice": "",
    "site_name": "衣橱管家 · 管理后台",
}
SETTING_KEYS = set(DEFAULT_SETTINGS)
SWITCH_KEYS = {"email_verification", "login_code_required", "ai_service_enabled",
               "device_auto_register", "direct_ai_enabled"}
NUMBER_KEYS = {"code_ttl_seconds", "code_resend_seconds", "code_max_per_hour",
               "device_rate_limit", "credential_ttl_hours"}

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'viewer',
  enabled INTEGER NOT NULL DEFAULT 1,
  email_verified INTEGER NOT NULL DEFAULT 0,
  failed_attempts INTEGER NOT NULL DEFAULT 0,
  locked_until REAL NOT NULL DEFAULT 0,
  created_at REAL NOT NULL,
  last_login_at REAL
);
CREATE TABLE IF NOT EXISTS codes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  target TEXT NOT NULL, purpose TEXT NOT NULL, code_hash TEXT NOT NULL,
  expires_at REAL NOT NULL, consumed INTEGER NOT NULL DEFAULT 0,
  attempts INTEGER NOT NULL DEFAULT 0, ip TEXT, created_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_codes_target ON codes(target, purpose, created_at);
CREATE TABLE IF NOT EXISTS tokens (
  token_hash TEXT PRIMARY KEY, user_id INTEGER NOT NULL,
  expires_at REAL NOT NULL, created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS models (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL, kind TEXT NOT NULL,
  provider TEXT NOT NULL DEFAULT '', base_url TEXT NOT NULL DEFAULT '',
  endpoint TEXT NOT NULL DEFAULT '', model TEXT NOT NULL DEFAULT '',
  api_key_enc TEXT NOT NULL DEFAULT '',
  supports_image_input INTEGER NOT NULL DEFAULT 0,
  supports_image_edit INTEGER NOT NULL DEFAULT 0,
  timeout_seconds INTEGER NOT NULL DEFAULT 90, temperature REAL NOT NULL DEFAULT 0.3,
  enabled INTEGER NOT NULL DEFAULT 1, is_default INTEGER NOT NULL DEFAULT 0,
  last_ok_at REAL, last_ok_ms INTEGER, last_error TEXT NOT NULL DEFAULT '',
  last_error_at REAL, note TEXT NOT NULL DEFAULT '',
  created_at REAL NOT NULL, updated_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_models_kind ON models(kind, enabled);
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS audit_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  actor_id INTEGER, actor_name TEXT NOT NULL DEFAULT '',
  action TEXT NOT NULL, target TEXT NOT NULL DEFAULT '',
  detail TEXT NOT NULL DEFAULT '', ip TEXT NOT NULL DEFAULT '', created_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_logs_time ON audit_logs(created_at);
CREATE TABLE IF NOT EXISTS devices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id TEXT NOT NULL UNIQUE, token_hash TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '', platform TEXT NOT NULL DEFAULT '',
  app_version TEXT NOT NULL DEFAULT '', enabled INTEGER NOT NULL DEFAULT 1,
  call_count INTEGER NOT NULL DEFAULT 0,
  created_at REAL NOT NULL, last_seen_at REAL
);
"""

ACTION_LABELS = {
    "user.register": "注册账号",
    "user.login": "登录",
    "user.logout": "退出登录",
    "user.login_failed": "登录失败",
    "user.update": "修改用户权限",
    "user.reset": "重置密码",
    "code.send": "发送验证码",
    "model.create": "新增模型",
    "model.update": "修改模型",
    "model.delete": "删除模型",
    "model.toggle": "启用/停用模型",
    "model.default": "设置默认模型",
    "model.test": "测试模型连通",
    "settings.update": "修改系统设置",
    "device.register": "App 设备接入",
    "device.toggle": "启用/停用设备",
    "device.delete": "移除设备",
    "credential.issue": "下发直连凭证",
    "ai.vision": "AI 拆衣",
    "ai.text": "AI 风格分析",
    "ai.edit": "AI 试穿",
    "ai.avatar": "照片数字人生成",
    "white_bg.generate": "白底图生成",
}


# ---------------------------------------------------------------- 数据库

def _migrate(conn: sqlite3.Connection) -> None:
    """老库升级：缺列就补，绝不删数据。"""
    def cols(table: str) -> set[str]:
        try:
            return {r[1] for r in conn.execute(f"PRAGMA table_info({table})")}
        except sqlite3.Error:
            return set()

    model_cols = cols("models")
    for name, ddl in {
        "api_key_enc": "TEXT NOT NULL DEFAULT ''",
        "last_ok_at": "REAL",
        "last_ok_ms": "INTEGER",
        "last_error": "TEXT NOT NULL DEFAULT ''",
        "last_error_at": "REAL",
    }.items():
        if model_cols and name not in model_cols:
            conn.execute(f"ALTER TABLE models ADD COLUMN {name} {ddl}")


@contextmanager
def db():
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=15)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    with db() as c:
        c.executescript(SCHEMA)
        _migrate(c)
        for k, v in DEFAULT_SETTINGS.items():
            c.execute("INSERT OR IGNORE INTO settings(key,value) VALUES(?,?)", (k, v))


def setting(key: str, default: str = "") -> str:
    with db() as c:
        row = c.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    return row["value"] if row else default


def setting_bool(key: str, default: bool = False) -> bool:
    return str(setting(key, "1" if default else "0")).lower() in ("1", "true", "yes", "on")


def setting_int(key: str, default: int) -> int:
    try:
        return int(setting(key, str(default)))
    except ValueError:
        return default


def sha(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def fail(status: int, message: str) -> None:
    raise HTTPException(status_code=status, detail=message)


def client_ip(request: Request) -> str:
    # nginx 用 $proxy_add_x_forwarded_for 会把真实客户端 IP 追加到末尾；
    # 取首段等于信任客户端自报的伪造值（可污染审计日志/IP 记录），取末段才是可信代理观察到的来源。
    fwd = request.headers.get("x-forwarded-for", "")
    return fwd.split(",")[-1].strip() if fwd else (request.client.host if request.client else "")


def audit(request: Optional[Request], actor: Optional[sqlite3.Row], action: str,
          target: str = "", detail: str = "") -> None:
    ip = client_ip(request) if request is not None else ""
    actor_id = actor["id"] if actor else None
    actor_name = actor["username"] if actor else "App 设备"
    with db() as c:
        c.execute(
            "INSERT INTO audit_logs(actor_id,actor_name,action,target,detail,ip,created_at)"
            " VALUES(?,?,?,?,?,?,?)",
            (actor_id, actor_name, action, str(target)[:120], str(detail)[:500], ip, time.time()))


# ---------------------------------------------------------------- 密码 / 令牌 / 权限

def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", (password + SECRET).encode(), salt.encode(), 120_000).hex()
    return f"pbkdf2${salt}${digest}"


def check_password(password: str, stored: str) -> bool:
    try:
        _, salt, digest = stored.split("$", 2)
    except ValueError:
        return False
    calc = hashlib.pbkdf2_hmac(
        "sha256", (password + SECRET).encode(), salt.encode(), 120_000).hex()
    return hmac.compare_digest(calc, digest)


def issue_token(user_id: int) -> tuple[str, int]:
    raw = secrets.token_urlsafe(32)
    ttl = 7 * 24 * 3600
    with db() as c:
        c.execute("INSERT INTO tokens(token_hash,user_id,expires_at,created_at) VALUES(?,?,?,?)",
                  (sha(raw), user_id, time.time() + ttl, time.time()))
        c.execute("DELETE FROM tokens WHERE expires_at < ?", (time.time(),))
    return raw, ttl


def current_user(authorization: Optional[str] = Header(None)) -> sqlite3.Row:
    if not authorization or not authorization.lower().startswith("bearer "):
        fail(401, "请先登录")
    with db() as c:
        row = c.execute(
            "SELECT u.* FROM tokens t JOIN users u ON u.id=t.user_id"
            " WHERE t.token_hash=? AND t.expires_at>?",
            (sha(authorization[7:].strip()), time.time())).fetchone()
    if not row:
        fail(401, "登录已过期，请重新登录")
    if not row["enabled"]:
        fail(403, "账号已被停用，请联系管理员")
    return row


def require(level: int):
    def dep(user: sqlite3.Row = Depends(current_user)) -> sqlite3.Row:
        if ROLE_LEVEL.get(user["role"], 0) < level:
            need = {1: "成员", 2: "管理员", 3: "超级管理员"}.get(level, "管理员")
            fail(403, f"权限不足：该操作需要{need}权限")
        return user
    return dep


def public_user(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"], "username": row["username"], "email": row["email"],
        "role": row["role"], "role_label": ROLE_LABELS.get(row["role"], row["role"]),
        "enabled": bool(row["enabled"]), "email_verified": bool(row["email_verified"]),
        "created_at": row["created_at"], "last_login_at": row["last_login_at"],
    }


# ---------------------------------------------------------------- 验证码

def deliver_code(target: str, code: str, purpose: str) -> tuple[bool, str]:
    if SMTP_HOST and SMTP_FROM:
        label = {"register": "注册", "login": "登录", "reset": "找回密码"}.get(purpose, "验证")
        msg = EmailMessage()
        msg["Subject"], msg["From"], msg["To"] = "衣橱管家验证码", SMTP_FROM, target
        ttl = setting_int("code_ttl_seconds", 600)
        window = f"{ttl // 60} 分钟" if ttl >= 60 else f"{ttl} 秒"
        msg.set_content(
            f"你正在进行{label}操作，验证码：{code}\n"
            f"{window}内有效。若非本人操作请忽略。")
        try:
            if SMTP_PORT == 465:
                with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, timeout=10) as s:
                    if SMTP_USER:
                        s.login(SMTP_USER, SMTP_PASS)
                    s.send_message(msg)
            else:
                with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=10) as s:
                    s.starttls()
                    if SMTP_USER:
                        s.login(SMTP_USER, SMTP_PASS)
                    s.send_message(msg)
            return False, "验证码已发送到邮箱"
        except Exception as exc:  # noqa: BLE001
            fail(502, f"邮件发送失败：{exc}")
    if DEV_CODE:
        return True, "邮件服务未配置，验证码直接显示（上线前请配置 SMTP）"
    fail(503, "邮件服务未配置，请联系管理员配置 SMTP 或关闭邮箱验证")


def consume_code(target: str, purpose: str, code: str) -> bool:
    if not code or not re.fullmatch(r"\d{6}", code.strip()):
        return False
    with db() as c:
        row = c.execute(
            "SELECT * FROM codes WHERE target=? AND purpose=? AND consumed=0 AND expires_at>?"
            " ORDER BY created_at DESC LIMIT 1", (target, purpose, time.time())).fetchone()
        if not row:
            return False
        if row["attempts"] >= 5:
            c.execute("UPDATE codes SET consumed=1 WHERE id=?", (row["id"],))
            return False
        c.execute("UPDATE codes SET attempts=attempts+1 WHERE id=?", (row["id"],))
        if not hmac.compare_digest(row["code_hash"], sha(code.strip() + SECRET)):
            return False
        c.execute("UPDATE codes SET consumed=1 WHERE id=?", (row["id"],))
        return True


# ---------------------------------------------------------------- 模型密钥加密

def _aead() -> AESGCM:
    return AESGCM(hashlib.sha256((SECRET + "|wm-model-key-v1").encode()).digest())


def encrypt_secret(plain: str) -> str:
    if not plain:
        return ""
    nonce = os.urandom(12)
    ct = _aead().encrypt(nonce, plain.encode(), b"wm-model")
    return "v1:" + base64.urlsafe_b64encode(nonce + ct).decode()


def decrypt_secret(blob: str) -> str:
    if not blob:
        return ""
    if not blob.startswith("v1:"):
        return ""
    try:
        raw = base64.urlsafe_b64decode(blob[3:].encode())
        return _aead().decrypt(raw[:12], raw[12:], b"wm-model").decode()
    except Exception:  # noqa: BLE001
        return ""


def mask_key(plain: str) -> str:
    if not plain:
        return ""
    if len(plain) <= 10:
        return plain[:2] + "****"
    return f"{plain[:5]}****{plain[-4:]}"


def model_row_secret(row: sqlite3.Row) -> str:
    return decrypt_secret(row["api_key_enc"] or "")


def model_public(row: sqlite3.Row, *, with_key_hint: bool = True) -> dict[str, Any]:
    """后台视图：不含明文密钥，只给掩码和配置状态。"""
    key = model_row_secret(row) if with_key_hint else ""
    return {
        "id": row["id"], "name": row["name"], "kind": row["kind"],
        "kind_label": MODEL_KINDS.get(row["kind"], row["kind"]),
        "provider": row["provider"], "base_url": row["base_url"],
        "endpoint": row["endpoint"], "model": row["model"],
        "api_key_set": bool(key), "api_key_hint": mask_key(key),
        "supports_image_input": bool(row["supports_image_input"]),
        "supports_image_edit": bool(row["supports_image_edit"]),
        "timeout_seconds": row["timeout_seconds"], "temperature": row["temperature"],
        "enabled": bool(row["enabled"]), "is_default": bool(row["is_default"]),
        "note": row["note"],
        "last_ok_at": row["last_ok_at"], "last_ok_ms": row["last_ok_ms"],
        "last_error": row["last_error"], "last_error_at": row["last_error_at"],
        "updated_at": row["updated_at"],
    }


def pick_model(kind: str, model_id: Optional[int] = None) -> Optional[sqlite3.Row]:
    """选模型：指定优先，其次默认，最后第一个启用的。避免停用默认后整类不可用。"""
    with db() as c:
        if model_id:
            row = c.execute("SELECT * FROM models WHERE id=? AND enabled=1 AND kind=?",
                            (model_id, kind)).fetchone()
            if row:
                return row
        row = c.execute(
            "SELECT * FROM models WHERE enabled=1 AND kind=?"
            " ORDER BY is_default DESC, id ASC LIMIT 1", (kind,)).fetchone()
    return row


def kind_ready(kind: str) -> bool:
    """该类型是否可用：有启用模型 + 有可用密钥。"""
    row = pick_model(kind)
    return bool(row and model_row_secret(row))


def provider_url(row: sqlite3.Row, default_endpoint: str) -> str:
    base = (row["base_url"] or "").rstrip("/")
    endpoint = (row["endpoint"] or "").strip() or default_endpoint
    if not endpoint.startswith("/"):
        endpoint = "/" + endpoint
    return base + endpoint
