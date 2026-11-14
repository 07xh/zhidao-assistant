# 源码与许可证 | Zhidao Assistant V5.2.9 Beta 2

本项目是非官方知到 App 学习记录查询桌面工具，使用开源 ZHS v0.1.5 Python 软件包。

- 上游源码：https://github.com/pjm314159/zhs
- 上游许可：GNU GPL-3.0-only；随包提供 LICENSE-GPL-3.0.txt
- 上游版本：v0.1.5 (2026-11-04)
- Windows 图形启动器：Zhidao-GUI.ps1、Zhidao-UI.xaml、Consent-UI.xaml
- 知到只读适配器：zhidao_only.py
- 构建源代码：与 exe 一起分发的 zhs527-src.zip（含 Go 启动器和安装器源码）

工具新增可选 ZHS 原版 CLI 调用入口：`zhs play -c courseId:classId --type ai`。不修改 ZHS 0.1.5 源码；该上游功能可能产生模拟观看进度，默认仍使用官方学习页。
本工具未获得知到/智慧树官方认可或授权。使用时请遵守平台与学校规则。

转发包含 GPL 代码的程序时，请随附对应源码与许可证。

注意：ZHS 原版 `play` 除了模拟进度，还包含视频弹窗答题行为。由于要求保留原版，本项目未改变其代码。

V5.2 新增 Official-Player.ps1、Install-WebView2.ps1（源代码完整随包分发），以及 WebView2 SDK 1.0.4191.47 官方 NuGet 下载路径。

V5.2.8 稳定性修复增加 `test_media_controller.cjs`（17 项离线测试）和 `test_stability.py`（同意标记/版本一致性测试）。官方播放器仅控制顶层页面选定的单一主视频，不操作 iframe 视频。

V5.2.8 新增 `test_cache_v527.py` 和 `CHANGELOG-V5.2.8.md`，缓存隔离使用登录文件 HMAC 标记而非稳定账号 ID。此版本未实施 DPAPI，也不是离线安装包。
