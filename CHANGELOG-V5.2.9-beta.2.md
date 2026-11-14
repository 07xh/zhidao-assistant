# 知到学习助手 v5.2.9-beta.2（Windows x64 测试版）

## 登录体验修复

- 设置页首选按钮改为 **直接输入 Cookie**：在程序内的遮蔽输入框中粘贴本人知到账号的 Cookie 字符串，不再要求准备 JSON 文件。
- 支持两种输入形式：单行 Cookie 请求头值（可带 `Cookie:` 前缀，例如 `a=example; b=example`，仅为虚构示例）和 ZHS 0.1.5 的 JSON Cookie 数组。
- 在本机校验字段、长度、重复 Cookie 等并统一转换为 ZHS 所需的 `cookies.json` 格式。普通 Cookie 请求头不包含域名/路径信息，因此统一限定到 `.zhihuishu.com` 和 `/`，无法保证所有浏览器 Cookie 都适用。
- 输入后自动进行只读服务端登录诊断；若不能确认登录，则尝试恢复原 Cookie。仅服务器认证通过才提示已验证登录。不会在日志或弹窗中显示 Cookie 明文。
- **扫码登录**、**从本机导入 ZHS Cookie 文件**继续保留。
- 已纳入离线回归测试：直接输入、格式错误、重复字段、换行注入、服务器拒绝登录回滚。PowerShell 5.1 Windows 检查和 Windows x64 安装包构建作为发布门禁。

## 安全和兼容性

- Cookie 与密码同等级敏感，**请不要发给 AI 聊天、GitHub、他人或截图分享**。只在自己可信的 Windows 电脑客户端输入。
- 用户手动输入的 Cookie 不会上传到开发者服务；软件调用现有 ZHS 依赖的服务器登录检查。
- 注意：ZHS 0.1.5 仍将 Cookie 明文存储在本地 `%USERPROFILE%\\.zhs\\cookies.json`，不支持 DPAPI 加密。
- 本次不更改 ZHS 心跳发送算法、课程进度提交参数或学习时长计算。
- Windows 10/11、真实账号的 Cookie 有效性、平台是否计入课程进度仍需本人真机验收。此版为**预发布测试版**，不承诺已验证所有知到登录场景。

## 安装

下载 `ZhidaoAssistant-Setup-v5.2.9-beta.2.exe` 和 `SHA256SUMS.txt`，校验文件完整性后在 Windows x64 上运行。保留原来的二维码登录方式；升级默认不清空已有 `.zhs` 登录数据。
