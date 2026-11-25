"""公开只读接口：仅用于登录页展示「邮箱验证是否开启」等状态。

注意：这里不再下发任何模型地址 / 模型 ID / 密钥信息。
App 需要的服务状态走 /api/app/config（需设备凭据）。
"""
from __future__ import annotations

from fastapi import APIRouter

from core import setting, setting_bool, setting_int

router = APIRouter(prefix="/api/public", tags=["public"])


@router.get("/config")
def public_config():
    return {
        "ok": True,
        "site_name": setting("site_name", "衣橱管家 · 管理后台"),
        "email_verification": setting_bool("email_verification", True),
        "login_code_required": setting_bool("login_code_required", False),
        "code_ttl_seconds": setting_int("code_ttl_seconds", 600),
        "code_resend_seconds": setting_int("code_resend_seconds", 60),
        "ai_service_enabled": setting_bool("ai_service_enabled", True),
        "white_bg_mode": setting("white_bg_mode", "local"),
        "api_version": "1.9.0",
    }
