# ADR 0119：完整视频与直接追加的本地听写

- 后续替代：[ADR 0131](0131-explicit-video-rejection-frame-fallback.md)（仅明确拒绝视频后的回退策略；语音与其他边界不变）

- 上游依据：[Apple 本地听写调研](../research/2026-09-05-apple-local-speech.md)
- 下游落地：[BUG 0054](../bugs/0054-full-video-playback-and-dictation-regressions.md)、[验收](../acceptance.md)、[ReAct 协议](../react-agent.md)、[远程 Job 协议](../engineering/agent-job-protocol.md)

- 状态：已采纳
- 日期：2026-09-05
- 版本：0.0.22
- 上游依据：[PRD 056](../prd/056-video-speech-and-share-readability.md)
- 后续替代：[ADR 0121](0121-live-dictation-preview.md) 未确认片段进入输入框预览；确认后追加草稿的边界不变
- 部分替代：[ADR 0000](0000-origin-through-0.0.11.md)、[ADR 0117](0117-workout-share-editorial-poster.md)

## 背景

完整视频被降级成抽帧、媒体页未主动播放、分享明细被元数据拆散，旧听写基线还会覆盖用户编辑。维护者要求统一修复这些真实输入与呈现问题。

## 决策

视频请求不再有抽帧降级：本地未知能力允许尝试完整 video_url，明确不支持时报错；远程遵守部署显式能力开关并在不支持时阻断。重试保留同一完整视频。可转码压缩但不裁剪时长，准备失败保留原件。历史明确引用同样不能抽帧。

播放器实例由当前媒体页面持有，配置 playback 音频会话后自动播放；页面选择及 Scene 状态决定播放权，生命周期结束停止并释放，不在 View 初始化时创建播放器。

iOS 26 优先 SpeechAnalyzer + SpeechTranscriber 的本地最终片段结果，使用系统资源管理。旧系统保留要求本地识别的 SFSpeechRecognizer。输入框是唯一已提交文本来源，识别服务只持有当前尚未确认片段和识别生命周期信息；确认回调直接追加到当前草稿，不保存草稿基线或历史段数组。自然语言标点优先系统输出，停顿补标点不能改写已有草稿。

分享独立生成同值组投影：重量、次数/时长、左右事实相同的组按首次出现合并，间歇、录像和组类型不参与，只用于分享，编辑投影仍保留有序组及其证据。动作卡内使用紧凑合并项卡。

## 未选择的方案

不支持完整视频的模型不再获得替代帧分析，避免覆盖不完整却看似成功。最终语音片段比不稳定 partial 略迟出现，但避免识别回退覆盖用户编辑；不承诺未经真机测量的准确率提升。分享不表示组的执行顺序，原始记录仍可审查。

## 结果

完整视频与草稿事实边界明确；不新增持久字段或远程语音。旧模型可能无法完成视频请求，设备模型首次下载需要网络。

## 验证

通过完整请求、重试、草稿编辑和生命周期回归，make check 与 make verify；真机本地中文准确率单独验收。

## 参考

- [Apple WWDC25：SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
