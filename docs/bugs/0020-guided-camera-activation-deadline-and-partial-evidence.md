# BUG 0020：带练相机完整 activation 无截止且极短录像误报成功

- 状态：修复中并部分修订（见 BUG 0025）；自动化与维护者真机验收尚未完成
- 发现日期：2026-08-16
- 影响范围：带练自动/手动录像、相机唤醒、失败可见性、系统中断与视频证据真值
- 修订自：
  - [BUG 0013](0013-guided-recording-startup-silent-stall.md) 的启动截止与失败事件修复
  - [BUG 0019](0019-guided-recording-attempt-terminal-and-duplicate-alerts.md) 的 attempt 单终态与成功文件保留修复
- 后续修订：
  - [BUG 0025](0025-guided-recording-terminated-by-connection-reconfiguration.md) 定位到录像开始后
    预览交接重放几何会改写视频连接并提前终止录像，并把失败原因具体化
- 下游落地：[ADR 0074](../archive/0.0.7/adr/0074-bounded-guided-camera-activation-and-partial-evidence.md)

## 症状

用户选择自动录像或点击主动录像后，相机长时间无法唤醒，界面可能一直停在“正在开启”，没有警告
解释权限、配置、Session 启动还是连接阶段失败。重新点击也可能继续无响应。

设备私有媒体目录可能同时出现可播放但只有极少帧的 HEVC 文件，说明硬件、权限和写文件曾经工作，
但录像在开始后立刻停止。现有 UI 会把这种片段当作完整成功而不提示，用户看到的却仍是“相机没有
唤醒”。

## 根因

1. Coordinator 先 `await prepare()`，返回后才创建完整录像 attempt；BUG 0013 的八秒 timeout 只在
   `startRecording` 里、等待 `didStartRecordingTo` 时建立。
2. `prepare()` 内权限返回后的配置和串行队列 `captureSession.startRunning()` 没有 deadline。
   `startRunning()` 是同步阻塞调用；若不返回，Coordinator 的 `isStartingRecording` 永久为 true，
   没有 attempt 终态和失败 Alert。
3. 共享 preparation task 在失败/悬挂后没有 request generation 隔离，重试可能再次等待同一任务。
4. 执行页只在 `.recording` 时显示 preview；`requestingPermission`、准备中、`.previewing` 和不可用
   状态对用户不可见，无法确认真实画面或调整机位。
5. 恢复旧 Session 时可以还原 `automaticRecordingPaused`，随后又清空 failure；后续自动目标组静默
   跳过录像。
6. Delegate finish 只要文件非空且 error 为空或 success key 为 true 就终结为 `saved`。系统中断、
   后台或异常 stop 产生的极短有效文件因此被误作完整录像，掩盖提前停止。
7. 缺少 interruption ended、foreground 和 video connection active 的恢复验证，Session 曾经可用
   不代表下一次写文件仍然可用。

## 修复

- 按 [ADR 0074](../archive/0.0.7/adr/0074-bounded-guided-camera-activation-and-partial-evidence.md) 把 request 建立前移到
  prepare 之前，权限返回后的配置、Session 启动、连接验证和文件启动全部具有有限终态。
- 用 request generation 隔离迟到的系统结果；失败或超时后新 retry 不复用旧 preparation task。
- 用户选择自动录像后在动作介绍/倒计时阶段执行可见 camera-ready preflight；“不录像”继续按需，
  直到用户点击常驻按钮。
- 执行页显示权限、启动、就绪、写文件中、录像中与不可用状态；红点仍只在 Delegate 确认后出现。
- 写文件前验证 Session、interruption 与 video connection；中断结束、媒体服务重置和返回前台时重新
  验证或重建。
- 记录明确 stop reason。异常提前结束的可播放文件保留为部分证据并提示一次，不能仅凭 success key
  冒充完整成功；用户明确停止仍按正常成功处理。
- 自动暂停原因在 View 重建后保持可见；手动成功 retry 后才恢复自动请求。
- 添加隐私安全阶段日志，不记录路径、动作、重量、身体数据或帧。

## 回归门禁

- 自动化测试：prepare 永不返回必须在 machine deadline 后形成一次失败、清除 starting，并允许新
  request 成功；旧 request 的迟到完成不能覆盖新状态。
- 自动化测试：Session 未运行、被中断或 video connection inactive 时不得盲发 movie command；恢复
  后重新验证。
- 自动化测试：异常提前 finish 的有效文件保留为部分证据并只提示一次；正常用户停止仍无警告；
  success key 不改变 stop reason。
- Coordinator/UI 测试：自动策略提前 preflight、不录像按需、手动意图绑定下一个有效 Effort、无目标
  明确反馈、暂停原因跨重建保持、权限/启动/ready/unavailable 全部可见且 VoiceOver 可达。
- 手工验收：真机验证首次允许/拒绝与设置恢复、正常录像、快速前后台、锁屏、来电/系统中断、低
  存储、连续 retry、绿色相机指示和文件可播放性。
- 仍无法自动化的风险：真实 `AVCaptureSession.startRunning()`、video connection active 与 Movie
  Output Delegate 的设备时序不能由 Simulator 证明。

## 验证

- 当前文档只记录已确认机制与修复门禁，不预先声称代码、`make verify` 或真机交互通过。
- 修复完成后必须记录自动化命令结果；安装到真机只证明构建/签名/安装，不等于上述交互验收。
- 维护者真机验收完成前，本 Bug 保持“修复中”或“代码已修复，待真机复验”。
