# 知到学习助手 V5.2.8 Hotfix7 · 同步真实性与缓存一致性优化

## 本轮修复

- 当共享课/智慧课程接口本次返回 **有效空列表**、但同一登录会话的旧缓存中仍然存在该来源的课程时，保存旧数据并设 `stale: true`，新增 `unconfirmedEmptySources` 标记，并返回不完整同步的退出码 `1`，**不再提示“同步完全成功”**。两类来源首次确实为空（没有该来源旧课程）仍视为正常成功。
- 全量进度同步沿用该标记：`incomplete` 为真时，明确告知不是全部新验证的记录。
- 前端增加“历史缓存待确认”标记；首页的已完成数和未完成数仅聚合 **非 stale 的进度行**。全部进度均是旧缓存时展示“—”，避免误称有最新的服务器数据；旧缓存仍可单独在详情查看。
- `ai_course_list` / `shared_course_list` 对非法响应外壳失败关闭，不用格式异常的结果覆盖有效本机缓存。
- 保留已经实现的个人账号隔离、加锁原子写、只读网络重试、官方播放器和实验室研究工具。

## 兼容性与安全

- 不清理 `%USERPROFILE%\.zhs`，仍以登录会话指纹隔离缓存；原有 JSON 字段仍可读取。新增字段是向后兼容的。
- 不改动 `zhs 0.1.5` 上游心跳发送，不增加模拟观看记录或课程进度写入；读取进度仅来自知到真实课程接口。
- 账号 Cookie、访问令牌、原始 HTTP 内容不会加入调试报告。
- Hotfix7 是本地源码测试 + Windows x64 交叉编译版本，**没有在真实 Windows 电脑/真实知到账号上完成端到端验收**。

## 建议实际验收

1. 备份 `%USERPROFILE%\.zhs`，再执行 `ZhidaoAssistant-Setup-v5.2.8-hotfix7-integrity.exe` 覆盖安装。
2. 设置 → 连接诊断，确认共享课与智慧课程接口各自的结果。
3. 同步课程/进度，与官方 App 的课程列表和进度对照；当接口返回空而旧课程仍存在时，窗口应提示 `[EMPTY_UNCONFIRMED]`，界面标识“历史缓存待确认”。
4. 在设置中核验单课进度。遇到异常仅提供安全错误码与文字截图，不外传 Cookie/二维码/完整原始请求。

## 测试

```
PYTHONPATH=research:. python -m unittest -v test_sync_integrity test_readonly_reliability test_cache_v527 test_hotfix3 test_hotfix4 test_hotfix5_research research.test_heartbeat_lab
node test_media_controller.cjs
python test_stability.py
python test_cmd_encoding.py
python test_ps1_encoding.py
python test_lifecycle_v528.py
python build.py
```
