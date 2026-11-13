# 知到学习助手 V5.2.8（Windows x64）

本版为 V5.2.7 的升级维护：再次运行安装器会自动结束属于当前用户同一个安装目录的旧版程序和播放器，然后就地替换程序文件、移除已知旧版启动脚本和更新卸载项。不会执行旧版本自带的卸载器，也不会删除 `.zhs` 登录数据或重建已有效的 Python/ZHS 虚拟环境。

只处理 `%LOCALAPPDATA%\ZHSDesktop`：其他文件夹中的便携副本不会自动卸载。若无法可靠识别相关进程或程序文件仍被占用，会保留已有安装并显示错误，而不是结束无关进程。

原有 V5.2.7 官方播放器、只读课程核验和 ZHS 0.1.5 依赖保持原样。本版尚未进行 Windows 真机升级/安装/卸载验收，不代表真实课程可用性已验证；首次安装可能需要联网下载依赖。

构建：`python build.py`。测试：`python test_cache_v527.py`、`python test_stability.py`、`python test_lifecycle_v528.py`、`node test_media_controller.cjs`。

本项目为非官方工具，GPL-3.0-only。
