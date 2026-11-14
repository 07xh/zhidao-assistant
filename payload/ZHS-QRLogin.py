"""QR sign-in integration for the installed, unmodified ZHS 0.1.5 APIs.

Preserves the original QR endpoint and poller; adds a fresh-QR lifecycle,
CAS session verification and sanitized local status for the WPF UI.
No raw QR tokens, cookies, URLs, user IDs or exception strings are logged.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys
import tempfile
import time

MONITOR_TOKEN = re.compile(r"^[0-9a-f]{32}$")
STAGES = frozenset({
    "requesting", "ready", "scanned", "confirming",
    "verified", "unavailable", "rejected", "expired", "cancelled", "failed",
    "environment-error",
})


class LoginObservation:
    def __init__(self, token: str, root: Path | None = None):
        if not MONITOR_TOKEN.fullmatch(token):
            raise ValueError("invalid local QR monitor token")
        if root is None:
            local_app_data = os.environ.get("LOCALAPPDATA")
            if not local_app_data:
                raise ValueError("LOCALAPPDATA unavailable")
            root = Path(local_app_data) / "ZHSDesktop"
        self.token = token
        self.root = root
        self.path = root / f"monitor-qr-{token}.json"

    def publish(self, stage: str) -> None:
        if stage not in STAGES:
            raise ValueError("unknown QR login stage")
        self.root.mkdir(parents=True, exist_ok=True)
        payload = {"v": 1, "token": self.token, "stage": stage, "at": int(time.time())}
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", dir=self.root,
                prefix="qr-status-", suffix=".tmp", delete=False
            ) as file:
                temporary = Path(file.name)
                json.dump(payload, file, separators=(",", ":"), ensure_ascii=True)
            os.replace(temporary, self.path)
        finally:
            if temporary is not None:
                try:
                    temporary.unlink(missing_ok=True)
                except OSError:
                    pass

    def record(self, stage: str) -> None:
        try:
            self.publish(stage)
        except OSError:
            # QR authentication must still work when UI status cannot be stored.
            pass


def save_cookies_atomic(destination: Path, cookies) -> None:
    """Atomic write of upstream ZHS cookie-list format; preserve prior on error."""
    from zhs.utils.cookie import cookies_to_list

    rows = cookies_to_list(cookies)
    if not isinstance(rows, list) or not rows:
        raise ValueError("no cookies returned by original QR login")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=destination.parent,
            prefix="zhs-login-", suffix=".tmp", delete=False
        ) as file:
            temporary = Path(file.name)
            json.dump(rows, file, ensure_ascii=False, indent=2)
        os.replace(temporary, destination)
    finally:
        if temporary is not None:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass


def _run_login_with_qr(config, session, observation: LoginObservation, data_dir: Path) -> int:
    """0 verified, 4 verification unavailable, 7 rejected, 5 local/QR failure."""
    from zhs.api.session_auth import SessionStatus, verify_session
    from zhs.login import LoginManager

    qr_path = data_dir / "qrcode.png"
    destination = data_dir / "cookies.json"
    observation.record("requesting")
    # Delete only the previous ephemeral QR *image*, never the login cookies.
    # A click on View QR must not show a code belonging to an older attempt.
    try:
        qr_path.unlink(missing_ok=True)
    except OSError:
        observation.record("failed")
        print("[QR_IMAGE_ERROR] 无法移除旧二维码图片；检查 .zhs 目录访问权限。")
        return 5

    def qr_ready(image: bytes) -> None:
        # The unmodified ZHS LoginManager already writes the PNG to qr_path.
        if not image or not qr_path.is_file():
            observation.record("failed")
            return
        observation.record("ready")
        print("[QR_READY] 本次登录二维码已生成。请在设置页查看，知到 App 扫码并确认。")

    def scanned() -> None:
        observation.record("scanned")
        # The original ZHS poller no longer reads its PNG after scan. Erase
        # the one-use image immediately; a later expiry callback can still
        # publish a fresh PNG. Keep all cookies and server state untouched.
        try:
            qr_path.unlink(missing_ok=True)
        except OSError:
            # The outer finally + GUI also retry removal at task exit.
            print("[QR_CLEANUP_WARNING] 已扫码，但临时图片暂未清理；任务结束后将重试。")
        print("[QR_SCANNED] 已扫码，二维码图片已撤除；请在官方 App 中确认登录。")

    try:
        result = LoginManager(session, config).login_with_qr(
            qr_ready, on_scanned=scanned, image_path=str(qr_path)
        )
        if not result.success or not result.cookies:
            observation.record("rejected")
            print("[QR_REJECTED] 扫码未返回可用登录凭证；旧凭证未覆盖。")
            return 7
    except KeyboardInterrupt:
        observation.record("cancelled")
        print("[QR_CANCELLED] 扫码窗口已取消。")
        return 9
    except Exception as error:
        # Never print raw exception text: upstream exceptions may contain
        # private QR tokens, one-time codes, login URLs or HTTP response bodies.
        description = str(error)
        if "二维码过期" in description:
            observation.record("expired")
            print("[QR_EXPIRED] 二维码多次过期，请重新打开扫码登录。")
            return 7
        if "取消" in description:
            observation.record("cancelled")
            print("[QR_CANCELLED] 手机端取消了本次登录。")
            return 9
        observation.record("failed")
        print("[QR_FAILED] 登录轮询或服务器响应异常，请检查网络/代理及原版 ZHS 兼容性。")
        return 5

    observation.record("confirming")
    print("[QR_CONFIRMED] 手机端已确认，正在建立并核验 CAS 服务器会话。")
    # The original LoginManager returns after QR status==1; this by itself
    # does not guarantee the protected Zhidao APIs accept the cookie.
    status = SessionStatus.UNAVAILABLE
    # Authentication endpoint failures can be transient. Retry only read-only
    # session checks, never the QR confirmation or one-time-password request.
    for attempt in range(3):
        try:
            status = verify_session(session)
        except Exception:
            status = SessionStatus.UNAVAILABLE
        if status != SessionStatus.UNAVAILABLE:
            break
        if attempt < 2:
            time.sleep(1)

    if status == SessionStatus.EXPIRED:
        observation.record("rejected")
        print("[QR_AUTH_REJECTED] 扫码已确认，但 CAS 未建立有效服务器会话。旧凭证未覆盖。")
        return 7

    # If auth checking was unavailable, keep the newly confirmed QR cookies
    # for a later *read-only* connection diagnosis, but do not claim success.
    try:
        save_cookies_atomic(destination, session.cookies)
    except (OSError, ValueError, TypeError):
        observation.record("failed")
        print("[QR_SAVE_ERROR] 登录凭证无法安全写入本机；原文件保持不变。")
        return 5

    if status == SessionStatus.OK:
        observation.record("verified")
        print("[QR_VERIFIED] 官方服务器会话核验通过；本地凭证已保存。")
        return 0
    observation.record("unavailable")
    print("[QR_AUTH_UNAVAILABLE] 扫码已确认、凭证已保存，但服务器认证检查暂不可用。请稍后运行连接诊断。")
    return 4


def login_with_qr(config, session, observation: LoginObservation, data_dir: Path) -> int:
    """Run one QR attempt, then erase the ephemeral QR on EVERY exit path.

    Only qrcode.png is removed. The cookies.json and persistent config remain
    untouched; the final sanitized status stays available for the GUI.
    """
    qr_path = data_dir / "qrcode.png"
    try:
        return _run_login_with_qr(config, session, observation, data_dir)
    finally:
        try:
            # unlink() removes a link itself, never follows it. Do not recurse.
            qr_path.unlink(missing_ok=True)
        except OSError:
            # The GUI also retries removal after the child exits, so a
            # temporary file lock does not silently preserve this QR.
            print("[QR_CLEANUP_WARNING] 二维码临时图片未能删除，主程序将再次清理。")


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1 or not MONITOR_TOKEN.fullmatch(args[0]):
        print("[QR_INVALID_ARGS] 缺少本次登录监控令牌。")
        return 2
    observation = None
    try:
        # Publish a pending state BEFORE importing third-party dependencies.
        # If ZHS, loguru, or the local configuration is broken, WPF must not
        # remain indefinitely at "not started" with no actionable diagnosis.
        observation = LoginObservation(args[0])
        observation.record("requesting")
        from loguru import logger
        from zhs.config import ConfigManager
        from zhs.session import ZhsSession
        from zhs.utils.path import get_data_dir

        data_dir = get_data_dir()
        config = ConfigManager().load()
        config.qr.image_path = str(data_dir / "qrcode.png")
        # Never output an upstream exception that could contain QR tokens,
        # one-time passwords or cookies.
        logger.remove()
        session = ZhsSession(config)
        try:
            return login_with_qr(config, session, observation, data_dir)
        finally:
            session.close()
    except Exception:
        if observation is not None:
            observation.record("environment-error")
        print("[QR_INIT_FAILED] 初始化扫码组件失败；请检查已安装的 ZHS 依赖及本机配置。")
        return 5


if __name__ == "__main__":
    raise SystemExit(main())
