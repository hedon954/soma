# BUG 0025：带练录像被连接重配置提前终止，且失败原因不可见

- 状态：首次修复不足，后续见 0026
- 发现日期：2026-08-20
- 影响范围：带练自动/手动录像、录像失败提示、录像诊断日志
- 修订自：
  - [BUG 0020](0020-guided-camera-activation-deadline-and-partial-evidence.md) 的完整 activation
    截止与部分录像证据修复
- 后续修订：
  - [BUG 0026](0026-guided-auto-recording-still-stops-without-reason.md) 定位到开组时预览宿主交接
    与自动放大取景仍会掐断录像，且极短文件被当成正常保存
- 上游依据：
  - [ADR 0074](../archive/0.0.7/adr/0074-bounded-guided-camera-activation-and-partial-evidence.md)
- 下游落地：
  - [PRD 033](../archive/0.0.7/prd/033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md)
  - [PRD 034](../archive/0.0.8/prd/034-history-media-tabs-and-guided-capture-polish.md)
  - [ADR 0083](../archive/0.0.7/adr/0083-local-diagnostics-log-and-silent-crash-reporting.md)

## 症状

带练开始录像后很快结束，界面提示「系统提前结束了录像」。提示不说明是存储不足、被其它 App 抢占、
系统中断还是别的原因，用户无法判断该怎么处理。设备上留下一个可播放但极短的文件。

## 根因

录像开始本身会触发一次相机几何重放：

`didStartRecordingTo` → `cameraStateChanged(.recording)` → `mode = .expandedCapture` →
SwiftUI 更换 preview host → `attachPreviewLayer` 重绑 `AVCaptureSession` 并调用
`applyCaptureGeometry`，后者在录像进行中改写 `AVCaptureMovieFileOutput` 的视频连接旋转与镜像。

AVFoundation 因此结束当前录制，并留下一个可播放的短文件。这条路径落到「非预期结束」分支，
分支使用固定文案且丢弃 `Error` 对象，所以真实原因既不显示也不落日志。

`AVCaptureSession.automaticallyConfiguresApplicationAudioSession` 保持默认开启，而带练在同一时刻
播报语音提示，音频会话竞争会放大中断概率。

手工路径修好后，自动路径仍会失败：`beginCurrentSet` 先 `setPhase(.setInProgress)`，SwiftUI 拆掉
倒计时 PIP 并换到 set-hero 宿主，此时 `isRecording` 仍为 false，第一轮几何守卫拦不住
`applyCaptureGeometry` 改写 movieOutput。手动开始时宿主已经稳定，所以看起来「手动可以、自动不行」。

## 修复

- `applyCaptureGeometry` 的 movieOutput 分支在 `startingRecording`、`recording` 或
  `movieOutput.isRecording` 时跳过。录像前已锁定几何，启动窗口和录像中改写既违规也无用；
  preview 分支保留。
- `attachPreviewLayer` 在 `layer.session === captureSession` 时不再 `session = nil` 重绑，
  录像中的 host 交接只更新 preview。
- 配置阶段设 `automaticallyConfiguresApplicationAudioSession = false`（本就没有音频输入），
  并把 `beginCurrentSet` 的语音播报移到录像真正开始之后。
- 自动录像改为：倒计时结束先在现有 PIP 宿主 `startRecording`，等到 `didStartRecordingTo` 成功后再
  `setPhase(.setInProgress)`，避免 `isRecording` 仍为 false 时拆宿主。
- 新增 `WorkoutRecordingFailureDiagnosis`：把 `AVError.Code` 与 `AVCaptureSession.InterruptionReason`
  映射为具体中文原因，并附带 `（domain code · stage）` 技术标识。非预期结束与中断都改用这份诊断，
  同时写入诊断日志。

## 回归门禁

- 自动化测试：错误码到文案映射、中断原因到文案映射、未知原因保留原始码、部分与完全失败文案保留
  技术标识。
- `make check` 静态门禁：`applyCaptureGeometry` 必须在 `startingRecording` 或 `recording` 时跳过
  movieOutput 几何改写。
- 手工验收：真机连续 3 组带练录像；分别验证后台切换、来电中断与语音提示开关，确认提示给出对应原因，
  诊断日志能查到阶段与技术标识。录像根因的最终结论以真机复验为准。

## 验证

- `WorkoutRecordingFailureDiagnosisTests`
- `GuidedWorkoutRecordingRecoveryTests`
- 夹具只使用虚构动作与本地临时文件，不含真实身体影像。
