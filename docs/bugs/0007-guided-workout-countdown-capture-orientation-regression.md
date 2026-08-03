# BUG 0007：带练倒计时、取景切换与方向投影回归

- 状态：已修复；待维护者真机复验
- 发现日期：2026-08-03
- 影响范围：iPhone 计划带练的组前倒计时、手动完整取景与横竖屏录像
- 修订自：[BUG 0006](0006-workout-camera-preview-recording-mismatch.md) 的首次画幅修复与真机验收结论
- 后续修订：暂无
- 关联需求：[PRD 013](../prd/013-guided-workout-experience-and-capture.md)
- 关联决策：[ADR 0038](../adr/0038-focused-guided-workout-and-capture-geometry.md)

## 症状

1. 组前倒计时显示到 `1` 后停住，没有自动进入本组。
2. 非目标录像组点击相机小窗后，没有稳定切换到完整取景。
3. 竖屏设备可能显示横向取景框和左右黑边，横竖屏布局与真实摆放不一致。

用户提供的真机截图只用于本次本地诊断，不进入仓库、测试夹具或 Issue。

## 根因

1. 倒计时推进挂在外层 `GuidedWorkoutView.task(id:)`，依赖 SwiftData 阶段字段触发任务重建；
   倒计时组件自身只更新时间文本，不拥有完成事件，因此 View 未重建时会永久停在 `1`。
2. 手动放大只是修改一个枚举，但相机 `state` 的后续 `previewing` 回调会把放大态改回紧凑态；
   同时 UIKit 预览层位于 SwiftUI `Button` 内，没有显式关闭命中测试。
3. `AVCaptureDevice.RotationCoordinator` 在 `AVCaptureVideoPreviewLayer` 进入窗口层级前创建。
   Apple 对该 API 的合同是：预览层尚未进入 View hierarchy 时，preview rotation 返回 `0°`；
   这个无效初值被解释为横屏并缓存。训练开始前的校准页又尚未开启带练方向策略，使横放设备
   时界面更难及时旋转。

## 修复

- 由可见的 `GuidedSetCountdownView` 持有基于绝对截止时间的异步任务，倒计时到 `0` 后直接调用
  `beginCurrentSet`；离开页面会取消任务，重复回调由当前阶段守卫阻止。
- 使用可测试的 `GuidedWorkoutPresentationState`：手动放大只由用户收起，`recording` 可以自动
  放大，普通 `previewing` 不再覆盖用户选择；相机画面关闭命中测试，整张小窗成为按钮区域。
- `CameraPreviewView` 只在 `didMoveToWindow` 后通知相机服务绑定预览层并创建 Rotation
  Coordinator；同层更新只重用当前协调器。
- 从开始前校准页起启用横竖屏策略，进入带练时再次请求当前 Scene 更新，取消或结束后恢复竖屏。

## 回归门禁

- `GuidedSetCountdownClock` 覆盖 `3 → 1 → 0`、截止时间和过期立即推进。
- `GuidedWorkoutPresentationState` 覆盖手动放大不被 `previewing` 收回、录像开始自动放大。
- `CameraPreviewView` 测试进入 UIWindow 前不发布预览层，进入后才发布。
- 方向策略测试确认非带练仅竖屏，校准和带练允许 portrait/landscape left/right。
- `make verify` 保持全量构建与回归门禁。

## 真机复验

1. 第 1 组倒计时显示 `3、2、1` 后自动进入执行，不需要额外点击。
2. 非录像组点击整个相机小窗，立即进入完整取景；收起后可以再次进入。
3. 在校准页和带练页分别竖放、左横放、右横放设备，界面布局和预览画幅同步变化。
4. 目标录像组开始后仍自动放大；录制中旋转不改变当前片段，下一片段重新读取方向。
