# 带练录像策略、语音节奏、完成反馈与历史管理调研

- 日期：2026-08-04
- 状态：已转化为正式 PRD、ADR 与 Bug 修复契约
- 修订自：[训练计划编排、沉浸式带练与真实取景调研](2026-08-03-guided-workout-flow-and-capture.md) 的录像触发、语音提示和训练结束部分
- 下游落地：
  - [PRD 014](../archive/0.0.1/prd/014-guided-workout-recording-cues-and-review.md)
  - [ADR 0039](../archive/0.0.1/adr/0039-event-driven-guided-recording-cues-and-review.md)
  - [BUG 0010](../bugs/0010-guided-recording-state-and-cue-gaps.md)

## 结论

带练中的相机、语音和总结不能只是跟随页面显示的附属效果，而应是确定性训练事件的三个投影：

```text
进入本组 → 组前倒计时 → 本组开始 → 可选录像 → 本组完成
        → 休息/下一组 → 全部完成 → 本地总结 → 历史复盘或删除
```

录像策略只决定“何时自动发起录像”，不能反过来决定“当前是否真的正在录像”。实际录像必须拥有
独立状态并绑定到具体 `WorkoutSet`。相机只有在某一组真正请求录像时才初始化；没有录像时，带练
保持动作示意主视觉，不显示黑色空窗，也不申请或占用相机。

## 当前体验审计

维护者提供的两张真机截图仅在本次本地诊断中查看，不复制进仓库、测试夹具或外部 Issue。

### 1. 自动录像失败态

- 画面已经显示前置相机，但录像状态由计划策略推断，出现“录像失败：无法录制”后仍保留取景器。
- 用户无法判断这是权限、启动、文件写入还是系统中断，也无法在当前组立即重试。
- 自动录像关闭时，当前组没有显式“录制本组”入口。

### 2. 紧凑取景器

- 小窗使用完整适配，在容器比例和相机画面比例不一致时产生上下黑边。
- 黑边既不增加取景信息，也挤压动作示意。紧凑小窗的任务是快速确认站位，应裁切填满；只有
  放大“完整取景”继续承担保存画幅边界的解释责任。

### 3. 语音节奏

- 当前只在状态机进入倒计时时播报一次“准备第 N 组”。
- 倒计时 3/2/1、正式开始、后续组、休息即将结束、下一个动作和训练完成没有事件。
- `AVSpeechSynthesizer` 会排队播放 utterance；如果不清理过期队列，迟到语音会与当前训练阶段错位。

### 4. 结束与历史

- 结束页只有一段汇总文本，没有训练时长、动作/组数、录像数量、跳过情况和动作明细。
- 历史列表可以进入复盘，但缺少系统一致的右侧左滑删除，错误或试跑 Session 无法低摩擦清理。

## Apple 平台证据

### 录像启动与完成

`AVCaptureFileOutputRecordingDelegate` 分别提供 `didStartRecordingTo` 与
`didFinishRecordingTo`。因此，调用 `startRecording` 只表示发出了请求；Soma 应等待
`didStartRecordingTo` 后才把 UI 标为“正在录制”，并在 `didFinishRecordingTo` 后保存文件或展示
可操作错误。

- [AVCaptureFileOutputRecordingDelegate](https://developer.apple.com/documentation/avfoundation/avcapturefileoutputrecordingdelegate)
- [AVCaptureMovieFileOutput](https://developer.apple.com/documentation/avfoundation/avcapturemoviefileoutput)

### 预览填充

Apple 定义 `resizeAspectFill` 为保持比例并填满图层，代价是水平或垂直裁切。因此它适合只用于
紧凑站位小窗；放大完整取景继续用 `resizeAspect` 展示完整画幅，二者必须向用户表达不同任务。

- [AVLayerVideoGravity.resizeAspectFill](https://developer.apple.com/documentation/AVFoundation/AVLayerVideoGravity/resizeAspectFill)
- [AVCaptureVideoPreviewLayer.videoGravity](https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer/1386708-videogravity)

### 语音队列

`AVSpeechSynthesizer` 会把新 utterance 加入队列；`stopSpeaking(at:)` 会取消当前和未播报内容。
训练阶段变化时应删除已经过期的语音，再播报当前阶段，避免上一组提示拖到下一组。

- [AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)
- [stopSpeaking(at:)](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/stopspeaking%28at%3A%29)

### 历史删除

SwiftUI `swipeActions` 是 List 行的原生尾随操作；SwiftData 删除需要在 `ModelContext` 中显式删除
相关模型并保存。Soma 当前以 UUID 关联 Session、Performance、Set 与 Analysis，没有关系级联，
因此必须由共享 Store 完成确定性级联和私有媒体回收。

- [View.swipeActions](https://developer.apple.com/documentation/swiftui/view/swipeactions%28edge%3Aallowsfullswipe%3Acontent%3A%29)
- [ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext)

## 产品取舍

- 自动录像保持本次训练显式开启；开启后默认“每个动作录一组”，也可选“每一组都录”。
- “每个动作录一组”继续跳过已标记的热身首组，选择首个工作组；“每一组都录”包含热身组。
- 没有自动录像或当前组不属于自动目标时，用户仍可在本组执行页点击“录制本组”。
- 只有系统确认录像开始后才显示相机小窗并自动提供放大入口；失败时回到动作示意并显示原因和重试。
- 录像证据绑定到 Set；动作级视频只是兼容旧分析入口的首段引用。
- 语音由状态事件驱动，至少覆盖准备、3/2/1、开始、完成/休息、下一动作和训练完成。
- 训练结束先展示本地确定性总结，不自动消耗模型 Token；用户可再主动进入教练复盘。
- 历史删除同时删除 Session、Performance、Set、Analysis 与只属于该 Session 的私有录像。

## 隐私与失败

- 相机不再因打开开始页、进入动作说明或执行无录像组而启动。
- 麦克风继续关闭；语音指导只输出，不采集音频。
- 录像启动失败不阻止训练；错误必须显示阶段和恢复动作，不能只留下黑窗或红点。
- 删除训练历史不会删除系统相册内容，只回收 Soma 私有目录中的该 Session 证据。
