# Bug 0002：视频抽帧失败会静默退化为无画面的请求

- 状态：已修复，待真机媒体验收
- 发现日期：2026-07-30
- 影响：用户附加视频后，Agent 可能表现得像已分析视频，实际请求没有任何视频画面
- 后续修订：[BUG 0012](0012-direct-video-and-first-delta-timeout.md) 修复直传仍重复抽帧与缺少首增量门禁
- 下游落地：[ADR 0057](../archive/0.0.4/adr/0057-direct-video-capability-and-observable-fallback.md)

## 症状

- 视频能够保存在聊天并正常回放，但 Agent 回复无法引用视频中的可见动作或场景。
- Trace 可以出现 `videoAttachmentCount > 0`、`imageCount == 0`，当前 UI 不把它视为媒体准备
  失败。

## 根因

1. 媒体选择器把相册视频复制到临时目录。
2. `ConversationProcessingService.prepareMedia` 再把视频保存到 App 沙盒，但抽帧仍使用选择器
   的临时 URL。
3. `VideoFrameExtractor.frames` 对时长读取和每张帧提取都使用 `try?`；任何失败最终只返回空数组。
4. `runAgent` 仍收到 `hasVideo == true`，但 `agentUserContent` 在图片数组为空时只构造文字消息。
5. 提示词告诉模型“包含视频”，模型却没有收到画面，失败没有阻止请求也没有形成可操作错误。

这条机制能证明静默退化路径存在，但不等于所有已观察到的视频失败都由同一种编解码或临时
文件问题触发。

相邻的媒体一致性问题是：首次发送图片时，沙盒会保存标准化 JPEG，但提供给模型的仍是选择器
原始 Data；重试才从沙盒读取标准化版本。当前“只发送压缩图片”的披露因此并不始终成立。

## 修复

- 增加模型媒体能力矩阵。百炼 Qwen 明确支持内联视频且稳定副本不超过 24MB 时优先使用直接视频输入；
  其他情况才进入关键帧路径。
- 视频先保存，再从 `MediaStore.url(at:)` 返回的稳定沙盒 URL 抽帧。
- 媒体准备返回逐附件成功/失败结果，不用空数组吞掉错误。
- 附有视频但既没有有效直接视频、实际帧数又为零时终止 Attempt，展示“视频未能解析，可重试”
  的恢复动作。
- 首次发送与重试都从同一标准化沙盒媒体准备远程输入。
- Trace 记录安全的抽帧阶段、帧数和错误类别，不记录路径、Base64 或真实媒体。

## 回归门禁

- 使用仓库生成的虚构短视频测试内联直传，并验证不支持或超限时稳定副本可抽出大于零的
  JPEG 帧。
- 注入不可读、零时长和不支持的视频，验证不会调用远程 Agent。
- 验证新图片首次发送和重试的远程 Data 指纹一致，且尺寸不超过标准化上限。
- 真机从相册和相机各选择一个虚构视频，确认 Trace 帧数、Agent 可见内容和失败恢复。

## 验证

- 已增加稳定沙盒 URL 抽帧、标准化图片复用、零帧失败、百炼直接视频和首响应前失败时的
  关键帧降级。
- 已通过静态门禁和模拟器构建；相册/相机真实编码组合仍需在真机完成手工验收。

## 关联

- [PRD 008](../archive/0.0.1/prd/008-coach-continuity-and-adaptive-models.md)
- [ADR 0012](../archive/0.0.1/adr/0012-ordered-mixed-media-collections.md)
- [ADR 0024](../archive/0.0.1/adr/0024-session-context-projection-and-compaction.md)
