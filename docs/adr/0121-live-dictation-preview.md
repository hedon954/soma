# ADR 0121：听写未确认片段只作输入框预览

- 状态：已采纳
- 日期：2026-09-07
- 维护者：Soma maintainers
- 上游依据：[PRD 057](../prd/057-coach-focus-progress-rings-and-library-clarity.md)
- 部分替代：[ADR 0119](0119-full-video-and-append-only-dictation.md) 的「最终片段才出现在输入框」呈现；追加-only 草稿边界不变
- 后续替代：暂无

## 背景

业内听写（系统听写、微信、百度）都是边说边出字。Soma 为避开 BUG 0048 把 partial 留在服务里，
用户必须停顿约 1 秒才看到文字，听起来像识别坏了。

## 决策

- 输入框展示 `草稿 + 当前未确认片段`。未确认片段可以随识别回退改写。
- 草稿仍是唯一已提交文本。partial 不得直接写入 `draft`。
- 用户在听写中改字：以改后的全文作为新草稿，丢弃当前未确认片段，避免回退覆盖编辑。
- 片段变 final、停止、发送或切走教练时，仍按 ADR 0119 把未确认片段追加到当前草稿；过期回调忽略。
- 不恢复草稿基线，不缓存历史转写。继续本地识别，不上传音频。

## 未选择的方案

- 把 TextField 直接绑到 live transcript：BUG 0048 会复发。
- 在输入框下方另开一行预览：用户仍觉得「字没有进去」。
- 云端流式识别：超出本地优先边界。

## 结果

### 正向影响

- 边说边看到字，同时保住「确认才落草稿」。

### 成本与限制

- 未确认字会闪烁回退，这是识别特性，不把它写成已提交事实。

## 验证

`SpeechInputSessionTests` 继续断言 partial 不改 `draft`；新增预览等于草稿加 pending、手改后丢弃
pending。真机中文听写单独验收。

## 参考

- [ADR 0119](0119-full-video-and-append-only-dictation.md)
- [BUG 0048](../bugs/0048-speech-segment-overwrites-committed-text.md)
