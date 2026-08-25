# BUG 0006：带练预览与保存录像画幅不一致

- 状态：基础画幅合同已修复；真机交互回归由 BUG 0007 继续修订
- 发现日期：2026-08-03
- 影响范围：iPhone 计划带练的自动录像、全身取景和横竖屏使用
- 上游依据：
  - [训练计划编排、沉浸式带练与真实取景调研](../research/2026-08-03-guided-workout-flow-and-capture.md)
- 下游落地：
  - [PRD 013](../archive/0.0.1/prd/013-guided-workout-experience-and-capture.md)
  - [ADR 0038](../archive/0.0.1/adr/0038-focused-guided-workout-and-capture-geometry.md)
- 后续修订：[BUG 0007](0007-guided-workout-countdown-capture-orientation-regression.md) 修复倒计时、手动放大和方向协调器初始化时机

## 症状

- 相机卡片显示的范围可能小于最终录像，或用户为填满卡片而错误摆放设备。
- iPhone 带练只能竖屏，无法使用更适合全身动作的横屏构图。
- 预览与 Movie Output 没有共同方向合同，旋转设备时行为不可预测。
- 当前固定 180pt 相机卡片与真实传感器比例无关，容易让用户误以为卡片边界就是输出边界。

## 根因

1. `WorkoutCameraPreview` 使用 `.resizeAspectFill`，该策略会为了填满视图裁切水平或垂直内容。
2. Movie Output 只设置前置镜像，没有显式设置与预览一致的 `videoRotationAngle`。
3. 没有在录像开始时锁定方向，预览层也没有 `AVCaptureDevice.RotationCoordinator`。
4. iPhone `UISupportedInterfaceOrientations` 只声明 portrait。
5. 紧凑与放大取景没有统一组件和 Session 生命周期合同。

## 修复

- 按 [ADR 0038](../archive/0.0.1/adr/0038-focused-guided-workout-and-capture-geometry.md) 建立 Capture Geometry。
- 预览改为 `.resizeAspect`，明确接受留白并展示完整输出画幅。
- 预览与文件显式同步镜像和旋转角；开始录像时锁定本段几何。
- 带练期间开放 portrait/landscape 左右方向，其他页面继续竖屏。
- 紧凑与放大态共享同一 Capture Session，切换只改变 UI 投影。

## 回归门禁

- 自动化测试或静态检查：Capture Geometry 方向映射、录像期间锁定、停止后恢复；禁止带练预览回退到 `.resizeAspectFill`。
- 手工验收：竖屏/横屏分别录制并逐边比较预览与文件；录制中旋转；收起和放大不中断。
- 仍无法自动化的风险：不同前置摄像头、安全区、系统方向锁定、来电/后台中断和设备编码行为。

## 验证

- `WorkoutCaptureGeometry` 的 portrait、landscape left/right 映射由单元测试覆盖。
- 模拟器已验证紧凑态、放大竖屏态、GUI 选动作、单步完成与中断恢复；参考图和实际截图的
  并排审查记录在仓库根目录 `design-qa.md`。
- `make check` 与 `make verify` 是合并门禁，最终命令证据随本次提交记录。
- 真实前置相机的画幅、镜像、横竖屏、录制中旋转和系统中断仍由维护者真机验收；完成前不把
  这些设备体验标记为已通过。
- 首轮真机验收随后发现倒计时驱动、手动取景切换和方向协调器进入窗口前初始化的问题；该批
  后续回归的机制、修复与二次验收见 [BUG 0007](0007-guided-workout-countdown-capture-orientation-regression.md)。
