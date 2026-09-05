# Apple 本地中文听写方案调研

- 日期：2026-09-05
- 状态：已转化，准确率待真机对比
- 下游落地：[PRD 056](../prd/056-video-speech-and-share-readability.md)、[ADR 0119](../adr/0119-full-video-and-append-only-dictation.md)

## 官方证据

Apple 在 WWDC25 发布 SpeechAnalyzer 与 SpeechTranscriber，面向设备端转写、长音频与对话场景。新模型通过系统 AssetInventory 下载和管理，转写在设备上执行。SpeechTranscriber 的设备、语言支持需要运行时查询，不能仅凭 iOS 26 判断可用。

- [WWDC25：Bring advanced speech-to-text to your app with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)
- [SpeechTranscriber API](https://developer.apple.com/documentation/speech/speechtranscriber)
- [Apple 官方实现示例](https://developer.apple.com/documentation/speech/bringing-advanced-speech-to-text-capabilities-to-your-app)

## Soma 选择

iOS 26 优先新模型，检查中文 locale 与硬件可用性；首次缺少资源时由系统下载，失败可恢复。旧系统或不支持的新设备组合继续使用 SFSpeechRecognizer，并强制 requiresOnDeviceRecognition，不退回云端。音频按模块支持格式转换，停止时排空转换器与最终结果。SpeechDetector 按实际静音区间请求确认，不靠重复的 partial 文本推测用户是否停顿。

最终片段追加到编辑器当前内容，partial 仅保留在当前识别生命周期中；不缓存输入前草稿或累计历史句子。系统标点优先，片段间静音补充缺失标点，用户已有文本不被重写。

## 证据边界与手工验收

新 API 的适用场景构成迁移依据，不构成 Soma 中文准确率实测。模拟器已验证音频转换时长、追加和取消边界；须在支持设备完成本地中文短句、连续长句、器械名称、停顿、手工修改后继续、停止立即发送的人工对比。首次下载后可断网验证本地转写。不得保存真实用户录音作为测试夹具。
