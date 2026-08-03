# ADR 0038：带练使用聚焦投影并锁定录像几何

- 状态：已采纳
- 日期：2026-08-03
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0030](0030-deterministic-guided-workout-and-session-recording.md) 的阶段 UI、两步组确认和未定义录像画幅
  - [ADR 0036](0036-gui-training-program-authoring.md) 的常驻展开处方与不提供历史值快捷入口
- 后续替代：暂无
- 上游依据：
  - [PRD 013](../prd/013-guided-workout-experience-and-capture.md)
  - [训练计划编排、沉浸式带练与真实取景调研](../research/2026-08-03-guided-workout-flow-and-capture.md)
  - [BUG 0006](../bugs/0006-workout-camera-preview-recording-mismatch.md)
- 下游落地：[训练领域模型与运行时协议](../engineering/training-domain-model.md)

## 背景

确定性状态机、不可变 Session 快照和每动作一段录像仍然正确，但现有 View 把每个状态直接
投影成独立页面，导致训练中信息跳变和重复确认。相机层没有定义预览、文件、方向与镜像的共同
合同，`.resizeAspectFill` 会裁切；iPhone 声明又只允许竖屏。

## 决策

1. `WorkoutSession`、`ExercisePerformance`、`WorkoutSet` 与
   `GuidedWorkoutCoordinator` 继续是训练事实和恢复事实来源；紧凑/放大只是 UI 投影状态。
2. 常规 Set 在 `.setInProgress` 中以一次显式操作确认屏幕上的实际值并保存；
   `.setConfirmation` 只用于恢复、纠错或显式编辑，不再是每组必经页面。
3. 休息保存确定的目标结束时间，增减时间修改该时间；实际休息仍由开始与完成时间派生。
4. GUI 可以提供“使用上次”，但必须由用户点击，并通过共享确定性解析器只复用明确字段。
5. `WorkoutCameraService` 建立统一 Capture Geometry：
   - 预览和文件显式使用相同镜像策略；
   - 使用 `.resizeAspect` 完整展示输出，不以裁切填满；
   - `AVCaptureDevice.RotationCoordinator` 提供预览与捕获角度；
   - 开始录像时锁定当前角度、方向和镜像，停止后恢复监听。
6. 紧凑态与放大态共享同一 `AVCaptureSession` 和同一 `AVCaptureVideoPreviewLayer`。UI 容器只
   重新挂载预览层；每个容器有稳定 Host 身份，旧 Host 不得在新 Host 接管后抢回或移除预览层；
   切换不得停止 Session、重建输出、重建预览层或改变文件。
7. 目标录像组成功开始后自动进入放大态；用户收起只改变显示，录像继续。
8. iPhone 声明横竖屏能力；App Delegate 只在带练期间返回 portrait/landscape 左右方向，其他
   页面继续竖屏。退出带练时恢复竖屏策略。
9. 横屏使用相机/控制栏分栏，不只是把竖屏页面整体旋转；竖屏使用相机/组信息上下布局。
10. 训练 Live Activity 使用独立 Attributes，只投影通用阶段、进度和休息时间；点击回到活动
    Session，不与 Agent Job Activity 混用。
11. 相机失败、系统方向锁定或 ActivityKit 不可用只降级对应体验，不改变 Set 事实。
12. Session、预览和文件 I/O 在专用串行队列执行。倒计时归零后先提交训练状态，任何相机准备、
    启动或停止都不得占住 Main Actor；界面横竖布局读取当前 Scene 尺寸，不读取锁定的片段方向。
13. 录像输出状态与预览可见状态分别投影。UI 使用 Preview Layer 的真实渲染状态展示连接、可见或
    失败；预览失败只降级相机表面并明确原因，不得用录像红点掩盖黑屏。

## 未选择的方案

- 两个独立相机会话分别服务小窗和大窗：切换成本高且可能中断文件。
- 继续使用 `resizeAspectFill`：视觉饱满但无法承诺预览即所得。
- 录制中持续追随设备旋转：会让同一片段的方向和构图改变。
- 整个 App 开放自由横屏：把训练场景的特殊需求扩散到聊天和进展页。
- 每组保留确认页：增加高频点击且不增加事实可信度。
- 自动把历史非一致组压缩成单个值：会把推测写成计划事实。

## 结果

### 正向影响

- 动作示范、录像和组确认在一个稳定训练表面中完成。
- 用户看到的完整画面与文件边界一致，横竖屏行为可解释。
- 录像 UI 切换不影响训练事实或文件生命周期。
- 最近值和单步完成降低计划创建与逐组执行摩擦。

### 成本与限制

- iPhone 需要声明横屏，并由 App Delegate 动态约束其他页面。
- SwiftData/DTO 增加休息恢复字段，需要覆盖备份恢复兼容。
- Simulator 不能证明真实相机画幅、镜像和方向，必须保留真机验收。
- 系统方向锁定可能阻止界面旋转，App 只能给出提示并保持训练可用。

## 验证

- 单元测试覆盖最近容量、单步完成、休息结束时间、恢复选择和 Capture Geometry 锁定。
- 模拟器覆盖紧凑/放大、横竖布局、深浅色、Dynamic Type、安全区和长文案。
- 真机比较竖屏与横屏的预览和保存视频，并在录制中旋转设备。
- `make check` 验证双向文档生命周期，`make verify` 验证完整构建与回归。

## 参考

- [PRD 013](../prd/013-guided-workout-experience-and-capture.md)
- [ADR 0029](0029-versioned-training-plans-and-session-facts.md)
- [ADR 0030](0030-deterministic-guided-workout-and-session-recording.md)
- [ADR 0036](0036-gui-training-program-authoring.md)
- [AVCam](https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app)
