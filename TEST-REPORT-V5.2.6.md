# V5.2.6 构建与测试报告

## 已完成

- Windows x64 安装器交叉编译成功：`ZhidaoAssistant-Setup-v5.2.6.exe`。
- Windows GUI 启动器已编译并内嵌至安装资源。
- `node --check payload/Official-MediaController.js` 通过。
- `node test_media_controller.cjs`：17 项通过。
- `python test_stability.py`：6 组静态一致性检查通过。
- `python -m py_compile payload/zhidao_only.py payload/Verify-Environment.py` 通过。
- `Zhidao-UI.xaml` 与 `Consent-UI.xaml` XML 解析通过。
- Go installer/launcher 文件级 `go vet` 通过。
- GUI、Task CMD 与隐私说明中的同意标记统一为 `privacy-accepted-v5.2.6.flag`。
- 安装包内嵌资源已重新生成。

## 17 项媒体控制器测试覆盖

1. 门户页不自动播放。
2. 官方课程页单视频自动播放与倍速设置。
3. 自动播放关闭时不调用 play。
4. 多视频场景只控制面积最大的主视频。
5. iframe 文档不自动控制。
6. 瞬时 AbortError 最多有限重试。
7. NotAllowedError 不循环重试，手动恢复入口可调用。
8. 应用倍速只作用于主视频。
9. 只在语义主内容容器内尝试下一节。
10. 缺少语义主容器时失败关闭。
11. 导航区域的下一节按钮被排除。
12. 下一题按钮被排除。
13. 页面路由已变化时不重复跳转。
14. SPA 复用视频元素并切换源后重置状态。
15. 重复 canplay 不会并行发起多个 play 请求。
16. 非主视频播放只报告，不由控制器启动或控制。
17. 后续动态加入的第二视频会被检测，但不会由控制器启动。

## 未完成、不得宣称通过

- 没有在 Windows 10/11 真机上运行 PowerShell/WPF 安装与升级流程。
- 没有使用真实知到账号验证登录、课程页面路由和实际 HTML5 播放器结构。
- 没有验证 1.5× 在真实课程播放器中一定生效。
- 没有验证最小化后后台播放行为。
- 没有验证自动下一节在真实课程 DOM 上的可用性；本版在无法安全定位时会停止并提示手动切换。
- 没有验证官方服务器进度是否在真实课程中更新。
- PowerShell 脚本未在 Windows PowerShell 5.1 真机执行解析/集成测试；当前环境没有 PowerShell 运行时。

## 重要限制

为防止多视频/多 iframe 同时触发播放，本版只控制顶层官方页面中选出的一个可见主视频，不自动控制 iframe 内媒体。某些课程若播放器仅存在于 iframe，需使用官方网页自身控件。控制器不会主动暂停网页自行启动的次要媒体，只保证本控制器不启动它们。
