# V5.2.8 Hotfix 2 · 启动器日志显示修复

## 已修复

`Zhidao-Task.cmd` 之前含 UTF-8 BOM。Windows CMD 会把首行 `@echo off` 前的 BOM 当作非预期字符，从而导致批处理命令被逐行回显。新版仅移除此 CMD 文件的 BOM，不更改 ZHS 0.1.5 业务行为。

`AppLifecycle.ps1` 及其他包含中文的 PowerShell 脚本继续保留 UTF-8 BOM，以兼容 Windows PowerShell 5.1。

## 截图中登录会话过期

`登录状态已过期，请重新运行 zhs login 登录` 属于 ZHS 登录会话失效，不是批处理编码错误；本补丁不伪造、不自动续期登录。请在软件中选择「扫码登录」，完成官方扫码后重新同步课程。官网 WebView2 登录和 ZHS 登录属于独立会话。

## 安装与验证

- 直接运行 hotfix2 安装器覆盖，保留 `%USERPROFILE%\.zhs` 下的登录及课程缓存。
- 编码回归：`python test_cmd_encoding.py` 和 `python test_ps1_encoding.py`。
- 本环境进行了编译与静态检查，未实际在 Windows 真机复现登录和安装步骤。
