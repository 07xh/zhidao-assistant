# 知到学习助手 V5.2.8 · 只读会话与进度可靠性修复

基线：Hotfix5 研究版 / 随后 Hotfix6 未完成的工作树。此次更改不包含知到平台心跳伪造或进度写入功能。

## 本轮代码改动

1. `zhidao_only.py` 增加 `doctor-server`：调用 ZHS SDK 的共享课列表与现有 AI 课程只读接口，分别检测服务器返回是否有效。一个来源失败时报告部分成功，不把本地 SDK 会话初始化当成服务器登录成功。
2. `Zhidao-Task.cmd` 原「连接诊断」入口改为调用 `doctor-server`。
3. GUI 根据完全成功/部分成功/全部失败显示不同消息（exit code 0/7/6）。
4. 给明确的只读操作增加一次**有限重试**：仅在连接超时、断网连接错误或 HTTP 502/503/504 时重试一次；401/403、429、接口数据变化和未知错误不重试。避免重复向服务器提交学习记录。
5. 释放会话时容错，防止关闭异常遮蔽已获得的有效结果。
6. 新增 9 项专项回归测试，覆盖断网、服务错误、权限失败、限流、单来源失败、双来源成功、Cookie 脱敏和 GUI 集成。

## 安全与边界

- 真实服务器调用仅限课程和学习进度读取；不会发送人工构造的观看时长、虚构视频心跳、课后题或考试提交数据。
- 旧的上游 ZHS `play` 入口未被增强或调用，原始用户数据不会被安装前清理。
- 程序只输出安全错误码、来源名称及数量，不打印 Cookie、服务器原始响应或敏感 URL。
- 当前结果是源码测试、Windows 交叉编译、静态包校验，**不代表 Windows 真机、平台服务器与具体课程已验收**。

## Windows 验收

1. **先备份** `%USERPROFILE%\.zhs`，保留原来的 Hotfix5 安装器。使用这份测试版覆盖安装，不要删除原账户数据。
2. 设置 → 连接诊断。返回 `SERVER_OK` 为两个只读课程接口返回有效数据；`SERVER_PARTIAL` 为至少一个成功；`SERVER_UNCONFIRMED` 为两个都失败。
3. 使用 GUI「同步课程」及「同步进度」，核对知到官方 App 里能看到的本人课程；记录错误码，不分享 Cookie、二维码或原始抓包。
4. 官方正常观看后核对进度，并确认错误网络状态不会把旧缓存显示为新数据。

## 本地构建与测试

```bash
PYTHONPATH=research:. python -m unittest -v test_cache_v527 test_hotfix3 test_hotfix4 test_hotfix5_research test_readonly_reliability research.test_heartbeat_lab
node test_media_controller.cjs
python test_stability.py
python build.py
```
