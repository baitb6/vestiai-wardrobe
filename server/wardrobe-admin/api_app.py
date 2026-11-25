"""App 端接口：设备接入、服务配置、AI 统一代理与直连凭证下发（v1.9）。

App 用户不需要注册任何账号，也不需要填模型地址和密钥；
所有 AI 能力由管理员在后台配置，代理链路只做转发（老版本 App 继续可用）。

v1.9：管理员开启「允许 App 直连」后，设备凭据可申请一次短时直连凭证
（五类默认模型的 base_url / model / endpoint / 解密明文 Key，App 写入手机安全存储），
之后图片类 AI 请求由 App 直连厂商，图片不再经过服务器。
撤销语义：停用设备（连代理一并拒绝）或关闭开关（停发新凭证），
已下发的凭证到 TTL 自动失效，App 过期后回代理链路重新申请。
明文 Key 只出现在 /api/app/credential 的响应里，绝不写审计与日志。
"""
from __future__ import annotations

import base64
import json
import secrets
import sqlite3
import time
from collections import defaultdict, deque
from typing import Any, Optional

import httpx
from fastapi import (APIRouter, Depends, File, Form, Header, Request, UploadFile)
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, Field

from core import (MODEL_KINDS, audit, client_ip, db, fail, kind_ready,
                  model_row_secret, pick_model, provider_url, setting,
                  setting_bool, setting_int, sha)

router = APIRouter(prefix="/api/app", tags=["app"])

_RATE: dict[str, deque] = defaultdict(deque)
_DEV_REG: dict[str, deque] = defaultdict(deque)


def _limit_device_register(request: Request) -> None:
    """设备注册端点不需要任何凭据：按来源 IP 限速，防刷库、防批量换取设备凭据。"""
    bucket = _DEV_REG[client_ip(request)]
    now = time.time()
    while bucket and now - bucket[0] > 3600:
        bucket.popleft()
    if len(bucket) >= 10:
        fail(429, "该网络接入设备过于频繁，请一小时后再试")
    bucket.append(now)

WHITE_BG_PROMPT = (
    "Generate a clean e-commerce product photo of the garment in the uploaded image. "
    "Keep the garment's design, color, material texture, pattern and details accurate. "
    "Remove the person, body, hands, hanger, room, props, shadows, text and watermark. "
    "Place one complete garment centered on a pure white background (#FFFFFF), "
    "front-facing, evenly lit, natural proportions, small even margin. "
    "Do not invent garments or change the color."
)

VISION_HINT = (
    "You are the vision step of a wardrobe app. Look at the outfit photo and split it "
    "into individual garments. Reply with JSON only."
)


class DeviceIn(BaseModel):
    device_id: str = Field(min_length=8, max_length=64)
    platform: str = ""
    app_version: str = ""
    name: str = ""


def _config_payload() -> dict[str, Any]:
    ai_on = setting_bool("ai_service_enabled", True)
    mode = setting("white_bg_mode", "local")
    return {
        "ok": True,
        "ai": {
            "enabled": ai_on,
            # v1.9：App 可据此决定是否尝试申请直连凭证（关闭则回代理链路）
            "direct": ai_on and setting_bool("direct_ai_enabled", True),
            "vision": ai_on and kind_ready("vision"),
            "text": ai_on and kind_ready("text"),
            "edit": ai_on and kind_ready("edit"),
            "white_bg": ai_on and kind_ready("white_bg"),
            "avatar": ai_on and (kind_ready("avatar") or kind_ready("edit")),
        },
        "white_bg": {
            "mode": mode,
            "server": mode == "server" and ai_on and kind_ready("white_bg"),
            "enabled": mode != "off",
        },
        "notice": setting("app_notice", ""),
        "min_version": setting("app_min_version", ""),
        "server_time": time.time(),
        "api_version": "1.9.0",
    }


def app_device(authorization: Optional[str] = Header(None)) -> sqlite3.Row:
    if not authorization or not authorization.lower().startswith("bearer "):
        fail(401, "设备未接入，请在 App 内重新连接服务")
    raw = authorization[7:].strip()
    with db() as c:
        row = c.execute("SELECT * FROM devices WHERE token_hash=?", (sha(raw),)).fetchone()
        if not row:
            fail(401, "设备凭据无效，请在 App 内重新连接服务")
        if not row["enabled"]:
            fail(403, "这台设备已被管理员停用")
        c.execute("UPDATE devices SET last_seen_at=? WHERE id=?", (time.time(), row["id"]))
    return row


def _limit(device: sqlite3.Row) -> None:
    cap = max(1, setting_int("device_rate_limit", 30))
    bucket = _RATE[str(device["id"])]
    now = time.time()
    while bucket and now - bucket[0] > 60:
        bucket.popleft()
    if len(bucket) >= cap:
        fail(429, f"请求太频繁，每分钟最多 {cap} 次，请稍后再试")
    bucket.append(now)


@router.post("/device")
def register_device(body: DeviceIn, request: Request):
    """App 首次启动自动接入。用户看不到任何账号密码。"""
    if not setting_bool("ai_service_enabled", True):
        fail(403, "管理员暂未开放 AI 服务")
    _limit_device_register(request)
    with db() as c:
        existing = c.execute("SELECT * FROM devices WHERE device_id=?",
                             (body.device_id,)).fetchone()
        if not existing and not setting_bool("device_auto_register", True):
            fail(403, "管理员已关闭新设备自动接入，请联系管理员添加")
        token = secrets.token_urlsafe(32)
        now = time.time()
        if existing:
            if not existing["enabled"]:
                fail(403, "这台设备已被管理员停用")
            c.execute(
                "UPDATE devices SET token_hash=?, platform=?, app_version=?, "
                "name=COALESCE(NULLIF(?, ''), name), last_seen_at=? WHERE id=?",
                (sha(token), body.platform[:40], body.app_version[:20],
                 body.name[:60], now, existing["id"]))
            did = existing["id"]
        else:
            try:
                cur = c.execute(
                    "INSERT INTO devices(device_id,token_hash,name,platform,app_version,"
                    "enabled,created_at,last_seen_at) VALUES(?,?,?,?,?,1,?,?)",
                    (body.device_id, sha(token), body.name[:60] or f"{body.platform or '未知'} 设备",
                     body.platform[:40], body.app_version[:20], now, now))
            except sqlite3.IntegrityError:
                # 并发接入撞了 device_id 唯一约束：前置 SELECT 存在竞态窗口
                fail(409, "该设备正在接入，请稍后重试")
            did = cur.lastrowid
    audit(request, None, "device.register", body.name or body.device_id,
          f"platform={body.platform}, version={body.app_version}")
    return {"ok": True, "token": token, "config": _config_payload(),
            "message": "已连接服务"}


@router.get("/config")
def app_config(device: sqlite3.Row = Depends(app_device)):
    return _config_payload()


def _credential_endpoint(row: sqlite3.Row, kind: str) -> str:
    """直连凭证里的 endpoint：显式配置优先；否则按协议与用途给默认值。

    App 用 base_url + endpoint 拼出厂商 URL，镜像服务端代理的选路规则：
    vision/text 走 chat/completions，图像编辑类走 images/edits（方舟等
    特殊网关由管理员显式填 endpoint），Gemini 自动拼 generateContent。
    """
    endpoint = (row["endpoint"] or "").strip()
    if endpoint:
        if _is_gemini(row):
            # 与 _gemini_url 相同的简写语义归一，凭证拿到的就是完整可请求路径：
            # 含 generateContent 的按完整路径/「:」简写处理，其余当路径前缀
            if "generatecontent" in endpoint.lower():
                if endpoint.startswith(":"):
                    return f"/models/{row['model'] or ''}{endpoint}"
                return endpoint if endpoint.startswith("/") else "/" + endpoint
            tail = "/" + endpoint.strip("/")
            return f"{tail}/models/{row['model'] or ''}:generateContent"
        return endpoint if endpoint.startswith("/") else "/" + endpoint
    if _is_gemini(row):
        return f"/models/{row['model'] or ''}:generateContent"
    if kind in ("vision", "text"):
        return "/chat/completions"
    return "/images/edits"


@router.post("/credential")
def issue_credential(request: Request, device: sqlite3.Row = Depends(app_device)):
    """v1.9：向设备下发一次短时直连凭证（五类默认模型的直连参数，含解密明文 Key）。

    安全取舍：
    - 明文 Key 只出现在本接口的响应里，绝不写审计日志、绝不进 /api/app/config；
    - 凭证离线有效到 TTL；撤销靠「停用设备 / 关闭 direct_ai_enabled」停发新凭证，
      已下发的凭证到期自动失效（服务器不维护吊销名单，App 到期重新申请）；
    - 只下发 enabled 且有密钥的默认模型（pick_model 逻辑），与后台模型启停实时一致。
    """
    _limit(device)
    if not setting_bool("ai_service_enabled", True):
        fail(403, "管理员暂未开放 AI 服务")
    if not setting_bool("direct_ai_enabled", True):
        fail(403, "管理员已关闭 App 直连，请继续使用服务器代理")
    ttl = setting_int("credential_ttl_hours", 24)
    ttl = max(1, min(168, ttl))  # 设置被手改坏时兜底，防凭证长期有效
    models: dict[str, Any] = {}
    for kind in MODEL_KINDS:
        # avatar 未单独配置时复用 edit 默认模型，与代理端点 app_avatar 的选路一致
        row = pick_model(kind) or (pick_model("edit") if kind == "avatar" else None)
        if not row:
            continue
        key = model_row_secret(row)
        if not key:
            continue
        models[kind] = {
            "base_url": (row["base_url"] or "").rstrip("/"),
            "model": row["model"] or "",
            "api_key": key,  # 解密明文：仅此接口下发（设计意图，见 README「密钥安全」）
            "endpoint": _credential_endpoint(row, kind),
        }
    expires_at = time.time() + ttl * 3600
    audit(request, None, "credential.issue", device["name"] or device["device_id"],
          f"device={device['device_id']}, kinds={','.join(models) or 'none'}, ttl={ttl}h")
    return {"ok": True, "expires_at": expires_at, "ttl_hours": ttl, "models": models,
            "message": f"直连凭证已下发，{ttl} 小时内有效，到期请重新申请"}


def _detect_kind(payload: dict[str, Any]) -> str:
    for m in payload.get("messages") or []:
        if not isinstance(m, dict):
            continue
        content = m.get("content")
        if isinstance(content, list):
            for part in content:
                if isinstance(part, dict) and part.get("type") in ("image_url", "input_image"):
                    return "vision"
        elif isinstance(content, str) and "image_url" in content:
            return "vision"
    return "text"


def _upstream_error(status: int, text: str) -> str:
    snippet = (text or "").strip().replace("\n", " ")[:200]
    if status == 401:
        return "模型密钥无效或已过期，请联系管理员在后台更新"
    if status == 403:
        return "模型拒绝访问，可能是密钥权限或额度问题，请联系管理员"
    if status == 404:
        return "接口地址或模型 ID 不正确，请联系管理员检查"
    if status == 429:
        return "模型调用太频繁或额度已用完，请稍后再试"
    if status >= 500:
        return f"模型服务异常（HTTP {status}），请稍后再试"
    return f"模型返回错误 HTTP {status}：{snippet}"


# ---------------- Gemini 原生 generateContent 协议适配（v1.9） ----------------

def _is_gemini(row: sqlite3.Row) -> bool:
    """Gemini 原生协议：provider 填 gemini，或 endpoint 里带 generateContent。"""
    provider = (row["provider"] or "").strip().lower()
    return provider == "gemini" or "generatecontent" in (row["endpoint"] or "").lower()


def _gemini_url(row: sqlite3.Row) -> str:
    """Gemini 请求地址：模型 ID 进 URL 路径（{base}/models/{model}:generateContent）。

    endpoint 允许三种填法：留空（默认）、路径前缀（如 /v1beta）、
    或带 generateContent 的完整路径（如 /models/x:generateContent）。
    """
    base = (row["base_url"] or "").rstrip("/")
    endpoint = (row["endpoint"] or "").strip()
    if endpoint and "generatecontent" in endpoint.lower():
        if endpoint.startswith(":"):
            return f"{base}/models/{row['model'] or ''}{endpoint}"
        return base + (endpoint if endpoint.startswith("/") else "/" + endpoint)
    model = row["model"] or ""
    tail = "/" + endpoint.strip("/") if endpoint else ""
    return f"{base}{tail}/models/{model}:generateContent"


def _image_url_to_gemini_part(url: Any) -> Optional[dict[str, Any]]:
    """OpenAI image_url → Gemini part：data: URI 转 inlineData，http(s) 转 fileData。"""
    if not isinstance(url, str) or not url:
        return None
    if url.startswith("data:"):
        head, _, data = url.partition(",")
        mime = head[5:].split(";", 1)[0] or "image/png"
        return {"inlineData": {"mimeType": mime, "data": data}}
    if url.startswith(("http://", "https://")):
        return {"fileData": {"fileUri": url}}
    return None


def _openai_to_gemini(payload: dict[str, Any]) -> dict[str, Any]:
    """OpenAI chat/completions 请求体 → Gemini generateContent 请求体。

    system/developer 消息合并为 systemInstruction；assistant → model 角色；
    image_url（base64 data URI）→ inlineData；temperature/max_tokens/top_p →
    generationConfig（字段名按 Gemini 规范：maxOutputTokens / topP）。
    """
    system_parts: list[dict[str, Any]] = []
    contents: list[dict[str, Any]] = []
    for m in payload.get("messages") or []:
        if not isinstance(m, dict):
            continue
        parts: list[dict[str, Any]] = []
        content = m.get("content")
        if isinstance(content, str):
            if content:
                parts.append({"text": content})
        elif isinstance(content, list):
            for p in content:
                if not isinstance(p, dict):
                    continue
                if p.get("type") in ("image_url", "input_image"):
                    iu = p.get("image_url")
                    url = iu.get("url") if isinstance(iu, dict) else iu
                    part = _image_url_to_gemini_part(url)
                    if part:
                        parts.append(part)
                elif isinstance(p.get("text"), str) and p["text"]:
                    parts.append({"text": p["text"]})
        if not parts:
            continue
        if m.get("role") in ("system", "developer"):
            system_parts.extend(parts)
        else:
            contents.append({
                "role": "model" if m.get("role") == "assistant" else "user",
                "parts": parts})
    body: dict[str, Any] = {"contents": contents}
    if system_parts:
        body["systemInstruction"] = {"parts": system_parts}
    gen: dict[str, Any] = {}
    if isinstance(payload.get("temperature"), (int, float)):
        gen["temperature"] = payload["temperature"]
    if isinstance(payload.get("max_tokens"), int):
        gen["maxOutputTokens"] = payload["max_tokens"]
    if isinstance(payload.get("top_p"), (int, float)):
        gen["topP"] = payload["top_p"]
    if gen:
        body["generationConfig"] = gen
    return body


def _gemini_to_openai(data: dict[str, Any], model_id: str) -> dict[str, Any]:
    """Gemini generateContent 响应 → OpenAI choices 格式（App 端零改动）。

    多个 text part 拼接为 content；finishReason 映射为 OpenAI 的 finish_reason；
    usageMetadata 映射为 usage 三元组。
    """
    message: dict[str, Any] = {"role": "assistant", "content": ""}
    finish = "stop"
    candidates = data.get("candidates") or []
    if candidates and isinstance(candidates[0], dict):
        texts = [p["text"] for p in ((candidates[0].get("content") or {}).get("parts") or [])
                 if isinstance(p, dict) and isinstance(p.get("text"), str)]
        message["content"] = "".join(texts)
        reason = str(candidates[0].get("finishReason") or "").upper()
        finish = {"MAX_TOKENS": "length", "SAFETY": "content_filter",
                  "RECITATION": "content_filter"}.get(reason, "stop")
    um = data.get("usageMetadata") if isinstance(data.get("usageMetadata"), dict) else {}
    return {
        "id": f"gemini-{int(time.time() * 1000)}",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model_id,
        "choices": [{"index": 0, "message": message, "finish_reason": finish}],
        "usage": {
            "prompt_tokens": um.get("promptTokenCount", 0) or 0,
            "completion_tokens": um.get("candidatesTokenCount", 0) or 0,
            "total_tokens": um.get("totalTokenCount", 0) or 0},
    }


def _gemini_error_message(text: str) -> str:
    """提取 Gemini 错误信封 {"error": {"code", "status", "message"}} 里的人话。"""
    try:
        data = json.loads(text or "")
    except Exception:  # noqa: BLE001
        return ""
    err = data.get("error") if isinstance(data, dict) else None
    if isinstance(err, dict):
        status = str(err.get("status") or "")
        msg = str(err.get("message") or "")
        return f"{status}: {msg}" if status and msg else (msg or status)
    if isinstance(err, str):
        return err
    return ""


@router.post("/ai/v1/chat/completions")
async def proxy_chat(request: Request, device: sqlite3.Row = Depends(app_device)):
    """兼容 OpenAI 协议：App 端不用改 payload，只把地址换成这里。

    v1.9：模型为 Gemini 原生 generateContent 时自动做双向协议转换
    （OpenAI ↔ Gemini，x-goog-api-key 头），App 端依旧零改动。
    """
    _limit(device)
    if not setting_bool("ai_service_enabled", True):
        fail(403, "管理员暂未开放 AI 服务")
    try:
        payload = await request.json()
    except Exception:  # noqa: BLE001
        fail(400, "请求内容不是合法 JSON")
    if not isinstance(payload, dict):
        # OpenAI 协议的 body 必须是 JSON 对象；数组/字符串/数字会让下游 payload.get 直接 500
        fail(400, "请求内容必须是 JSON 对象")
    kind = _detect_kind(payload)
    row = pick_model(kind)
    if not row:
        fail(503, "管理员还没有配置可用的" + ("视觉识别" if kind == "vision" else "文本") + "模型")
    from core import model_row_secret
    key = model_row_secret(row)
    if not key:
        fail(503, "该模型缺少密钥，请联系管理员在后台补充")
    gemini = _is_gemini(row)
    if gemini:
        url = _gemini_url(row)
        headers = {"x-goog-api-key": key}
        body = _openai_to_gemini(payload)
    else:
        payload["model"] = row["model"] or payload.get("model") or "gpt-4o-mini"
        payload.pop("stream", None)
        url = provider_url(row, "/chat/completions")
        headers = {"Authorization": f"Bearer {key}"}
        body = payload
    started = time.time()
    try:
        async with httpx.AsyncClient(timeout=row["timeout_seconds"] or 90) as client:
            r = await client.post(url, headers=headers, json=body)
    except httpx.TimeoutException:
        fail(504, "模型响应超时，请稍后再试")
    except httpx.HTTPError as exc:
        fail(502, f"连不上模型服务：{exc.__class__.__name__}")
    if r.status_code >= 300:
        audit(request, None, f"ai.{kind}", row["name"], f"HTTP {r.status_code}")
        # Gemini 错误信封 {"error":{"message"}} → 统一中文提示；
        # Gemini 对无效 Key 常回 400 而非 401，按人话识别后归一到密钥提示
        detail = _gemini_error_message(r.text) if gemini else ""
        if gemini and r.status_code in (400, 401, 403) and "api key" in detail.lower():
            fail(502, "模型密钥无效或已过期，请联系管理员在后台更新")
        fail(502, _upstream_error(r.status_code, detail or r.text))
    with db() as c:
        c.execute("UPDATE devices SET call_count=call_count+1 WHERE id=?", (device["id"],))
        c.execute("UPDATE models SET last_ok_at=?, last_ok_ms=?, last_error='' WHERE id=?",
                  (time.time(), int((time.time() - started) * 1000), row["id"]))
    audit(request, None, f"ai.{kind}", row["name"],
          f"device={device['device_id']}, {int((time.time()-started)*1000)}ms")
    # 2xx 但内容不是 JSON（如 base_url 配错拿到 HTML 落地页）按失败处理，
    # 不再把上游错误包成 200 application/json 发给 App
    try:
        r.json()
    except Exception:  # noqa: BLE001
        fail(502, "模型返回的内容无法识别，请稍后再试")
    if gemini:
        try:
            gjson = r.json()
        except Exception:  # noqa: BLE001
            fail(502, "模型返回的内容无法识别，请稍后再试")
        if not isinstance(gjson, dict):
            fail(502, "模型返回的内容无法识别，请稍后再试")
        feedback = gjson.get("promptFeedback")
        block = str(feedback.get("blockReason")) \
            if isinstance(feedback, dict) and feedback.get("blockReason") else ""
        if not gjson.get("candidates") and block:
            fail(502, f"模型拒绝了这次请求（{block}），请换张照片或稍后再试")
        return JSONResponse(_gemini_to_openai(gjson, row["model"] or ""))
    return Response(content=r.content, media_type="application/json")


async def _fetch_image(url: str) -> bytes:
    async with httpx.AsyncClient(timeout=60) as client:
        r = await client.get(url)
        r.raise_for_status()
        return r.content


def _is_ark(row: sqlite3.Row) -> bool:
    """豆包 / 火山方舟 Seedream：必须走官方 /images/generations JSON 接口。"""
    provider = (row["provider"] or "").strip().lower()
    base = (row["base_url"] or "").lower()
    return provider in ("doubao", "volcengine", "ark") \
        or "/images/generations" in (row["endpoint"] or "").lower() \
        or "volces.com" in base


async def _read_image(image: UploadFile) -> bytes:
    """统一图片校验：坏文件直接 400，不再浪费一次模型调用去失败。"""
    data = await image.read(12 * 1024 * 1024 + 1)
    if len(data) > 12 * 1024 * 1024:
        fail(413, "图片不能超过 12 MB")
    is_png = data[:8] == b"\x89PNG\r\n\x1a\n"
    is_jpg = data[:2] == b"\xff\xd8"
    is_webp = data[:4] == b"RIFF" and data[8:12] == b"WEBP"
    if not (is_png or is_jpg or is_webp):
        fail(400, "只支持 JPG / PNG / WEBP 图片，请换一张照片重试")
    return data


# 图像生成整链总预算（秒）：留 10s 余量给响应回传，避免撞 nginx 180s
# proxy_read_timeout 被掐成 HTML 504、白付上游生成费
_IMAGE_TOTAL_BUDGET = 170.0


async def _run_image_edit(row: sqlite3.Row, key: str, data: bytes,
                          prompt: str, size: str = "1024x1024",
                          _retried: bool = False,
                          _budget_end: float = 0.0) -> bytes:
    """豆包/方舟走官方 generations JSON；OpenAI 兼容网关先 /images/edits 再退回对话。

    超时重试带总预算（_budget_end 为本轮请求链的截止时刻）：上游偶发拥堵时
    自动重试一次，但 90s×2 会撞 nginx 180s 读超时被掐成 HTML 504、白付生成费，
    因此重试前检查剩余预算，不足 10 秒直接按超时失败，不再发起注定被掐的请求。
    """
    base_headers = {"Authorization": f"Bearer {key}"}
    if not _budget_end:
        _budget_end = time.time() + _IMAGE_TOTAL_BUDGET
    remaining = _budget_end - time.time()

    def _retry_or_fail(msg: str):
        """超时后先看预算：够就重试一次（含剩余时限），不够直接失败。"""
        if not _retried and _budget_end - time.time() >= 10:
            return _run_image_edit(row, key, data, prompt, size, True, _budget_end)
        fail(504, msg)

    if _is_ark(row):
        try:
            timeout = max(5.0, min(row["timeout_seconds"] or 120, remaining))
            async with httpx.AsyncClient(timeout=timeout) as client:
                r = await client.post(
                    provider_url(row, "/images/generations"), headers=base_headers,
                    json={
                        "model": row["model"] or "",
                        "prompt": prompt,
                        "image": "data:image/png;base64," +
                                 base64.b64encode(data).decode(),
                        "size": "1024x1024",  # 2K 生成要 2 分钟且 5MB；App 卡片 1K 足够（实测 10s vs 127s）
                        "response_format": "b64_json",
                        "output_format": "png",
                        "watermark": False})
            if r.status_code >= 400:
                fail(502, _upstream_error(r.status_code, r.text))
            return await _extract_image(r)
        except httpx.TimeoutException:
            await _retry_or_fail("图像生成超时，请稍后重试")
        except httpx.HTTPError as exc:
            fail(502, f"连不上模型服务：{exc.__class__.__name__}")
    edits_url = provider_url(row, "/images/edits")
    try:
        timeout = max(5.0, min(row["timeout_seconds"] or 120, remaining))
        async with httpx.AsyncClient(timeout=timeout) as client:
            r = await client.post(
                edits_url, headers=base_headers,
                data={"model": row["model"] or "", "prompt": prompt,
                      "size": size, "n": "1", "response_format": "b64_json"},
                files={"image": ("garment.png", data, "image/png")})
            if r.status_code in (404, 405):
                r = await client.post(
                    provider_url(row, "/chat/completions"), headers=base_headers,
                    json={"model": row["model"] or "",
                          "messages": [{"role": "user", "content": [
                              {"type": "text", "text": prompt},
                              {"type": "image_url", "image_url": {
                                  "url": "data:image/png;base64," +
                                         base64.b64encode(data).decode()}}]}],
                          "modalities": ["image", "text"]})
            if r.status_code >= 400:
                fail(502, _upstream_error(r.status_code, r.text))
            return await _extract_image(r)
    except httpx.TimeoutException:
        await _retry_or_fail("图像生成超时，请稍后重试")
    except httpx.HTTPError as exc:
        fail(502, f"连不上模型服务：{exc.__class__.__name__}")


async def _extract_image(resp: httpx.Response) -> bytes:
    ctype = resp.headers.get("content-type", "")
    if ctype.startswith("image/"):
        return resp.content
    try:
        payload = resp.json()
    except Exception:  # noqa: BLE001
        fail(502, "模型返回的内容无法识别，请确认该模型支持图像输出")
    candidates: list[str] = []
    data = payload.get("data")
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                if item.get("b64_json"):
                    candidates.append("b64:" + item["b64_json"])
                elif item.get("url"):
                    candidates.append("url:" + item["url"])
    for ch in payload.get("choices") or []:
        content = (ch.get("message") or {}).get("content")
        if isinstance(content, list):
            for part in content:
                if isinstance(part, dict) and part.get("type") in (
                        "image_url", "output_image", "image"):
                    url = ((part.get("image_url") or {}).get("url")
                           or part.get("url") or "")
                    if url.startswith("data:"):
                        candidates.append("b64:" + url.split(",", 1)[-1])
                    elif url:
                        candidates.append("url:" + url)
    for cand in candidates:
        try:
            if cand.startswith("b64:"):
                raw = base64.b64decode(cand[4:])
            else:
                raw = await _fetch_image(cand[4:])
            if raw and len(raw) > 200:
                return raw
        except Exception:  # noqa: BLE001
            continue
    fail(502, "模型没有返回图片，可能这个模型不支持图像编辑")


@router.post("/ai/v1/images/edits")
async def proxy_edit(request: Request, image: UploadFile = File(...),
                     prompt: str = Form(""), device: sqlite3.Row = Depends(app_device)):
    _limit(device)
    if not setting_bool("ai_service_enabled", True):
        fail(403, "管理员暂未开放 AI 服务")
    data = await _read_image(image)
    row = pick_model("edit")
    if not row:
        fail(503, "管理员还没有配置可用的图像编辑模型")
    from core import model_row_secret
    key = model_row_secret(row)
    if not key:
        fail(503, "该模型缺少密钥，请联系管理员在后台补充")
    started = time.time()
    raw = await _run_image_edit(row, key, data, prompt or "Try this outfit on the model.")
    with db() as c:
        c.execute("UPDATE devices SET call_count=call_count+1 WHERE id=?", (device["id"],))
        c.execute("UPDATE models SET last_ok_at=?, last_ok_ms=? WHERE id=?",
                  (time.time(), int((time.time() - started) * 1000), row["id"]))
    audit(request, None, "ai.edit", row["name"],
          f"device={device['device_id']}, bytes={len(data)}, {int((time.time()-started)*1000)}ms")
    return Response(content=raw,
                    media_type="image/png" if raw[:8] == b"\x89PNG\r\n\x1a\n" else "image/jpeg",
                    headers={"X-Model-Name": row["name"], "Cache-Control": "no-store"})


@router.post("/white-bg")
async def app_white_bg(request: Request, image: UploadFile = File(...),
                       device: sqlite3.Row = Depends(app_device)):
    """后台代跑白底图：只在内存处理，不写入磁盘、不入库。"""
    mode = setting("white_bg_mode", "local")
    if mode == "off":
        # 功能整体关闭（连手机本地也关）：别再指引用户去点本地处理
        fail(403, "管理员已关闭白底图功能")
    if mode != "server":
        fail(403, "管理员未开启「后台代跑白底图」，请用手机本地处理")
    _limit(device)
    if not setting_bool("ai_service_enabled", True):
        fail(403, "管理员暂未开放 AI 服务")
    data = await _read_image(image)
    row = pick_model("white_bg")
    if not row:
        fail(503, "管理员还没有配置白底图模型")
    from core import model_row_secret
    key = model_row_secret(row)
    if not key:
        fail(503, "白底图模型缺少密钥，请联系管理员补充")
    started = time.time()
    raw = await _run_image_edit(row, key, data, WHITE_BG_PROMPT)
    with db() as c:
        c.execute("UPDATE devices SET call_count=call_count+1 WHERE id=?", (device["id"],))
        c.execute("UPDATE models SET last_ok_at=?, last_ok_ms=? WHERE id=?",
                  (time.time(), int((time.time() - started) * 1000), row["id"]))
    audit(request, None, "white_bg.generate", row["name"],
          f"device={device['device_id']}, bytes={len(data)}, {int((time.time()-started)*1000)}ms")
    return Response(content=raw,
                    media_type="image/png" if raw[:8] == b"\x89PNG\r\n\x1a\n" else "image/jpeg",
                    headers={"X-Model-Name": row["name"], "Cache-Control": "no-store"})


@router.post("/avatar")
async def app_avatar(request: Request, image: UploadFile = File(...),
                     device: sqlite3.Row = Depends(app_device)):
    """照片数字人：用本人全身照生成多视角形象。只走内存，不落盘、不下发模型名。"""
    _limit(device)
    if not setting_bool("ai_service_enabled", True):
        fail(403, "管理员暂未开放 AI 服务")
    data = await _read_image(image)
    row = pick_model("avatar") or pick_model("edit")
    if not row:
        fail(503, "管理员还没有配置数字人或试穿模型")
    from core import model_row_secret
    key = model_row_secret(row)
    if not key:
        fail(503, "该模型缺少密钥，请联系管理员在后台补充")
    prompt = (
        "Use the uploaded full-body photo as the identity reference. Create ONE single "
        "horizontal image with exactly three panels of the SAME adult person side by side: "
        "front view, three-quarter view, back view. Keep the same face, hairstyle, skin tone, "
        "body proportions and outfit in every panel. Full body from head to toe, consistent "
        "scale, natural relaxed standing pose, clean warm-grey studio background, soft even "
        "lighting. No text, no watermark, no borders, no extra people."
    )
    started = time.time()
    raw = await _run_image_edit(row, key, data, prompt)
    with db() as c:
        c.execute("UPDATE devices SET call_count=call_count+1 WHERE id=?", (device["id"],))
        c.execute("UPDATE models SET last_ok_at=?, last_ok_ms=? WHERE id=?",
                  (time.time(), int((time.time() - started) * 1000), row["id"]))
    audit(request, None, "ai.avatar", row["name"],
          f"device={device['device_id']}, bytes={len(data)}, {int((time.time()-started)*1000)}ms")
    return Response(content=raw,
                    media_type="image/png" if raw[:8] == b"\x89PNG\r\n\x1a\n" else "image/jpeg",
                    headers={"Cache-Control": "no-store"})
