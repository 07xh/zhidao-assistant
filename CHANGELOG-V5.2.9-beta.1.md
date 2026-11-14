# 知到学习助手 v5.2.9-beta.1（Windows x64 测试版）

## 主要更新
- 设置页新增「导入 ZHS Cookie 文件」入口。仅接受本人已有的 ZHS 0.1.5 `cookies.json` 列表格式（`name/value/domain/path`）；**不是**直接粘贴浏览器 Cookie 的登录方式。
- 导入前检查文件大小、JSON 结构、重复项与知到域名；导入后自动运行 **只读** 服务端登录检测。检测未确认登录时尝试原地回滚先前的本地凭证。
- 旧的知到 App 扫码登录继续保留；官方 WebView2 网页登录仍单独使用浏览器配置文件，不与 ZHS Cookie 自动互通。
- 包含上一轮已合并的 ZHS 原版任务退出后的课程进度只读核验、同一会话绑定的待核验队列与跨账号隔离。
- 新增 Windows PowerShell 5.1 离线回归测试，涵盖合法导入、非法域名、无效 JSON、旧凭证回滚和部分课程接口故障。
- 安装器升级原地覆盖应用文件，继续保留既有 `%USERPROFILE%\.zhs` Cookie 与课程数据。

## 登录注意事项
- Cookie 是**敏感登录凭证**，请勿发送给任何人，也不要上传至 GitHub、论坛或聊天。
- 导入只验证给定文件格式是否与 ZHS 0.1.5 兼容；是否真正登录成功由随后只读服务器接口确认。
- 选取来自您本人其他 ZHS 安装的 `cookies.json`，而不是浏览器 HTTP Cookie 请求头，也不提供自动提取浏览器 Cookie 的功能。
- ZHS 上游仍以明文 JSON 保存 Cookie（未实施 DPAPI 加密）。建议仅在可信的私人 Windows 用户账号中使用。

## 限制与验收状态
- 这是 **预发布测试版**，不是经真实账号验收的稳定版本。
- GitHub Actions 仅负责静态语法、离线模拟回归与 Windows x64 安装器交叉编译；真实 Windows 10/11 升级、扫码 / Cookie 导入及服务端学习进度仍需在本人设备与账号上验证。
- 不保证平台学习进度或心跳被接受。原版 ZHS 0.1.5 的心跳生成、频率和提交算法**没有**因本版新增登录方式而改变。
- 安装包未数字签名。发布页面的 `SHA256SUMS.txt` 可用于校验安装器完整性。

## 安装
下载 GitHub Release 中的 `ZhidaoAssistant-Setup-v5.2.9-beta.1.exe`，在 Windows 10/11 x64 上运行。升级前请自行备份 `%USERPROFILE%\.zhs`。联网安装仍可能下载固定版本的 Python、ZHS 与 WebView2 依赖。
