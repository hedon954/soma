# 训练计划编排、沉浸式带练与真实取景调研

- 日期：2026-08-03
- 状态：已转化为正式 PRD、ADR 与 Bug 修复契约
- 修订自：[动作库、训练计划、程序化带练与训练视频复盘调研](2026-07-31-exercise-library-plans-guided-training.md) 的计划执行体验与录像部分
- 下游落地：
  - [PRD 013](../prd/013-guided-workout-experience-and-capture.md)
  - [ADR 0038](../adr/0038-focused-guided-workout-and-capture-geometry.md)
  - [BUG 0006](../bugs/0006-workout-camera-preview-recording-mismatch.md)

## 结论

Soma 的计划带练应是“自主节奏的逐组教练”，而不是固定时长的视频课程。训练中的一屏只回答
四件事：现在做什么、目标是什么、做到第几组、下一步按什么。动作示范、用户取景、组数和主
按钮必须在同一视觉层级中完成，不能要求用户在训练中频繁跳页。

```text
计划库 → GUI/聊天建计划 → 计划详情 → 录像校准
      → 动作示范 → 本组执行 → 休息 → 下一组 → 本地总结
```

## 竞品证据

### Keep

Keep 当前产品继续强调课程跟练、AI 语音指导和简化后的核心入口。可借鉴的是“当前动作占据主
视觉、辅助信息退后、训练中只保留必要控制”，但 Soma 不复制课程商城、时间轴视频课程或第三方
内容资产。

- [Keep App Store](https://apps.apple.com/cn/app/keep-ai-%E8%BF%90%E5%8A%A8%E6%95%99%E7%BB%83/id952694580)

### Hevy

Hevy 把计划作为 Routine 启动，训练时逐组完成、调整重量与次数、自动进入休息；历史值允许用户
主动复用。它证明力量训练的主循环应围绕 Set，而不是围绕长表单或聊天轮次。

- [Track Workouts](https://www.hevyapp.com/features/track-workouts/)
- [Track Exercises](https://www.hevyapp.com/features/track-exercises/)
- [Live Activity](https://help.hevyapp.com/hc/en-us/articles/35649846517399-How-to-Use-Hevy-s-Live-Activity-on-iOS-and-Android)

### Fitbod

Fitbod 在记录一组后立即启动休息计时，并通过声音、震动和后台通知提示用户。可借鉴的是休息
阶段的自动进入和单一倒计时事实，不复制其推荐算法进入每一组的确定性执行路径。

- [Rest Timer](https://help.fitbod.me/hc/en-us/articles/360006340194-Rest-Timer)

## 产品取舍

### 计划创建

- 聊天适合生成草案和自然调整；GUI 适合动作选择、排序、比较和处方编辑。
- 动作行默认只展示图片、名称和处方摘要，编辑字段进入次级面板。
- “使用上次”必须由用户点击；只复用最近完成记录中可确定的字段，不自动调用 AI。

### 带练

- 紧凑态以动作示范为主，相机小窗为辅；完成当前组是唯一主按钮。
- 目标录像组开始后自动放大取景，用户可以收起且不终止录像。
- 完成本组即确认屏幕上的实际值并落盘，常规路径不再经过第二个保存页。
- 休息阶段只显示倒计时、下一组、增减时间与跳过。

### 视频

Apple 明确说明 `resizeAspectFill` 可能裁切水平或垂直内容，因此不能用它承诺“预览即所得”。
预览和文件必须共享方向、镜像与完整画幅，必要时接受留白。

- [AVLayerVideoGravity.resizeAspectFill](https://developer.apple.com/documentation/AVFoundation/AVLayerVideoGravity/resizeAspectFill)
- [AVCaptureConnection.videoRotationAngle](https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videorotationangle)
- [AVCaptureDevice.RotationCoordinator](https://developer.apple.com/documentation/avfoundation/avcapturedevice/rotationcoordinator)
- [AVCam](https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app)

方向规则是：录像开始前跟随设备当前摆放，开始后锁定本段视频；录制中旋转手机不改变当前
文件，停止后才重新跟随。横竖屏只在沉浸式带练中开放，其他页面维持竖屏。

## 隐私与失败

- 前置摄像头、麦克风关闭、每动作一段、视频留在 App 私有目录。
- 不识别旁人、不承诺实时人体检测；安全框只是取景提示。
- 相机权限、中断、后台、磁盘和热压力失败只停止录像，不改变 Set 事实。
- Live Activity 只显示训练状态、进度和休息时间，不显示动作、重量、媒体或身体数据。
- AI 与视频复盘只由用户主动触发。

## 实施原则

1. 先修复 capture-exact 画幅与方向合同，再做视觉放大动画。
2. UI 展示状态不成为训练事实；Session、Performance、Set 继续是恢复事实来源。
3. 单步完成、休息结束时间和相机错误使用确定性测试覆盖。
4. 相机真实画幅、系统方向锁定和 Live Activity 留给真机手工验收。
