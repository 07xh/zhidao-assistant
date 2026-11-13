# 本地心跳状态实验室（不连接知到平台）

本实验只复用**通用系统工程思想**：单调时间、采样间隔、状态机、事件序号、去重、有限重试、背压与最终结果校验。
不包含知到/雨课堂真实接口、身份信息、平台心跳载荷、模拟观看时长或完成状态修改。

## 运行

Windows PowerShell（已有 Python 3.10+）：

```powershell
python research/heartbeat_lab.py --scenario normal
python research/heartbeat_lab.py --scenario background-gap --demo-retry
python research/heartbeat_lab.py --scenario unmarked-jump
python -m unittest discover -s research -p 'test_*.py' -v
```

仅内存中的 `MemoryLabReceiver` 会给出 `accepted` 等 **实验回执**，它**不是**知到服务器确认，更不是学习完成证明。

## 观察项

- `clock_s` 单调时间（模拟值），`media_s` HTML5 播放器真实/模拟时间
- `baseline`/`advancing`/`paused`/`buffering`/`stalled`
- `seeking`/`position-jump`/`sampling-gap`/`clock-regression`
- `source-changed` 与 `visibility-changed`
- 有界队列、事件编号、重复去重与失败后的有限重试

**平台接入边界：** Hotfix5 主程序的 `Official-MediaController.js` 仍只读浏览器播放状态，页面无授权完成行为不会被转成平台心跳请求。服务器进度只通过既有 ZHS 只读查询确认。
