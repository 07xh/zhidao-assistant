# 知到学习助手 v5.2.9 Beta 2（Windows x64）

**下载：** [v5.2.9-beta.2 测试版](https://github.com/07xh/zhidao-assistant/releases/tag/v5.2.9-beta.2) · [更新说明](CHANGELOG-V5.2.9-beta.2.md) · [CI 记录](https://github.com/07xh/zhidao-assistant/actions/workflows/ci.yml)

## 登录方式

**首选：直接输入 Cookie。** 打开软件 → 设置与隐私 →「直接输入 Cookie」，在遮蔽输入框粘贴**本人知到站点**的单行 Cookie 字符串（`Cookie: name=value; other=value`）或 ZHS `cookies.json` 的 JSON 数组，点「验证并登录」。软件会把本机输入转换为 ZHS 格式，再运行**服务器只读登录诊断**；未确认登录会尝试恢复原来的 Cookie。

另保留「扫码登录」「导入 Cookie 文件」与官方 WebView2 独立网页登录。不能保证任意浏览器站点的 Cookie 都有效。**请勿将真实 Cookie 贴入聊天、Issues 或日志。**

## 桌面界面（开发分支已整合的视觉升级）

- **课程总览：** 自适应单列/双列课程卡片、课程类型与最近核验状态标签、项目数量比例。历史缓存和没有服务器核验时间的进度不显示成当前完成率。
- **登录交互：** 标题栏快速进入账号设置，设置页显示扫码/输入 Cookie/文件导入的步骤和当前服务端核验状态；明文凭据不会在列表、提示或日志中显示。
- **深色主题：** 设置与隐私 → 外观与显示 → 切换深色/浅色；选择保存在 `%LOCALAPPDATA%\\ZHSDesktop\\appearance-mode.txt`，只记录 light/dark，不包含账户数据。
- **高缩放/小窗口：** 基于 WPF 设备无关像素（DIP）和布局取整，窄窗口折叠侧边栏，课程详情的课程选择区移至上方，降低最小窗口尺寸。
- **技术边界：** 继续使用原生 WPF + PowerShell/Python 核心；参考 LightC 的视觉层次但不复制其受 Source Available 许可限制的组件源码或专有资源。

新增 UI 验收在 Windows CI 中使用虚构课程和本机假数据执行；**不能代替 125%/150%/200% 缩放的真机视觉确认**，也不代表真实知到课程或登录已完成端到端验收。

## 当前约束

- 非官方 Windows 10/11 x64 预发布测试版，GPL-3.0-only。
- ZHS 0.1.5 仍会在 `%USERPROFILE%\.zhs\cookies.json` 本地明文保存 Cookie，未实现 DPAPI 加密。
- 只读服务器核验、原始 ZHS 任务退出回查与跨账号进度隔离保留；不更改原版心跳生成/发送机制。
- CI 包含 Windows PowerShell 5.1 源码与 Cookie 假数据回归、Python/JavaScript 离线回归和 Windows x64 交叉构建；真实账号与课程进度需要本人在 Windows 真机验收。

开发者本地构建：`python build.py` → `ZhidaoAssistant-Setup-v5.2.9-beta.2.exe`。

[上一版 v5.2.9-beta.1（仅支持 Cookie 文件导入）](https://github.com/07xh/zhidao-assistant/releases/tag/v5.2.9-beta.1)。
