# BUG 0008：带练训练状态与相机投影未真正解耦

- 状态：首次共享层修复不足；Host 所有权与可见性由 BUG 0009 继续修订
- 发现日期：2026-08-03
- 影响范围：iPhone 计划带练的倒计时结束、完整取景切换、横竖屏布局与相机可视面积
- 修订自：[BUG 0007](0007-guided-workout-countdown-capture-orientation-regression.md) 的首次倒计时、取景切换与方向修复
- 后续修订：[BUG 0009](0009-guided-workout-preview-host-ownership-and-visible-state.md) 修复旧 Host 抢回共享层、静默黑屏和放大态信息缺失
- 关联需求：[PRD 013](../prd/013-guided-workout-experience-and-capture.md)
- 关联决策：[ADR 0038](../adr/0038-focused-guided-workout-and-capture-geometry.md)

## 症状

1. 倒计时已经显示 `0`，界面仍停留数秒甚至更久，直到相机开始录像后才进入本组。
2. 点击“完整取景”或“收起”后有明显等待、黑屏或不连贯，无法像同一个训练表面即时切换。
3. 横竖屏页面虽能变化，但取景框比例、内容方向和选定实现图不一致；相机区域偏小，难以看清全身。

用户提供的真机截图只用于本地诊断和视觉对照，不进入仓库、测试夹具或外部 Issue。

## 根因

1. `GuidedWorkoutCoordinator` 先保存 `.setInProgress`，但随后仍在主执行链等待
   `AVCaptureMovieFileOutput.startRecording`。该调用位于 `@MainActor`，相机启动慢时会占住 UI
   Run Loop，导致已经保存的训练状态无法及时呈现。
2. 紧凑态和放大态分别创建 `AVCaptureVideoPreviewLayer`。SwiftUI 分支切换会先拆旧层、再绑定新层，
   Rotation Coordinator 也随之重建，因此一次纯布局切换被放大为相机资源切换。
3. View 使用录像期间锁定的 `captureGeometry.orientation` 决定界面宽高比。录像几何应固定文件，
   但不应反过来决定当前 SwiftUI 是横屏还是竖屏。
4. 方向策略只把 portrait/landscape 的并集交给 Scene，没有按 `UIDeviceOrientation` 请求当前精确
   方向；已经横放的设备仍可能维持竖屏界面。
5. 横屏控制栏和紧凑相机小窗使用固定宽度，未把“相机尽可能大”设为布局约束。

## 修复

- 训练状态先确定性保存并立即投影；相机准备、开始与停止统一在串行相机队列执行，不再阻塞
  Main Actor。重复 `prepare` 合并为同一个任务，相机慢或失败只显示准备/降级状态。
- `WorkoutCameraService` 持有唯一共享 `AVCaptureVideoPreviewLayer`；紧凑和放大容器只重新挂载该层，
  不销毁 Session、输出或 Rotation Coordinator。移除切换淡入淡出，点按即时改变投影。
- 界面比例只由当前可用宽高决定：竖屏使用 portrait 取景，横屏使用 landscape 取景；
  `WorkoutCaptureGeometry` 继续只负责预览/文件旋转、镜像和当前片段锁定。
- 带练期间监听设备方向并向当前 Scene 请求精确方向；退出带练后移除监听并恢复 portrait。
- 紧凑相机小窗按容器宽度放大；竖屏放大态把主要可用高度给相机；横屏压窄控制栏，保证相机
  获得至少约 68% 的可用宽度。

## 回归门禁

- 协调器测试在录像启动仍挂起时检查 Session 和 Set 已经进入 `setInProgress`。
- 预览测试把同一 `AVCaptureVideoPreviewLayer` 从紧凑 Host 迁移到放大 Host，并确认旧 Host 的
  清理不会把新 Host 中的层移除。
- 布局测试固定竖屏 `9:16`、横屏 `16:9`，并约束紧凑小窗和横屏相机的最小占比。
- 方向测试覆盖 portrait、landscape left/right 的设备方向到界面方向映射。
- `make verify` 继续覆盖静态门禁、构建与模拟器测试。

## 真机复验

1. 倒计时从 `1` 到 `0` 后立即出现本组执行界面；相机尚未就绪时显示“相机准备中”，训练仍可操作。
2. 连续点击完整取景、收起、再次放大，确认没有黑屏、重新启动相机或明显等待，录制红点连续。
3. 竖屏放大态对照选定竖屏实现图：相机占主要面积，顶部为关闭、暂停/计时和更多。
4. 左横放和右横放分别对照横屏实现图：大相机在左，窄控制栏在右，画面和文字均保持正向。
5. 紧凑、开始前校准、竖屏放大和横屏放大四处确认相机都使用当前布局允许的最大区域。
