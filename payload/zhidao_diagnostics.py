"""Safe, allowlisted diagnostics for read-only Zhidao data retrieval.

This module deliberately never serializes raw exceptions, URLs, cookies,
session tokens or HTTP response bodies to the console.
"""
from __future__ import annotations

import socket

class ResponseShapeError(ValueError):
    """An API response changed shape; no raw response or token should reach UI logs."""


def diagnose(exc: BaseException) -> tuple[str, str]:
    """Allowlisted error output, never print exception text or request URL/cookies."""
    status = getattr(getattr(exc, "response", None), "status_code", None)
    if status is None:
        status = getattr(exc, "status_code", None)
    if status in (401, 403):
        return "AUTH", "登录会话可能失效或权限不足；请重新扫码并重试"
    if status in (429, 500, 502, 503, 504):
        return "SERVICE", "服务器限流或暂时不可用；稍后再试"
    if isinstance(exc, (TimeoutError, socket.timeout)) or "timeout" in type(exc).__name__.lower():
        return "TIMEOUT", "请求超时；检查网络连接或稍后重试"
    if isinstance(exc, (ConnectionError, socket.gaierror)) or "connect" in type(exc).__name__.lower():
        return "NETWORK", "无法连接到课程服务；检查网络和代理设置"
    if isinstance(exc, (ResponseShapeError, ValueError, KeyError, TypeError)) or "validationerror" in type(exc).__name__.lower():
        return "API_SHAPE", "返回数据格式与当前适配器不符；需要核对课程接口"
    if status is not None:
        return "HTTP_ERROR", "课程服务返回错误状态；请稍后重试或核对登录"
    return "UNKNOWN", "请求未成功；请重新扫码并检查网络，保留了旧缓存"


def diagnostic(source: str, exc: BaseException) -> dict[str, str]:
    code, advice = diagnose(exc)
    return {"source": source, "code": code, "advice": advice}


def emit_failure(source: str, exc: BaseException) -> dict[str, str]:
    detail = diagnostic(source, exc)
    print(f"{source}读取失败 [{detail['code']}]：{detail['advice']}；仅保留同一登录会话的旧缓存。")
    return detail


