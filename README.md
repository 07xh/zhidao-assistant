# 知到学习助手 v5.2.9 Beta 1（Windows x64）

**下载：** [v5.2.9-beta.1 测试版](https://github.com/07xh/zhidao-assistant/releases/tag/v5.2.9-beta.1) · [发布说明](CHANGELOG-V5.2.9-beta.1.md) · [GitHub Actions](https://github.com/07xh/zhidao-assistant/actions/workflows/ci.yml)

本项目是非官方、面向个人学习的 Windows 工具（GPL-3.0-only）。软件保留 ZHS 0.1.5 的课程读取、进度查询与原版功能，并提供独立的官方 WebView2 视频窗口和服务器只读核验；**离线测试和安装包构建通过不等于真实知到账号/课程已验收**。

## 登录方式

1. **官方知到 App 扫码（推荐）：** 设置与隐私 → 扫码登录，随后自动执行只读服务器诊断。
2. **导入已有 ZHS Cookie：** 设置与隐私 → 导入 ZHS Cookie 文件，选择本人已有 ZHS 0.1.5 的 `cookies.json`（JSON 列表）。严格验证结构和知到域名后临时替换本地凭证，并自动检测服务器登录；登录未确认时尝试恢复旧凭证。不能直接粘贴浏览器 HTTP Cookie 字符串。
3. **官方网页独立登录：** WebView2 内的官网 Cookie 保存在独立浏览器配置目录，与 ZHS 会话不共用。

Cookie 文件属于敏感登录凭证，**请不要上传、发送或贴到 Issues**。ZHS 上游仍以明文 JSON 保存在 `%USERPROFILE%\.zhs\cookies.json`，请妥善保护本机账户。

## 本次修复

- 将 ZHS 原版任务退出与课程服务器只读核验衔接；显示本地退出码但不把它误当作服务器进度成功。
- 待核验课程绑定启动时的 ZHS 会话；旧格式、跨账号任务不再被当作当前账号数据。
- 新增 Cookie 导入校验、原凭证回滚与 Windows PowerShell 回归测试。
- 安装器原地升级且默认保留 `.zhs`、已存在的 Python/ZHS 运行环境；不另写模拟心跳执行器。

## 构建与验收

本项目以 CI 为构建来源，`python build.py` 生成 `ZhidaoAssistant-Setup-v5.2.9-beta.1.exe`；测试包括 Python、JavaScript、Windows PowerShell 5.1 源码解析、模拟 Cookie 登录以及 Windows x64 安装器交叉编译。发布包不含代码签名，需参照 SHA-256 校验。

**尚待本人 Windows 真机验收：** 安装/升级与登录、官方播放，以及平台真实记录的服务器端学习进度。保留 [上一测试版 v5.2.8-hotfix10](https://github.com/07xh/zhidao-assistant/releases/tag/v5.2.8-hotfix10) 供比较。
