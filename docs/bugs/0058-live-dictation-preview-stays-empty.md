# BUG 0058：听写说话时不出字，点停才倒出缓存

- 状态：已修复，真机中文听写待复验
- 发现日期：2026-09-09
- 影响范围：教练输入区听写预览与输入框高度
- 上游依据：[ADR 0121](../archive/0.0.22/adr/0121-live-dictation-preview.md)
- 下游落地：[验收](../acceptance.md)

## 症状

说话时输入框一直是占位符。点停麦克风后，缓存的识别结果才一次性出现。听写中点输入框，
或换成听写态后，输入框会从一行变成两行。

## 根因

iOS 26 的 `SpeechTranscriber` 只用了 `volatileResults`，没有走 `progressiveTranscription`，
未确认片段往往要等 `finalize` 才出来，表现就是点停才出字。识别回调也可能不在主线程，
输入框看不到预览。听写态用无行数限制的 `Text` 画整句占位符，`TextField` 又开了纵向轴，
空内容一点就扩成两行。

## 修复

优先用 `DictationTranscriber` 的 `progressiveShortDictation`；没有听写模块时用
`SpeechTranscriber` 的 `timeIndexedProgressiveTranscription`。结果回到主线程再写预览。
输入框在尚未换行时保持一行。

## 回归门禁

- `SpeechInputSessionTests`：空草稿听写时 partial 立刻进入 `displayedSpeechDraft`，draft 仍为空。
- 真机：连续说短句应边说边出字；点输入框空内容保持一行。

## 验证

`make check`、`make verify`。真机中文听写由维护者复验，安装后不自动启动。
