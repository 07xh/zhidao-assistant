# 代码架构与重复项审查（2026-11-13）

范围：`main` 分支的 Windows 启动器、安装与更新、WPF GUI、只读课程/进度、ZHS 0.1.5 源码修复包装器、自动化测试。**未进行 Windows 真机安装/真实账号验收。**

## 一、已落地的去重与安全整改

| 优先级 | 文件 | 原问题 | 本轮改动 |
| --- | --- | --- | --- |
| P0 | `build.py`, `payload/install-files.json`, `payload/Install.ps1` | 构建“打包全部普通文件”，安装器另维护 22 项手写清单，容易额外打包文件或漏装依赖 | **共享唯一 JSON 白名单**，两端校验路径与重复项；额外文件直接拒绝构建 |
| P0 | `build.py` | Go 编译阶段把 `payload/ZhidaoAssistant.exe`、`src/payload.zip` 等中间文件写回源码树，可能污染下次构建 | 在隔离临时目录构建、ZIP 排序和固定时间戳；失败不改变源码树 |
| P1 | `build.py`, `.github/workflows/ci.yml` | 未发布的代码仍以 **Hotfix10** 作为文件名，容易误认为与现有 Release 二进制相同 | 改成独立的 `v5.2.8-dev` 名称，SHA-256 校验后只上传 Actions 构建产物 |
| P1 | `.github/workflows/ci.yml` | `unittest discover` 已导入静态契约文件，额外显式调用 4 次重复运行 | 精简重复步骤；保留独立研究模块、JS 控制器和 Windows PowerShell 5.1 语法测试 |
| P1 | `payload/Verify-Environment.py` | 用 `assert version('zhs') == '0.1.5'` 检查版本，优化运行时断言会消失 | 改为始终执行的显式条件判断，补缺失/错误版本离线测试 |
| P2 | `payload/Windows-Preflight.ps1` | 诊断输出仍为 5.2.7，文件名仍为 v526 | 更新为 5.2.8-dev；不上传本地 Cookie、课程标识 |
| P2 | `.github/workflows/publish-hotfix10.yml` | 已发布 Hotfix10 的一次性工作流与现行 dev 输出不兼容 | 移除过时工作流；**GitHub Release v5.2.8-hotfix10 保持原样** |

新增 `test_packaging.py` 校验：白名单完整、路径非法/大小写重复拒绝、多余文件拒绝、ZIP 内容精确匹配、ZIP 按字节可重复。新增 `test_environment.py` 证明依赖版本检测不依赖 Python 断言。

**同步可靠性追加修复：** `zhidao_only.py` 的失败课程记录不再只依赖课程名称，改用不暴露原始课程路由的 SHA-256 身份摘要 `failedCourseKeys` 对齐失败原因；同名课程可独立恢复。老缓存缺少身份摘要且名称重复时保持未确认，不会误删错误。`test_sync_integrity.py` 新增同名课程与旧缓存回归用例。该字段对原缓存结构为向后兼容的可选字段。

## 第二阶段：渐进式模块拆分（已完成代码与离线测试）

- **登录状态模块：** 新增 `payload/SessionState.ps1`，从 WPF 主入口抽离 Cookie 摘要与登录提示状态机，仍保持原来的 `Get-CookieDigest`、`Update-LoginState` 调用接口。GUI 使用 dot-source 加载；`test_session_state.ps1` 在 Windows PowerShell 5.1 下用临时假 Cookie 实际检查：未登录、仅有凭证、已核验、账号更换、退出登录。
- **诊断模块：** 新增 `payload/zhidao_diagnostics.py`，将 `ResponseShapeError`、`diagnose`、`diagnostic`、`emit_failure` 独立出来并由旧适配器重新导出。诊断仅打印允许的错误类别与固定建议，不打印异常原文；`test_diagnostics.py` 校验分类与脱敏。
- **课程模型模块：** 新增 `payload/zhidao_courses.py`，抽离课程身份、身份摘要、固定官方域名链接及“空响应保留历史待确认”合并策略。原 `zhidao_only.py` 继续重新导出原接口；`test_course_model.py` 对比调用兼容性、同名课程不同身份、外部 URL 注入防护和缓存合并结果。
- **安装一致性：** 三个模块全部进入唯一白名单 `install-files.json`，依赖随开发版 Windows 安装器一同打包；单独脚本测试与完整回归均由 GitHub Actions 执行。

**边界：** 上述是离线重构与可用性改进，尚未证明真实 Windows 登录、浏览器播放、知到后台进度的端到端行为。不会将构建成功等同于平台学习完成。

## 二、暂不能直接删除的旧文件

| 文件或目录 | 判定 | 理由 |
| --- | --- | --- |
| `payload/apply_safe_fixes_v2.py` | **保留：运行时依赖** | 被 `verify_and_integrate_v4.py` 导入，用于精确验证与保守错误处理补丁 |
| `payload/apply_http_safety_v3.py` | **保留：运行时依赖** | 同上，处理固定版本 HTTP 客户端的受审查差异 |
| `payload/verify_and_integrate_v4.py` | **保留：运行时依赖** | 被 `Patch-ZHS-0.1.5.py` 调用，承担源代码指纹验证 |
| `payload/Patch-ZHS-0.1.5.py` | **保留：安装路径必需** | 安装器 `--apply`/`--check` 调用，提供备份与回滚 |
| `LICENSE` 与 `payload/LICENSE-GPL-3.0.txt` | **有意重复** | 仓库许可证与独立安装包分发许可证承担不同用途 |
| `CHANGELOG-*.md`, `HOTFIX*-README.md`, `TEST-REPORT-*.md` | **历史档案** | 不参与打包；可集中到 docs/archive 但应保留历史验收记录，不应伪造重新测试 |
| `research/heartbeat_lab.py` | **保留但保持隔离** | 离线状态机研究；不连接真实知到服务器，不证明线上进度 |

## 三、进一步架构重构（尚未完成）

1. **P1｜GUI 继续拆分**：`SessionState.ps1` 已抽离并有 Windows 状态测试；余下 WPF 主入口仍约 880 行。下一步按 `TaskRunner` / `CourseViews` 拆分，先补运行时事件处理器与真实窗口测试，再分段迁移。
2. **P1｜只读适配器继续拆分**：诊断与课程模型已抽离，`payload/zhidao_only.py` 仍约 640 行。下一步独立 `auth_state`、`cache_store`、`api_readers`、`sync_service`，保持对外 CLI `doctor-server/courses/progress/verify-one` 契约和缓存 schema，避免账号缓存交叉污染。
3. **P1｜依赖锁定**：已固定 ZHS 0.1.5 / uv 版本，但尚未提供所有 Python 依赖的完整 hash lock；安装器首次联网安装依赖，仍有网络和供应链可重复性缺口。
4. **P1｜Windows E2E 门禁**：目前 CI 增加了 Windows PowerShell 5.1 下的登录状态模块离线执行，但完整 Windows 安装/升级/卸载和真实服务器集成仍未验收。没有真实安装/升级/卸载、WebView2、扫码和 CAS 会话的真机验收。正式 Release 之前必须补齐。
5. **P2｜GUI 提示一致性**：服务器只读记录、历史缓存和本地任务执行结果应始终分开展示；不可根据进程退出码推断课程完成。
6. **P2｜测试整理**：早期 `test_hotfix3.py` / `test_hotfix4.py` / `test_stability.py` 有少量静态断言与运行时集成测试重叠；迁移为聚焦的单元测试后才能删旧用例。
7. **P2｜版本单一来源**：`Install.ps1`, WPF 页面, Go 提示和预检仍存在 5.2.8 的重复文字；以后通过一次生成的构建元数据统一版本展示。
8. **P2｜发布工件与源码关联**：在下个正式版本上提供 tag/SHA、校验文件和 Windows 真机验收证明，不能把当前 dev 工件覆盖为原 Hotfix10。

## 四、开发纪律

- **不破坏现有数据**：`%USERPROFILE%\\.zhs` 以及 `%LOCALAPPDATA%\\ZHSDesktop` 的个人数据不因代码清理自动删除；安装失败保持已有备份/回滚机制。
- **不改模拟心跳**：本轮没有修改 ZHS 模拟播放请求、时长、调度或发送逻辑；不会以本地/离线测试宣称服务器课程完成。
- **旧版可追溯**：已发布的 `v5.2.8-hotfix10` Release 与对应 tag 不变；新代码仅在 `main`，通过 CI 提供独立开发构建。
