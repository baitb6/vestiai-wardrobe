"""wardrobe-manager 管理后台入口。

    python3 server.py                                  # 本地开发
    uvicorn server:app --host 0.0.0.0 --port 8787     # 生产（见 deploy/）
"""
from __future__ import annotations

import logging
import os
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

import api_admin
import api_app
import api_auth
import api_public
from core import init_db

ROOT = Path(__file__).resolve().parent
ORIGINS = [s.strip() for s in os.getenv("WM_ALLOW_ORIGINS", "*").split(",") if s.strip()]
logger = logging.getLogger("wardrobe-admin")

init_db()

app = FastAPI(title="wardrobe-manager admin", version="1.9.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ORIGINS or ["*"],
    # Flutter Web 的 XHR 在部分版本会带 withCredentials，
    # 这里必须允许凭据（Starlette 会自动回显具体 Origin），否则整站跨域失败。
    # 接口鉴权用的是 Bearer 设备凭据而不是 Cookie，不存在 CSRF 风险。
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["X-Model-Name"],
)
app.include_router(api_auth.router)
app.include_router(api_admin.router)
app.include_router(api_app.router)
app.include_router(api_public.router)


@app.exception_handler(HTTPException)
async def http_error(request: Request, exc: HTTPException):
    return JSONResponse(status_code=exc.status_code,
                        content={"ok": False, "message": exc.detail})


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError):
    # 参数校验失败也统一成 {ok, message} 信封，返回 422（前端能读到中文提示），
    # 而不是 FastAPI 默认的英文 detail 数组
    first = exc.errors()[0] if exc.errors() else {}
    loc = ".".join(str(p) for p in first.get("loc", []) if p != "body")
    return JSONResponse(status_code=422, content={
        "ok": False,
        "message": f"请求参数不合法（{loc or 'body'}：{first.get('msg', '格式错误')}）"})


@app.exception_handler(Exception)
async def unhandled(request: Request, exc: Exception):
    # 永远给前端一句人话，不要把 Python 堆栈甩到页面上；真实堆栈写日志，便于 journalctl 排查
    logger.exception("未处理异常 %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500,
                        content={"ok": False, "message": f"服务器处理失败：{exc.__class__.__name__}"})


@app.get("/healthz")
def healthz():
    return {"ok": True, "service": "wardrobe-admin", "version": "1.9.0"}


# 静态管理后台必须放在最后，避免吞掉 /api 路由
app.mount("/", StaticFiles(directory=str(ROOT / "static"), html=True), name="static")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("server:app", host="0.0.0.0",
                port=int(os.getenv("WM_PORT", "8787")), reload=False)
