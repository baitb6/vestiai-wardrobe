"""管理端：系统设置、用户权限、模型配置、连通测试、设备、操作日志。"""
from __future__ import annotations

import re
import sqlite3
import time
from datetime import datetime
from typing import Any, Optional

import httpx
from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field

from core import (ACTION_LABELS, DEV_CODE, KIND_HINTS, MODEL_KINDS, NUMBER_KEYS,
                  ROLE_LABELS, ROLE_LEVEL, SETTING_KEYS, SMTP_HOST, SWITCH_KEYS,
                  audit, db, encrypt_secret, fail, mask_key, model_public,
                  model_row_secret, pick_model, provider_url, public_user,
                  require, setting, setting_bool, kind_ready)

router = APIRouter(prefix="/api/admin", tags=["admin"])

WHITE_BG_MODE_LABELS = {"local": "手机本地处理（数据不出手机）",
                        "server": "后台代跑（更快，图片经服务器转发）",
                        "off": "关闭白底图"}


class SettingIn(BaseModel):
    key: str
    value: str


class UserPatch(BaseModel):
    role: Optional[str] = None
    enabled: Optional[bool] = None


class ModelIn(BaseModel):
    name: str = Field(min_length=1, max_length=60)
    kind: str
    provider: str = ""
    base_url: str = ""
    endpoint: str = ""
    model: str = ""
    api_key: str = ""          # 留空 = 不修改已有密钥
    clear_key: bool = False
    supports_image_input: bool = False
    supports_image_edit: bool = False
    timeout_seconds: int = 90
    temperature: float = 0.3
    enabled: bool = True
    is_default: bool = False
    note: str = ""


def validate_model(body: ModelIn) -> None:
    if body.kind not in MODEL_KINDS:
        fail(400, "模型类型不合法")
    if not body.name.strip():
        fail(400, "请填写模型名称，方便自己辨认")
    if not body.base_url.strip():
        fail(400, "请填写接口地址（Base URL），例如 https://api.openai.com/v1")
    if not body.model.strip():
        fail(400, "请填写模型 ID，例如 gpt-4o / qwen-vl-max")
    if not body.base_url.strip().startswith(("http://", "https://")):
        fail(400, "接口地址要以 http:// 或 https:// 开头")
    if not 5 <= body.timeout_seconds <= 600:
        fail(400, "超时时间需在 5-600 秒之间")
    if not 0 <= body.temperature <= 2:
        fail(400, "temperature 需在 0-2 之间")
    if body.api_key.strip() and len(body.api_key.strip()) < 8:
        fail(400, "API Key 看起来太短，请检查是否粘贴完整")


def normalize_caps(body: ModelIn) -> ModelIn:
    """按用途补全能力标记：视觉/编辑类天然需要图片。"""
    if body.kind == "vision":
        body.supports_image_input = True
    elif body.kind in ("edit", "avatar", "white_bg"):
        body.supports_image_input = True
        body.supports_image_edit = True
    return body


def _ensure_single_default(c: sqlite3.Connection, kind: str, model_id: int) -> None:
    c.execute("UPDATE models SET is_default=0 WHERE kind=? AND id<>?", (kind, model_id))


def _ensure_any_default(c: sqlite3.Connection, kind: str) -> None:
    """一类模型至少要有一个默认，否则 App 端会以为没配置。"""
    row = c.execute("SELECT id FROM models WHERE kind=? AND is_default=1 AND enabled=1",
                    (kind,)).fetchone()
    if row:
        return
    row = c.execute("SELECT id FROM models WHERE kind=? AND enabled=1 ORDER BY id LIMIT 1",
                    (kind,)).fetchone()
    if row:
        c.execute("UPDATE models SET is_default=1 WHERE id=?", (row["id"],))


# ---------------- 设置 ----------------

@router.get("/settings")
def get_settings(user: sqlite3.Row = Depends(require(1))):
    with db() as c:
        rows = c.execute("SELECT * FROM settings").fetchall()
    return {"ok": True, "settings": {r["key"]: r["value"] for r in rows},
            "keys": sorted(SETTING_KEYS),
            "white_bg_modes": [{"key": k, "label": v} for k, v in WHITE_BG_MODE_LABELS.items()]}


@router.put("/settings")
def put_setting(body: SettingIn, request: Request,
                user: sqlite3.Row = Depends(require(3))):
    if body.key not in SETTING_KEYS:
        fail(400, "未知的设置项")
    value = body.value.strip()
    if body.key in NUMBER_KEYS:
        try:
            n = int(value)
        except ValueError:
            fail(400, "这一项需要填数字")
        if body.key == "code_ttl_seconds":
            lo, hi = 10, 86400
        elif body.key == "credential_ttl_hours":
            lo, hi = 1, 168   # v1.9 直连凭证有效期：最短 1 小时，最长一周
        else:
            lo, hi = 1, 86400
        if not lo <= n <= hi:
            fail(400, f"数值需在 {lo}-{hi} 之间")
        if body.key == "code_max_per_hour" and n > 100:
            fail(400, "每小时上限不要超过 100 次")
    elif body.key in SWITCH_KEYS:
        if value not in ("0", "1"):
            fail(400, "开关只能用 0 或 1")
    elif body.key == "white_bg_mode":
        if value not in WHITE_BG_MODE_LABELS:
            fail(400, "白底图模式不合法")
    elif body.key == "app_notice":
        value = value[:300]
    with db() as c:
        c.execute("UPDATE settings SET value=? WHERE key=?", (value, body.key))
    audit(request, user, "settings.update", body.key, f"{body.key}={value}")
    return {"ok": True, "message": "已保存", "key": body.key, "value": value}


# ---------------- 用户与权限 ----------------

@router.get("/users")
def list_users(user: sqlite3.Row = Depends(require(3))):
    with db() as c:
        rows = c.execute("SELECT * FROM users ORDER BY id").fetchall()
    return {"ok": True, "users": [public_user(r) for r in rows],
            "roles": [{"key": k, "label": v} for k, v in ROLE_LABELS.items()]}


@router.patch("/users/{uid}")
def patch_user(uid: int, body: UserPatch, request: Request,
               user: sqlite3.Row = Depends(require(3))):
    if uid == user["id"] and (body.role is not None or body.enabled is False):
        fail(400, "不能改自己的角色，也不能停用自己")
    if body.role is not None and body.role not in ROLE_LEVEL:
        fail(400, "角色不合法")
    with db() as c:
        row = c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
        if not row:
            fail(404, "用户不存在")
        role = body.role if body.role is not None else row["role"]
        enabled = int(body.enabled) if body.enabled is not None else row["enabled"]
        c.execute("UPDATE users SET role=?, enabled=? WHERE id=?", (role, enabled, uid))
        if not enabled:
            c.execute("DELETE FROM tokens WHERE user_id=?", (uid,))
        fresh = c.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
    audit(request, user, "user.update", row["username"], f"role={role}, enabled={enabled}")
    return {"ok": True, "user": public_user(fresh), "message": "已更新"}


# ---------------- 模型 ----------------

@router.get("/models")
def list_models(user: sqlite3.Row = Depends(require(1))):
    with db() as c:
        rows = c.execute(
            "SELECT * FROM models ORDER BY kind, is_default DESC, id").fetchall()
    return {
        "ok": True,
        "models": [model_public(r) for r in rows],
        "kinds": [{"key": k, "label": v, "hint": KIND_HINTS.get(k, "")} for k, v in MODEL_KINDS.items()],
        "ready": {k: kind_ready(k) for k in MODEL_KINDS},
    }


@router.post("/models")
def create_model(body: ModelIn, request: Request,
                 user: sqlite3.Row = Depends(require(2))):
    validate_model(body)
    body = normalize_caps(body)
    now = time.time()
    enc = "" if body.clear_key or not body.api_key.strip() else encrypt_secret(body.api_key.strip())
    with db() as c:
        make_default = body.is_default
        if not c.execute("SELECT 1 FROM models WHERE kind=? AND enabled=1",
                         (body.kind,)).fetchone():
            make_default = True  # 该类第一个启用的自动成为默认
        cur = c.execute(
            "INSERT INTO models(name,kind,provider,base_url,endpoint,model,api_key_enc,"
            "supports_image_input,supports_image_edit,timeout_seconds,temperature,"
            "enabled,is_default,note,created_at,updated_at)"
            " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (body.name.strip(), body.kind, body.provider.strip(), body.base_url.strip(),
             body.endpoint.strip(), body.model.strip(), enc,
             int(body.supports_image_input or body.kind in ("vision", "edit", "avatar", "white_bg")),
             int(body.supports_image_edit or body.kind in ("edit", "avatar", "white_bg")),
             body.timeout_seconds, body.temperature, int(body.enabled),
             int(make_default), body.note.strip(), now, now))
        mid = cur.lastrowid
        if make_default:
            _ensure_single_default(c, body.kind, mid)
        if not body.enabled:
            # 新建即停用时不保留默认标记，与 update_model 的行为对齐，
            # 避免「停用的模型仍挂着默认」这种脏状态
            c.execute("UPDATE models SET is_default=0 WHERE id=?", (mid,))
        _ensure_any_default(c, body.kind)
        row = c.execute("SELECT * FROM models WHERE id=?", (mid,)).fetchone()
    audit(request, user, "model.create", body.name, f"kind={body.kind}, id={mid}")
    return {"ok": True, "model": model_public(row), "message": "模型已添加"}


@router.put("/models/{mid}")
def update_model(mid: int, body: ModelIn, request: Request,
                 user: sqlite3.Row = Depends(require(2))):
    validate_model(body)
    body = normalize_caps(body)
    now = time.time()
    with db() as c:
        old = c.execute("SELECT * FROM models WHERE id=?", (mid,)).fetchone()
        if not old:
            fail(404, "模型不存在")
        enc = old["api_key_enc"]
        if body.clear_key:
            enc = ""
        elif body.api_key.strip():
            enc = encrypt_secret(body.api_key.strip())
        c.execute(
            "UPDATE models SET name=?,kind=?,provider=?,base_url=?,endpoint=?,model=?,"
            "api_key_enc=?,supports_image_input=?,supports_image_edit=?,timeout_seconds=?,"
            "temperature=?,enabled=?,is_default=?,note=?,updated_at=? WHERE id=?",
            (body.name.strip(), body.kind, body.provider.strip(), body.base_url.strip(),
             body.endpoint.strip(), body.model.strip(), enc,
             int(body.supports_image_input), int(body.supports_image_edit),
             body.timeout_seconds, body.temperature, int(body.enabled),
             int(body.is_default), body.note.strip(), now, mid))
        if body.is_default and body.enabled:
            _ensure_single_default(c, body.kind, mid)
        if old["kind"] != body.kind:
            _ensure_any_default(c, old["kind"])
        _ensure_any_default(c, body.kind)
        if not body.enabled:
            c.execute("UPDATE models SET is_default=0 WHERE id=?", (mid,))
            _ensure_any_default(c, body.kind)
        row = c.execute("SELECT * FROM models WHERE id=?", (mid,)).fetchone()
    audit(request, user, "model.update", body.name,
          f"id={mid}, enabled={body.enabled}, key_changed={bool(body.api_key.strip())}")
    return {"ok": True, "model": model_public(row), "message": "已保存"}


@router.delete("/models/{mid}")
def delete_model(mid: int, request: Request,
                 user: sqlite3.Row = Depends(require(3))):
    with db() as c:
        row = c.execute("SELECT * FROM models WHERE id=?", (mid,)).fetchone()
        if not row:
            fail(404, "模型不存在")
        c.execute("DELETE FROM models WHERE id=?", (mid,))
        _ensure_any_default(c, row["kind"])
    audit(request, user, "model.delete", row["name"], f"id={mid}")
    return {"ok": True, "message": "已删除"}


@router.post("/models/{mid}/toggle")
def toggle_model(mid: int, request: Request,
                 user: sqlite3.Row = Depends(require(2))):
    with db() as c:
        row = c.execute("SELECT * FROM models WHERE id=?", (mid,)).fetchone()
        if not row:
            fail(404, "模型不存在")
        enabled = 0 if row["enabled"] else 1
        c.execute("UPDATE models SET enabled=?, updated_at=? WHERE id=?",
                  (enabled, time.time(), mid))
        if not enabled:
            c.execute("UPDATE models SET is_default=0 WHERE id=?", (mid,))
        _ensure_any_default(c, row["kind"])
        fresh = c.execute("SELECT * FROM models WHERE id=?", (mid,)).fetchone()
    audit(request, user, "model.toggle", row["name"], f"enabled={enabled}")
    return {"ok": True, "model": model_public(fresh),
            "message": "已启用" if enabled else "已停用"}


@router.post("/models/{mid}/default")
def set_default(mid: int, request: Request,
                user: sqlite3.Row = Depends(require(2))):
    with db() as c:
        row = c.execute("SELECT * FROM models WHERE id=?", (mid,)).fetchone()
        if not row:
            fail(404, "模型不存在")
        if not row["enabled"]:
            fail(400, "停用的模型不能设为默认，请先启用")
        c.execute("UPDATE models SET is_default=0 WHERE kind=?", (row["kind"],))
        c.execute("UPDATE models SET is_default=1, updated_at=? WHERE id=?",
                  (time.time(), mid))
        fresh = c.execute("SELECT * FROM models WHERE id=?", (mid,)).fetchone()
    audit(request, user, "model.default", row["name"], f"kind={row['kind']}, id={mid}")
    return {"ok": True, "model": model_public(fresh), "message": "已设为默认"}


def _record_result(mid: int, ok: bool, ms: int, err: str) -> None:
    with db() as c:
        if ok:
            c.execute("UPDATE models SET last_ok_at=?, last_ok_ms=?, last_error='', "
                      "last_error_at=NULL WHERE id=?", (time.time(), ms, mid))
        else:
            c.execute("UPDATE models SET last_error=?, last_error_at=? WHERE id=?",
                      (err[:300], time.time(), mid))


@router.post("/models/{mid}/test")
async def test_model(mid: int, request: Request,
                     user: sqlite3.Row = Depends(require(2))):
    """连通性测试：不产生业务数据，尽量少花钱。"""
    with db() as c:
        row = c.execute("SELECT * FROM models WHERE id=?", (mid,)).fetchone()
    if not row:
        fail(404, "模型不存在")
    key = model_row_secret(row)
    if not key:
        fail(400, "这个模型还没填 API Key，先填上再测试")
    base = (row["base_url"] or "").rstrip("/")
    if not base:
        fail(400, "接口地址为空")
    started = time.time()
    detail = ""
    # Gemini 的鉴权头是 x-goog-api-key，Authorization Bearer 一律 401，
    # 会把有效 Key 误报成「密钥被拒绝」
    from api_app import _is_gemini
    test_headers = ({"x-goog-api-key": key} if _is_gemini(row)
                    else {"Authorization": f"Bearer {key}"})
    try:
        async with httpx.AsyncClient(timeout=min(row["timeout_seconds"] or 30, 45)) as client:
            r = await client.get(f"{base}/models",
                                 headers=test_headers)
            if r.status_code in (200, 401, 403):
                if r.status_code == 401:
                    raise RuntimeError("密钥被拒绝（HTTP 401），请检查 Key 是否正确")
                if r.status_code == 403:
                    raise RuntimeError("该 Key 没有访问权限（HTTP 403）")
                ids = []
                try:
                    ids = [m.get("id", "") for m in (r.json().get("data") or [])][:5]
                except Exception:  # noqa: BLE001
                    pass
                detail = "模型列表可访问" + (f"，例如：{', '.join(x for x in ids if x)}" if ids else "")
            elif row["kind"] in ("edit", "avatar", "white_bg") and r.status_code in (404, 405):
                # 方舟等图像服务没有 /models；能收到明确响应即可，测试不生成计费图片。
                detail = "服务地址可访问；图像模型未产生计费调用"
            else:
                # 文本/视觉网关不提供 /models：用一次最小对话请求验证
                url = provider_url(row, "/chat/completions")
                payload = {"model": row["model"] or "gpt-4o-mini",
                           "messages": [{"role": "user", "content": "ping"}],
                           "max_tokens": 1}
                r2 = await client.post(url, headers={"Authorization": f"Bearer {key}"},
                                       json=payload)
                if r2.status_code == 401:
                    raise RuntimeError("密钥被拒绝（HTTP 401），请检查 Key 是否正确")
                if r2.status_code >= 400:
                    raise RuntimeError(f"网关返回 HTTP {r2.status_code}：{r2.text[:160]}")
                detail = "对话接口可访问"
    except Exception as exc:  # noqa: BLE001
        ms = int((time.time() - started) * 1000)
        msg = str(exc) if str(exc) else exc.__class__.__name__
        _record_result(mid, False, ms, msg)
        audit(request, user, "model.test", row["name"], f"failed: {msg[:200]}")
        return {"ok": False, "message": f"连接失败：{msg}", "elapsed_ms": ms}
    ms = int((time.time() - started) * 1000)
    _record_result(mid, True, ms, "")
    audit(request, user, "model.test", row["name"], f"ok: {detail}, {ms}ms")
    return {"ok": True, "message": f"连接正常（{ms} ms）· {detail}", "elapsed_ms": ms}


# ---------------- 设备 ----------------

@router.get("/devices")
def list_devices(user: sqlite3.Row = Depends(require(2))):
    with db() as c:
        rows = c.execute("SELECT * FROM devices ORDER BY last_seen_at DESC, id DESC").fetchall()
    return {"ok": True, "devices": [{
        "id": r["id"], "device_id": r["device_id"], "name": r["name"],
        "platform": r["platform"], "app_version": r["app_version"],
        "enabled": bool(r["enabled"]), "call_count": r["call_count"],
        "created_at": r["created_at"], "last_seen_at": r["last_seen_at"],
    } for r in rows]}


@router.post("/devices/{did}/toggle")
def toggle_device(did: int, request: Request,
                  user: sqlite3.Row = Depends(require(2))):
    with db() as c:
        row = c.execute("SELECT * FROM devices WHERE id=?", (did,)).fetchone()
        if not row:
            fail(404, "设备不存在")
        enabled = 0 if row["enabled"] else 1
        c.execute("UPDATE devices SET enabled=? WHERE id=?", (enabled, did))
    audit(request, user, "device.toggle", row["name"] or row["device_id"],
          f"enabled={enabled}")
    return {"ok": True, "message": "已启用" if enabled else "已停用"}


@router.delete("/devices/{did}")
def delete_device(did: int, request: Request,
                  user: sqlite3.Row = Depends(require(3))):
    with db() as c:
        row = c.execute("SELECT * FROM devices WHERE id=?", (did,)).fetchone()
        if not row:
            fail(404, "设备不存在")
        c.execute("DELETE FROM devices WHERE id=?", (did,))
    audit(request, user, "device.delete", row["name"] or row["device_id"], "已移除")
    return {"ok": True, "message": "已移除该设备"}


# ---------------- 操作日志 ----------------

@router.get("/logs")
def list_logs(limit: int = 100, action: str = "", keyword: str = "",
              user: sqlite3.Row = Depends(require(2))):
    limit = max(1, min(limit, 500))
    sql = "SELECT * FROM audit_logs WHERE 1=1"
    args: list[Any] = []
    if action:
        sql += " AND action=?"
        args.append(action)
    if keyword:
        sql += " AND (target LIKE ? OR detail LIKE ? OR actor_name LIKE ?)"
        args += [f"%{keyword}%"] * 3
    sql += " ORDER BY id DESC LIMIT ?"
    args.append(limit)
    with db() as c:
        rows = c.execute(sql, args).fetchall()
    logs = []
    for r in rows:
        d = dict(r)
        d["action_label"] = ACTION_LABELS.get(r["action"], r["action"])
        logs.append(d)
    return {"ok": True, "logs": logs, "count": len(logs),
            "actions": [{"key": k, "label": v} for k, v in ACTION_LABELS.items()]}


@router.get("/summary")
def summary(user: sqlite3.Row = Depends(require(1))):
    with db() as c:
        users = c.execute("SELECT COUNT(*) n FROM users").fetchone()["n"]
        models = c.execute("SELECT COUNT(*) n FROM models").fetchone()["n"]
        on = c.execute("SELECT COUNT(*) n FROM models WHERE enabled=1").fetchone()["n"]
        logs = c.execute("SELECT COUNT(*) n FROM audit_logs").fetchone()["n"]
        devices = c.execute("SELECT COUNT(*) n FROM devices").fetchone()["n"]
        recent = c.execute("SELECT COUNT(*) n FROM devices WHERE last_seen_at > ?",
                           (time.time() - 7 * 86400,)).fetchone()["n"]
        # 今日 AI 调用：App 端经代理完成的模型请求数（按本地零点起算）。
        # v1.9 口径修正：只统计代理流量；开启 App 直连后，直连厂商的调用
        # 不经过本服务器、不产生这里的审计记录，因此不在此列。
        today_start = datetime.now().replace(
            hour=0, minute=0, second=0, microsecond=0).timestamp()
        ai_today = c.execute(
            "SELECT COUNT(*) n FROM audit_logs WHERE action IN"
            " ('ai.vision','ai.text','ai.edit','ai.avatar','white_bg.generate')"
            " AND created_at > ?", (today_start,)).fetchone()["n"]
        # 今日下发直连凭证：credential.issue 审计数，与代理流量分开统计
        cred_today = c.execute(
            "SELECT COUNT(*) n FROM audit_logs WHERE action='credential.issue'"
            " AND created_at > ?", (today_start,)).fetchone()["n"]
    mode = setting("white_bg_mode", "local")
    return {
        "ok": True, "users": users, "models": models, "models_enabled": on,
        "logs": logs, "devices": devices, "devices_active": recent,
        "ai_calls_today": ai_today,        # 仅代理流量（直连调用不在此列）
        "credentials_today": cred_today,
        "ready": {k: kind_ready(k) for k in MODEL_KINDS},
        "email_verification": setting_bool("email_verification", True),
        "ai_service_enabled": setting_bool("ai_service_enabled", True),
        "white_bg_mode": mode, "white_bg_mode_label": WHITE_BG_MODE_LABELS.get(mode, mode),
        "dev_mode": DEV_CODE and not SMTP_HOST,
        "smtp_configured": bool(SMTP_HOST),
    }
