# BUG 0026：自动录像仍在开组时被预览宿主交接掐断，且被当成正常结束

- 状态：已修复，待真机复验
- 发现日期：2026-08-21
- 影响范围：带练自动录像（录第一组 / 每一组都录）、放大取景、完成后分享导航
- 修订自：
  - [BUG 0025](0025-guided-recording-terminated-by-connection-reconfiguration.md) 的 movieOutput
    几何守卫与「PIP 上先 startRecording 再切组」策略
- 上游依据：
  - [ADR 0074](../archive/0.0.7/adr/0074-bounded-guided-camera-activation-and-partial-evidence.md)
- 下游落地：
  - [PRD 035](../archive/0.0.9/prd/035-guided-preview-then-record-and-immediate-share.md)

## 症状

v0.0.8 真机上，自动录像在第一组或每一组都会很快自己关掉。界面没有「录像无法继续」原因，
只剩一个极短可播放文件。手动在已经稳定的执行页上开始录像仍然更可靠。

## 根因

BUG 0025 拦住了 `applyCaptureGeometry` 改写 `movieOutput`，但开组瞬间仍会换预览宿主，
并且会把已经跑着的 Capture Session 当成中断：

1. `cameraStateChanged(.recording)` 或开组进入 `.setInProgress` 把界面切到放大取景；
2. 倒计时 PIP 卸下、放大页挂上时 `hostID` 变化；`hasLivePreview` 若只看
   `RotationCoordinator`，预览已在跑也会被当成需要重建；
3. 预览层重绑会发出 `AVCaptureSessionWasInterrupted`。当时还没有 recording attempt，
   `interrupt()` 会 `stopCaptureSession`，状态离开 `.previewing`；
4. `startRecording` 因此再次 `prepare()`（日志里 `attempt-request` 后紧跟
   `permission-request` / `configure` / `session-start`），嵌套 `beginConfiguration`
   后本次 attempt 到不了 `movie-command` / `did-start`。

启动哨兵报告（「启动哨兵未被正常清位」）只说明上次前台进程被杀掉或覆盖安装，不是这次
录像失败的原生崩溃栈。诊断正文里的 `[workout-recording]` 阶段日志才是录像路径。

`attachPreviewLayer` 在新宿主上若重建 `RotationCoordinator` 并重绑 preview session，
已经开始写文件时还会让 AVFoundation 结束当前文件且 success key 常为 true，于是走完整
`saved` 而不是带原因的 `savedPartial`。

## 修复

- 倒计时只取景；开组后自动进入放大取景，等该宿主挂上再 `startRecording`。
- 进入 `.recording` 不再二次自动放大。用户可缩小到小窗继续录像；小窗身份在录像前后不变。
- 录像中以及已有预览连接时，`detachPreviewLayer` / `attachPreviewLayer` 不得拆除
  RotationCoordinator 或 preview session；`hasLivePreview` 以 layer session 与相机状态
  为准，不要求 RotationCoordinator 已经存在。
- 带练仍持有 session owner 时，预览阶段的 `session-interruption` 不得停掉 Capture
  Session；`prepare()` 在 Session 仍在跑时直接复用，不得再走 permission/configure。
- 异常结束必须写入诊断日志和调用栈。
- 执行页小窗与动作介绍小窗使用同一固定 9:16 尺寸，默认贴在示范图右侧垂直居中，可拖动，且可点击进入放大取景。
- 「每个动作录第一组」时后续组不显示取景，并释放 Capture Session。
- 计划执行结束（含提前结束）后直接出分享预览，关闭后回到训练主页。

## 回归门禁

- 自动化：`testAutomaticRecordingStartsAfterSetIsInProgress` 断言 `startRecording` 时已经
  处于 `.setInProgress`；`testSetStartExpandsCaptureAndCollapseSurvivesRecording`；
  `testEnabledPolicyDoesNotRecordLaterSetsAndReleasesPreview`；
  `testEndEarlyAbandonsSessionWithoutRequiringRemainingSets`；
  `testPreviewHostSettlementWaitsForANewHost`；`testPreviewHostDetachSkipsTeardownWhileRecording`；
  `testPreviewHostDetachSkipsTeardownWhilePreviewing`。
- `make check`：`beginCurrentSet` 必须 `waitUntilPreviewHostSettled`；
  `attachPreviewLayer` 必须按 `shouldRebuildCaptureConnections` 跳过录像中的连接重建；
  `prepare()` 必须能 `prepare-reused-running-session`。
- 手工验收：真机「每个动作录第一组」开组后进入放大录制、可缩小继续录、第 2 组无预览；
  「每一组都录」连续至少 3 组；提前结束也出分享，关闭后回到训练主页。

## 验证

- `GuidedWorkoutCoordinatorTests`
- `WorkoutCameraServiceTests`
- 夹具只使用虚构动作与本地临时文件，不含真实身体影像。
