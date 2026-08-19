# BUG 0013：带练录像启动无终态且失败提示不可见

- 状态：首次修复不足；写文件回调截止已落地，完整相机 activation 由 BUG 0020 继续修复
- 发现日期：2026-08-12
- 影响范围：计划带练自动/手动录像、相机错误恢复与诊断
- 上游依据：[BUG 0010](0010-guided-recording-state-and-cue-gaps.md) 的启动回调与错误投影修复
- 后续修订：
  - [BUG 0019](0019-guided-recording-attempt-terminal-and-duplicate-alerts.md) 记录启动成功后系统提前终结、成功 key 误判、陈旧活动状态与多 Alert 源造成的重复提示
  - [BUG 0020](0020-guided-camera-activation-deadline-and-partial-evidence.md) 记录旧“启动截止时间”只覆盖写文件回调、没有覆盖权限后配置与 `startRunning()`，以及不可见预览、静默暂停和极短文件误报完整成功
- 下游落地：[PRD 026](../prd/026-guided-workout-record-projection-camera-failures-and-session-entry.md)

## 症状

进入目标组后录像一直没有显示；界面可能停在“正在开启相机”，没有稳定可见的失败警告，也没有
足以区分权限、配置、启动回调或写入阶段的安全诊断日志。相同错误重试时可能不再触发提示。

## 根因

`WorkoutCameraService.startRecording` 用 checked continuation 等待系统 Delegate，但没有启动
截止时间；系统既不调用 start 也不调用 finish 时，调用永久悬挂。Coordinator 只保存一条错误
字符串且下次请求前不建立新的失败事件，相同文本不能可靠驱动 SwiftUI `onChange`。UI 又把错误
映射成自动消失的 toast，未满足需要用户确认的失败态；相机链没有阶段化 OSLog。

## 修复

- 为 Delegate 启动确认增加有限等待；超时后取消待写入、停止 Capture Session 并返回可恢复错误。
- 每次失败生成独立事件；权限、配置、启动、停止/写入和系统中断记录阶段、类型与 domain/code，
  不记录媒体路径或身体数据。
- 带练页把录像失败统一投影为系统警告框；权限拒绝可进入系统设置，训练状态机继续运行。

## 回归门禁

- 自动化测试：Coordinator 相同错误连续失败会产生两个失败事件；相机启动超时消息与清理状态可测。
- 手工验收：真机分别验证正常录像、拒绝权限、快速前后台和系统中断，失败均有警告且组可继续。
- 仍无法自动化的风险：真实 `AVCaptureFileOutput` Delegate 时序和系统绿色相机指示需真机确认。

## 验证

- `make verify` 通过：格式、SwiftLint、Actions/shell/文档/仓库契约、Server TypeScript、
  Server 测试、iOS 模拟器构建与单元测试全部通过。
- iPhone 17 Pro 模拟器拒绝相机权限后，带练页弹出“录像无法继续”，同时提供“好”和“打开设置”；
  关闭后用同一组再次录像会再次弹出。
- 模拟器 OSLog 的 `GuidedWorkoutRecording` 分类只出现 `stage=permission/start`、错误类型、
  domain/code，没有视频路径、动作、重量或其他身体内容。
- 仍需真机验证正常前置录像、8 秒启动截止、前后台/来电/热压力中断、绿色相机指示与落盘文件。
