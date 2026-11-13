# V5.2.8 Hotfix 1 — 修复 Windows 安装器脚本编码

- 原版 `payload/AppLifecycle.ps1` 是 **无 BOM 的 UTF-8**，包含中文错误消息。
- Windows PowerShell 5.1 对无 BOM 脚本通常使用系统 ANSI 代码页，从而误解析引号和中文内容，在 dot-source 阶段抛出 ParserError；截图中 `AppLifecycle.ps1:118`、`:120` 即该问题。
- 为 `AppLifecycle.ps1` 增加 UTF-8 BOM；不更改业务逻辑、进程终止范围、登录态或安装位置。
- 增加 `test_ps1_encoding.py`，防止以后的无 BOM 中文 PowerShell 文件重新进入安装包。
- 打包文件命名为 `v5.2.8-hotfix1`，应用内版本仍为 5.2.8。

在 Windows 上再次运行 **修复版安装器**，无需运行原版卸载器、手动删除 `.zhs` 或 `.venv`。失败时请提供新的安装器截图。此环境不能运行 Windows PowerShell 5.1 真机集成测试。
