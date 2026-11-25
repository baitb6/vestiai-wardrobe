"""管理后台接口测试（pytest）。运行：python3 -m pytest tests -q"""
import asyncio
import base64
import os
import tempfile
import time

import pytest
from fastapi.testclient import TestClient

_TMP = tempfile.mkdtemp(prefix="wm-admin-test-")
os.environ["WM_DB"] = os.path.join(_TMP, "test.db")
os.environ["WM_DEV_CODE"] = "1"
os.environ["WM_SECRET"] = "test-secret"

import core  # noqa: E402
import server  # noqa: E402

client = TestClient(server.app)


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def register(email, code_required=True, username=None, password="Passw0rd1"):
    username = username or ("u" + email.split("@")[0])
    payload = {"username": username, "password": password, "email": email, "code": ""}
    if code_required:
        r = client.post("/api/auth/code", json={"target": email, "purpose": "register"})
        assert r.status_code == 200, r.text
        payload["code"] = r.json()["dev_code"]
    return client.post("/api/auth/register", json=payload)


@pytest.fixture(scope="module", autouse=True)
def setup():
    with core.db() as c:
        for table in ("users", "codes", "models", "audit_logs", "devices", "tokens"):
            c.execute(f"DELETE FROM {table}")
        for k, v in core.DEFAULT_SETTINGS.items():
            c.execute("UPDATE settings SET value=? WHERE key=?", (v, k))
    yield


# ---------------- 公开 / 账号 ----------------

def test_01_public_config_has_no_model_info():
    r = client.get("/api/public/config")
    assert r.status_code == 200
    body = r.json()
    assert body["email_verification"] is True
    assert body["code_resend_seconds"] == 60
    # 公开接口绝不能泄露模型地址或密钥
    assert "models" not in body
    assert "base_url" not in str(body)


def test_02_register_needs_code_and_first_user_is_super_admin():
    bad = client.post("/api/auth/register", json={
        "username": "someone", "password": "Passw0rd1", "email": "a@b.com", "code": "123456"})
    assert bad.status_code == 400 and "验证码" in bad.json()["message"]
    r = register("boss@test.com", username="管理员")
    assert r.status_code == 200, r.text
    assert r.json()["user"]["role"] == "super_admin"
    globals()["ADMIN"] = r.json()["token"]
    globals()["ADMIN_ID"] = r.json()["user"]["id"]


def test_03_code_rate_limit_and_expiry():
    client.post("/api/auth/code", json={"target": "rate@test.com", "purpose": "register"})
    again = client.post("/api/auth/code", json={"target": "rate@test.com", "purpose": "register"})
    assert again.status_code == 429 and "频繁" in again.json()["message"]

    r = client.post("/api/auth/code", json={"target": "expire@test.com", "purpose": "register"})
    code = r.json()["dev_code"]
    with core.db() as c:
        c.execute("UPDATE codes SET expires_at=? WHERE target=?",
                  (time.time() - 1, "expire@test.com"))
    bad = client.post("/api/auth/register", json={
        "username": "expireuser", "password": "Passw0rd1",
        "email": "expire@test.com", "code": code})
    assert bad.status_code == 400 and "过期" in bad.json()["message"]


def test_04_login_code_can_use_username():
    """登录验证码允许填账号：后端应解析成邮箱再发信。"""
    r = client.post("/api/auth/code", json={"target": "管理员", "purpose": "login"})
    assert r.status_code == 200, r.text
    assert r.json()["sent_to"] == "boss@test.com"


def test_05_second_user_is_viewer_and_cannot_write():
    r = register("viewer@test.com")
    assert r.json()["user"]["role"] == "viewer"
    t = r.json()["token"]
    assert client.put("/api/admin/settings", headers=auth(t),
                      json={"key": "white_bg_mode", "value": "server"}).status_code == 403
    assert client.post("/api/admin/models", headers=auth(t), json={
        "name": "x", "kind": "vision"}).status_code == 403
    # 只读账号也不能看用户列表
    assert client.get("/api/admin/users", headers=auth(t)).status_code == 403


def test_06_login_lock_and_wrong_password():
    for _ in range(5):
        r = client.post("/api/auth/login", json={
            "username": "boss@test.com", "password": "wrongpass1"})
        assert r.status_code == 401
    locked = client.post("/api/auth/login", json={
        "username": "boss@test.com", "password": "Passw0rd1"})
    assert locked.status_code == 429
    with core.db() as c:
        c.execute("UPDATE users SET locked_until=0, failed_attempts=0 WHERE username='管理员'")
    ok = client.post("/api/auth/login", json={
        "username": "boss@test.com", "password": "Passw0rd1"})
    assert ok.status_code == 200


# ---------------- 模型 ----------------

def test_07_model_key_is_encrypted_and_never_echoed():
    h = auth(ADMIN)
    raw_key = "sk-live-abcdefghijklmnop"
    r = client.post("/api/admin/models", headers=h, json={
        "name": "视觉模型", "kind": "vision",
        "base_url": "https://api.example.com/v1", "model": "qwen-vl-max",
        "api_key": raw_key})
    assert r.status_code == 200, r.text
    mid = r.json()["model"]["id"]
    globals()["VISION_ID"] = mid

    body = r.json()["model"]
    assert raw_key not in str(body)
    assert body["api_key_set"] is True
    assert body["api_key_hint"].startswith("sk-li")
    assert body["is_default"] is True  # 该类第一个自动成为默认

    with core.db() as c:
        enc = c.execute("SELECT api_key_enc FROM models WHERE id=?", (mid,)).fetchone()[0]
    assert enc and enc.startswith("v1:")
    assert raw_key not in enc
    assert core.decrypt_secret(enc) == raw_key


def test_08_model_requires_base_url_and_model_id():
    h = auth(ADMIN)
    assert client.post("/api/admin/models", headers=h, json={
        "name": "缺地址", "kind": "text"}).status_code == 400
    assert client.post("/api/admin/models", headers=h, json={
        "name": "缺模型", "kind": "text",
        "base_url": "https://x.com/v1"}).status_code == 400


def test_09_update_without_key_keeps_old_key():
    h = auth(ADMIN)
    mid = VISION_ID
    r = client.put(f"/api/admin/models/{mid}", headers=h, json={
        "name": "视觉模型改名", "kind": "vision",
        "base_url": "https://api.example.com/v1", "model": "qwen-vl-plus"})
    assert r.status_code == 200
    assert r.json()["model"]["api_key_set"] is True
    assert r.json()["model"]["name"] == "视觉模型改名"

    cleared = client.put(f"/api/admin/models/{mid}", headers=h, json={
        "name": "清空密钥", "kind": "vision",
        "base_url": "https://api.example.com/v1", "model": "qwen-vl-plus",
        "clear_key": True})
    assert cleared.json()["model"]["api_key_set"] is False
    assert cleared.json()["model"]["api_key_hint"] == ""


def test_10_default_is_unique_and_survives_disable():
    h = auth(ADMIN)
    a = client.post("/api/admin/models", headers=h, json={
        "name": "文本A", "kind": "text", "base_url": "https://x.com/v1",
        "model": "a", "api_key": "sk-aaaaaaaaaaaa", "is_default": True}).json()["model"]["id"]
    b = client.post("/api/admin/models", headers=h, json={
        "name": "文本B", "kind": "text", "base_url": "https://x.com/v1",
        "model": "b", "api_key": "sk-bbbbbbbbbbbb", "is_default": True}).json()["model"]["id"]
    with core.db() as c:
        rows = c.execute("SELECT id FROM models WHERE kind='text' AND is_default=1").fetchall()
    assert len(rows) == 1 and rows[0]["id"] == b

    # 停用默认模型后，同类另一个应自动接棒，避免整类不可用
    client.post(f"/api/admin/models/{b}/toggle", headers=h)
    with core.db() as c:
        rows = c.execute("SELECT id FROM models WHERE kind='text' AND is_default=1").fetchall()
    assert len(rows) == 1 and rows[0]["id"] == a
    # 停用的模型不能设默认
    assert client.post(f"/api/admin/models/{b}/default", headers=h).status_code == 400


def test_11_model_readiness_reflects_key_and_switch():
    h = auth(ADMIN)
    ready = client.get("/api/admin/models", headers=h).json()["ready"]
    assert ready["vision"] is False      # 上一步把密钥清空了
    assert ready["text"] is True
    assert ready["edit"] is False


def test_12_model_connectivity_test_reports_failure_in_chinese():
    h = auth(ADMIN)
    mid = client.post("/api/admin/models", headers=h, json={
        "name": "坏地址", "kind": "text",
        "base_url": "https://127.0.0.1:9/v1", "model": "x",
        "api_key": "sk-cccccccccccc", "timeout_seconds": 5}).json()["model"]["id"]
    r = client.post(f"/api/admin/models/{mid}/test", headers=h)
    assert r.status_code == 200
    assert r.json()["ok"] is False
    assert "失败" in r.json()["message"]
    row = [m for m in client.get("/api/admin/models", headers=h).json()["models"]
           if m["id"] == mid][0]
    assert row["last_error"]


# ---------------- App 设备与代理 ----------------

def test_13_app_device_autoregister_and_config():
    r = client.post("/api/app/device", json={
        "device_id": "device-aaaa1111", "platform": "android",
        "app_version": "1.7.0", "name": "小王的手机"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["token"]
    cfg = body["config"]
    assert cfg["ai"]["text"] is True
    assert cfg["ai"]["edit"] is False
    assert "base_url" not in str(cfg)
    assert "key" not in str(cfg).lower().replace("api_version", "")
    globals()["DEVICE"] = body["token"]


def test_14_app_config_requires_device_token():
    assert client.get("/api/app/config").status_code == 401
    r = client.get("/api/app/config", headers=auth(DEVICE))
    assert r.status_code == 200 and r.json()["ai"]["enabled"] is True


def test_15_proxy_rejects_when_capability_missing():
    r = client.post("/api/app/ai/v1/images/edits", headers=auth(DEVICE),
                    files={"image": ("a.png", b"\x89PNG\r\n\x1a\n" + b"0" * 900, "image/png")},
                    data={"prompt": "try on"})
    assert r.status_code == 503
    assert "图像编辑" in r.json()["message"]


def test_16_proxy_returns_chinese_error_when_upstream_unreachable():
    r = client.post("/api/app/ai/v1/chat/completions", headers=auth(DEVICE),
                    json={"model": "auto", "messages": [{"role": "user", "content": "hi"}]})
    assert r.status_code in (502, 504)
    assert "模型" in r.json()["message"] or "连接" in r.json()["message"]


def test_17_device_disable_blocks_calls():
    h = auth(ADMIN)
    devices = client.get("/api/admin/devices", headers=h).json()["devices"]
    did = devices[0]["id"]
    client.post(f"/api/admin/devices/{did}/toggle", headers=h)
    assert client.get("/api/app/config", headers=auth(DEVICE)).status_code == 403
    client.post(f"/api/admin/devices/{did}/toggle", headers=h)
    assert client.get("/api/app/config", headers=auth(DEVICE)).status_code == 200


def test_18_ai_service_switch_blocks_new_devices():
    h = auth(ADMIN)
    client.put("/api/admin/settings", headers=h, json={
        "key": "ai_service_enabled", "value": "0"})
    r = client.post("/api/app/device", json={"device_id": "device-new-2222"})
    assert r.status_code == 403 and "未开放" in r.json()["message"]
    client.put("/api/admin/settings", headers=h, json={
        "key": "ai_service_enabled", "value": "1"})


def test_19_white_bg_mode_gate():
    h = auth(ADMIN)
    client.put("/api/admin/settings", headers=h, json={
        "key": "white_bg_mode", "value": "local"})
    r = client.post("/api/app/white-bg", headers=auth(DEVICE),
                    files={"image": ("a.png", b"\x89PNG\r\n\x1a\n" + b"0" * 900, "image/png")})
    assert r.status_code == 403 and "后台代跑" in r.json()["message"]
    client.put("/api/admin/settings", headers=h, json={
        "key": "white_bg_mode", "value": "server"})
    r2 = client.post("/api/app/white-bg", headers=auth(DEVICE),
                     files={"image": ("a.png", b"\x89PNG\r\n\x1a\n" + b"0" * 900, "image/png")})
    # 没配白底模型 → 503，但不能再是权限错误
    assert r2.status_code == 503


# ---------------- 设置 / 权限 / 日志 ----------------

def test_20_settings_validation_and_email_switch_hint():
    h = auth(ADMIN)
    assert client.put("/api/admin/settings", headers=h, json={
        "key": "white_bg_mode", "value": "weird"}).status_code == 400
    assert client.put("/api/admin/settings", headers=h, json={
        "key": "code_ttl_seconds", "value": "1"}).status_code == 400
    assert client.put("/api/admin/settings", headers=h, json={
        "key": "email_verification", "value": "0"}).status_code == 200
    cfg = client.get("/api/public/config").json()
    assert cfg["email_verification"] is False
    blocked = client.post("/api/auth/code", json={
        "target": "x@y.com", "purpose": "register"})
    assert blocked.status_code == 400 and "已关闭" in blocked.json()["message"]
    r = register("nocode@test.com", code_required=False)
    assert r.status_code == 200
    assert r.json()["user"]["email_verified"] is False
    assert "已关闭" in r.json()["message"]


def test_21_cannot_change_own_role_or_disable_self():
    h = auth(ADMIN)
    assert client.patch(f"/api/admin/users/{ADMIN_ID}", headers=h,
                        json={"role": "viewer"}).status_code == 400
    assert client.patch(f"/api/admin/users/{ADMIN_ID}", headers=h,
                        json={"enabled": False}).status_code == 400


def test_22_promote_viewer_to_admin():
    h = auth(ADMIN)
    users = client.get("/api/admin/users", headers=h).json()["users"]
    viewer = [u for u in users if u["username"] == "uviewer"][0]
    r = client.patch(f"/api/admin/users/{viewer['id']}", headers=h,
                     json={"role": "admin"})
    assert r.status_code == 200 and r.json()["user"]["role"] == "admin"


def test_23_audit_logs_are_chinese_and_filterable():
    h = auth(ADMIN)
    logs = client.get("/api/admin/logs?limit=200", headers=h).json()
    labels = {l["action"]: l["action_label"] for l in logs["logs"]}
    assert labels.get("model.create") == "新增模型"
    assert labels.get("device.register") == "App 设备接入"
    only = client.get("/api/admin/logs?action=model.update", headers=h).json()["logs"]
    assert all(l["action"] == "model.update" for l in only)


def test_24_summary_reports_readiness_and_devices():
    h = auth(ADMIN)
    s = client.get("/api/admin/summary", headers=h).json()
    assert s["devices"] >= 1
    assert set(s["ready"]) == {"vision", "text", "edit", "white_bg", "avatar"}
    assert s["white_bg_mode"] == "server"
    # 概览新字段：今日 AI 调用统计（数值本身随用例执行变动，只验证存在与非负）
    assert "ai_calls_today" in s and s["ai_calls_today"] >= 0


def test_25_health():
    assert client.get("/healthz").json()["ok"] is True
    assert client.get("/").status_code == 200


def test_26_doubao_seedream_uses_generations_and_avatar_proxy(monkeypatch):
    """方舟图生图必须走官方 generations JSON，不能误发 multipart edits。"""
    import api_app
    import httpx

    h = auth(ADMIN)
    created = client.post("/api/admin/models", headers=h, json={
        "name": "豆包数字人", "kind": "avatar", "provider": "doubao",
        "base_url": "https://ark.cn-beijing.volces.com/api/v3",
        "endpoint": "/images/generations", "model": "doubao-seedream-5-0-260128",
        "api_key": "ark-test-secret-key", "is_default": True})
    assert created.status_code == 200, created.text
    mid = created.json()["model"]["id"]
    cfg = client.get("/api/app/config", headers=auth(DEVICE)).json()
    assert cfg["ai"]["avatar"] is True
    assert "ark-test-secret-key" not in str(cfg)

    calls = []
    image = b"\x89PNG\r\n\x1a\n" + b"1" * 600

    class FakeClient:
        def __init__(self, *args, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def post(self, url, **kwargs):
            calls.append((url, kwargs))
            return httpx.Response(200, json={"data": [{
                "b64_json": base64.b64encode(image).decode()}]})

    monkeypatch.setattr(api_app.httpx, "AsyncClient", FakeClient)
    with core.db() as c:
        row = c.execute("SELECT * FROM models WHERE id=?", (mid,)).fetchone()
    raw = asyncio.run(api_app._run_image_edit(row, "ark-test-secret-key", image, "portrait"))
    assert raw == image
    url, kwargs = calls[0]
    assert url.endswith("/api/v3/images/generations")
    assert kwargs["json"]["image"].startswith("data:image/png;base64,")
    assert kwargs["json"]["size"] == "1024x1024"  # 2K 太慢（127s/5MB），1K 实测 10s
    assert kwargs["json"]["watermark"] is False
    assert kwargs["headers"]["Authorization"] == "Bearer ark-test-secret-key"

    response = client.post("/api/app/avatar", headers=auth(DEVICE),
        files={"image": ("me.png", image, "image/png")})
    assert response.status_code == 200, response.text
    assert response.content == image
    assert response.headers["cache-control"] == "no-store"
    assert "x-model-name" not in response.headers
    assert "ark-test-secret-key" not in str(response.headers)


def test_27_avatar_rejects_non_image_without_calling_model():
    r = client.post("/api/app/avatar", headers=auth(DEVICE),
        files={"image": ("fake.png", b"not-an-image" + b"0" * 900, "image/png")})
    assert r.status_code == 400
    assert "JPG" in r.json()["message"]


# ---------------- 本轮修复的回归测试 ----------------

def test_28_chat_proxy_rejects_non_object_json():
    """body 不是 JSON 对象（数组/标量）应 400，而不是在下游 .get 时抛 500。"""
    r = client.post("/api/app/ai/v1/chat/completions", headers=auth(DEVICE),
                    json=["array-not-object"])
    assert r.status_code == 400, r.text
    assert "JSON 对象" in r.json()["message"]
    r2 = client.post("/api/app/ai/v1/chat/completions", headers=auth(DEVICE),
                     json="plain-string")
    assert r2.status_code == 400 and "JSON 对象" in r2.json()["message"]


def test_29_device_registration_rate_limited_per_ip():
    """设备注册无需凭据，必须按来源 IP 限频，防止刷库/批量换凭据。"""
    import api_app
    api_app._DEV_REG.clear()
    for i in range(10):
        r = client.post("/api/app/device", json={"device_id": f"device-rl{i:03d}"})
        assert r.status_code == 200, r.text
    r = client.post("/api/app/device", json={"device_id": "device-rl-overflow"})
    assert r.status_code == 429 and "频繁" in r.json()["message"]


def test_30_validation_error_returns_422_envelope():
    """pydantic 校验失败统一返回 {ok, message} 的 422，而不是英文 detail 数组。"""
    r = client.post("/api/auth/register", json={"username": "abc"})
    assert r.status_code == 422, r.text
    body = r.json()
    assert body["ok"] is False and "password" in body["message"]


def test_31_client_ip_uses_last_xff_entry():
    """nginx 把真实客户端 IP 追加到 XFF 末尾，取首段会被客户端伪造。"""
    with core.db() as c:
        c.execute("UPDATE settings SET value='1' WHERE key='email_verification'")
    r = client.post("/api/auth/code",
                    json={"target": "xff@test.com", "purpose": "register"},
                    headers={"X-Forwarded-For": "1.2.3.4, 5.6.7.8"})
    assert r.status_code == 200, r.text
    with core.db() as c:
        ip = c.execute("SELECT ip FROM codes WHERE target='xff@test.com'"
                       " ORDER BY id DESC LIMIT 1").fetchone()["ip"]
    assert ip == "5.6.7.8"


def test_32_ai_switch_blocks_image_edit_and_white_bg():
    """AI 总开关必须拦住所有代理端点：图像编辑与白底图不能漏。"""
    h = auth(ADMIN)
    client.put("/api/admin/settings", headers=h, json={
        "key": "ai_service_enabled", "value": "0"})
    try:
        png = b"\x89PNG\r\n\x1a\n" + b"0" * 900
        r = client.post("/api/app/ai/v1/images/edits", headers=auth(DEVICE),
                        files={"image": ("a.png", png, "image/png")},
                        data={"prompt": "x"})
        assert r.status_code == 403 and "未开放" in r.json()["message"]
        # test_19 已把 white_bg_mode 设为 server，此时应被总开关拦下而非继续走模型
        r2 = client.post("/api/app/white-bg", headers=auth(DEVICE),
                         files={"image": ("a.png", png, "image/png")})
        assert r2.status_code == 403 and "未开放" in r2.json()["message"]
    finally:
        client.put("/api/admin/settings", headers=h, json={
            "key": "ai_service_enabled", "value": "1"})


# ---------------- v1.9：App 直连凭证 + Gemini 协议适配 ----------------

def test_33_credential_issue_returns_five_kinds_and_never_logs_keys():
    """正常下发：五类默认模型映射 + 解密明文 Key（设计意图，仅此接口），
    审计只记设备 / 用途列表 / TTL，绝不带明文 Key。"""
    h = auth(ADMIN)
    # 补齐缺密钥/缺配置的用途，保证五类齐全（text=文本A、avatar=豆包数字人 已存在）
    created = client.post("/api/admin/models", headers=h, json={
        "name": "Gemini 视觉", "kind": "vision", "provider": "gemini",
        "base_url": "https://generativelanguage.googleapis.com/v1beta",
        "model": "gemini-2.5-flash", "api_key": "gemini-test-key",
        "is_default": True})
    assert created.status_code == 200, created.text
    for name, kind in [("试穿模型", "edit"), ("白底模型", "white_bg")]:
        r = client.post("/api/admin/models", headers=h, json={
            "name": name, "kind": kind, "base_url": "https://api.example.com/v1",
            "model": "img-" + kind, "api_key": "sk-" + kind + "-key"})
        assert r.status_code == 200, r.text

    r = client.post("/api/app/credential", headers=auth(DEVICE))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["ok"] is True
    assert set(body["models"]) == {"vision", "text", "edit", "avatar", "white_bg"}
    # 明文 Key 下发是设计意图：仅此接口、仅默认模型
    assert body["models"]["vision"]["api_key"] == "gemini-test-key"
    assert body["models"]["text"]["api_key"] == "sk-aaaaaaaaaaaa"
    assert body["models"]["avatar"]["api_key"] == "ark-test-secret-key"
    assert body["models"]["edit"]["api_key"] == "sk-edit-key"
    for m in body["models"].values():
        assert m["base_url"].startswith("https://")
        assert m["model"] and m["endpoint"].startswith("/")
    # Gemini 未显式填 endpoint 时自动拼 /models/{model}:generateContent
    assert body["models"]["vision"]["endpoint"] == "/models/gemini-2.5-flash:generateContent"
    # 默认 TTL 24 小时
    assert body["ttl_hours"] == 24
    assert abs(body["expires_at"] - time.time() - 24 * 3600) < 60

    # 审计绝不记录明文 Key：任何日志字段都不含 Key 原文
    logs = client.get("/api/admin/logs?limit=300", headers=h).json()["logs"]
    issued = [l for l in logs if l["action"] == "credential.issue"]
    assert issued, "credential.issue 未写审计"
    assert "gemini-test-key" not in str(logs)
    assert "sk-aaaaaaaaaaaa" not in str(logs)
    assert "ark-test-secret-key" not in str(logs)
    d = issued[0]["detail"]
    assert "device=device-aaaa1111" in d and "ttl=24" in d and "vision" in d


def test_34_credential_rejected_for_disabled_device():
    """停用设备：app_device 依赖直接 403，凭证不下发。"""
    import api_app
    api_app._DEV_REG.clear()  # test_29 把同 IP 注册额度用满了，先清桶再注册新设备
    r = client.post("/api/app/device", json={
        "device_id": "device-cred-3333", "name": "直连测试机"})
    assert r.status_code == 200, r.text
    token = r.json()["token"]
    h = auth(ADMIN)
    devices = client.get("/api/admin/devices", headers=h).json()["devices"]
    did = [d for d in devices if d["device_id"] == "device-cred-3333"][0]["id"]
    client.post(f"/api/admin/devices/{did}/toggle", headers=h)
    denied = client.post("/api/app/credential", headers=auth(token))
    assert denied.status_code == 403 and "停用" in denied.json()["message"]
    client.post(f"/api/admin/devices/{did}/toggle", headers=h)  # 恢复，避免影响后续用例


def test_35_credential_gated_by_direct_switch_and_ttl_validation():
    """direct_ai_enabled 关闭时 403 拒绝下发；credential_ttl_hours 校验 1-168 小时。"""
    h = auth(ADMIN)
    client.put("/api/admin/settings", headers=h, json={
        "key": "direct_ai_enabled", "value": "0"})
    r = client.post("/api/app/credential", headers=auth(DEVICE))
    assert r.status_code == 403 and "直连" in r.json()["message"]
    client.put("/api/admin/settings", headers=h, json={
        "key": "direct_ai_enabled", "value": "1"})
    # 数值范围：1-168 小时
    for bad in ("0", "169", "abc"):
        resp = client.put("/api/admin/settings", headers=h, json={
            "key": "credential_ttl_hours", "value": bad})
        assert resp.status_code == 400, (bad, resp.text)
    ok = client.put("/api/admin/settings", headers=h, json={
        "key": "credential_ttl_hours", "value": "48"})
    assert ok.status_code == 200
    body = client.post("/api/app/credential", headers=auth(DEVICE)).json()
    assert body["ttl_hours"] == 48
    assert abs(body["expires_at"] - time.time() - 48 * 3600) < 60
    client.put("/api/admin/settings", headers=h, json={
        "key": "credential_ttl_hours", "value": "24"})  # 恢复默认


GEMINI_OK = {
    "candidates": [{
        "content": {"role": "model", "parts": [{"text": "一件"}, {"text": "白衬衫"}]},
        "finishReason": "STOP"}],
    "usageMetadata": {"promptTokenCount": 12, "candidatesTokenCount": 7,
                      "totalTokenCount": 19},
}


def test_36_gemini_proxy_converts_request_and_response(monkeypatch):
    """Gemini 原生 generateContent：请求转 contents/parts + inlineData +
    x-goog-api-key 头，响应转回 OpenAI choices 格式（App 端零改动）。"""
    import api_app
    import httpx

    calls = []
    b64 = base64.b64encode(b"\x89PNG\r\n\x1a\nfake-image").decode()

    class FakeClient:
        def __init__(self, *args, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def post(self, url, **kwargs):
            calls.append((url, kwargs))
            return httpx.Response(200, json=GEMINI_OK)

    monkeypatch.setattr(api_app.httpx, "AsyncClient", FakeClient)
    r = client.post("/api/app/ai/v1/chat/completions", headers=auth(DEVICE), json={
        "model": "auto", "temperature": 0.3,
        "messages": [
            {"role": "system", "content": "You are the vision step of a wardrobe app."},
            {"role": "user", "content": [
                {"type": "text", "text": "拆解这套穿搭"},
                {"type": "image_url", "image_url": {
                    "url": "data:image/png;base64," + b64}}]}]})
    assert r.status_code == 200, r.text
    body = r.json()
    # 响应是标准 OpenAI choices 格式
    assert body["choices"][0]["message"]["content"] == "一件白衬衫"
    assert body["choices"][0]["message"]["role"] == "assistant"
    assert body["choices"][0]["finish_reason"] == "stop"
    assert body["usage"]["total_tokens"] == 19
    assert body["model"] == "gemini-2.5-flash"
    # 请求确实转成了 Gemini 原生格式
    assert len(calls) == 1
    url, kwargs = calls[0]
    assert url == ("https://generativelanguage.googleapis.com/v1beta"
                   "/models/gemini-2.5-flash:generateContent")
    headers = kwargs["headers"]
    assert headers.get("x-goog-api-key") == "gemini-test-key"
    assert "Authorization" not in headers
    g = kwargs["json"]
    assert g["systemInstruction"]["parts"][0]["text"].startswith("You are")
    assert g["contents"][0]["role"] == "user"
    parts = g["contents"][0]["parts"]
    assert parts[0] == {"text": "拆解这套穿搭"}
    assert parts[1]["inlineData"]["mimeType"] == "image/png"
    assert parts[1]["inlineData"]["data"] == b64
    assert g["generationConfig"]["temperature"] == 0.3


def test_37_gemini_error_envelope_becomes_chinese(monkeypatch):
    """Gemini 错误信封 {"error":{"message"}} 转统一中文提示（密钥类错误点名 Key）。"""
    import api_app
    import httpx

    class FakeClient:
        def __init__(self, *args, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def post(self, url, **kwargs):
            return httpx.Response(400, json={
                "error": {"code": 400, "status": "INVALID_ARGUMENT",
                          "message": "API key not valid. Please pass a valid API key."}})

    monkeypatch.setattr(api_app.httpx, "AsyncClient", FakeClient)
    b64 = base64.b64encode(b"img").decode()
    r = client.post("/api/app/ai/v1/chat/completions", headers=auth(DEVICE), json={
        "messages": [{"role": "user", "content": [
            {"type": "text", "text": "hi"},
            {"type": "image_url", "image_url": {"url": "data:image/png;base64," + b64}}]}]})
    assert r.status_code == 502
    assert "密钥" in r.json()["message"]
    # 纯函数：finishReason → OpenAI finish_reason 映射
    out = api_app._gemini_to_openai({"candidates": [{
        "content": {"parts": [{"text": "x"}]}, "finishReason": "MAX_TOKENS"}]}, "m")
    assert out["choices"][0]["finish_reason"] == "length"


def test_38_summary_counts_credential_issues_separately():
    """summary 新增 credentials_today：与 ai_calls_today（仅代理流量）分开统计。"""
    h = auth(ADMIN)
    s = client.get("/api/admin/summary", headers=h).json()
    assert "credentials_today" in s and s["credentials_today"] >= 1
    assert "ai_calls_today" in s and s["ai_calls_today"] >= 0
