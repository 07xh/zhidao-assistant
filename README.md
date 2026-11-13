# 知到学习助手 V5.2.8 Hotfix10（Windows x64 测试版）

**开发分支最新修复（尚未进入 Hotfix10 Release）：** 单课只读核验成功后，准确更新对应的失败标记；其他失败来源继续保留；首页在同步不完整或存在历史记录时隐藏总进度统计；历史完成状态显示为待核验。增加了异常脱敏和针对性离线测试。这些修改不涉及 ZHS 心跳生成/发送算法。可在 [GitHub Actions](https://github.com/07xh/zhidao-assistant/actions/workflows/ci.yml) 核对最新源码构建情况。最新可直接下载的 Release 仍为 Hotfix10，**并未包含这批开发分支修复**。

**最新登录检测修复：** 扫码后自动进行只读服务端诊断；明确区分本地 Cookie 缺失/损坏、会话未确认与课程接口失败；最近一次登录验证状态随 Cookie 更换立即失效。详见 [Hotfix10 更新说明](CHANGELOG-HOTFIX10.md)。



本版为 V5.2.7 的升级维护：再次运行安装器会自动结束属于当前用户同一个安装目录的旧版程序和播放器，然后就地替换程序文件、移除已知旧版启动脚本和更新卸载项。不会执行旧版本自带的卸载器，也不会删除 `.zhs` 登录数据或重建已有效的 Python/ZHS 虚拟环境。

只处理 `%LOCALAPPDATA%\ZHSDesktop`：其他文件夹中的便携副本不会自动卸载。若无法可靠识别相关进程或程序文件仍被占用，会保留已有安装并显示错误，而不是结束无关进程。

原有 V5.2.7 官方播放器、只读课程核验和 ZHS 0.1.5 依赖保持原样。本版仍未进行 Windows 真机升级/安装/卸载验收，不代表真实课程可用性已验证；首次安装可能需要联网下载依赖。

构建：`python build.py`。测试：`python test_cache_v527.py`、`python test_stability.py`、`python test_lifecycle_v528.py`、`node test_media_controller.cjs`。

本项目为非官方工具，GPL-3.0-only。
