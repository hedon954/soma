# ADR 0085：原位卡跟随产生它的那一步渲染

- 状态：已采纳
- 日期：2026-08-20
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0077](0077-same-turn-identity-merge-and-additive-inline-review.md) 中「原位卡渲染在过程与文字之后」的位置约定；原位卡与 Event Cards 共存、按 `record_refs` 逐条投影、保存必须可见确认继续有效
- 后续替代：暂无
- 后续修订：暂无
- 修订自：
  - [ADR 0014](../../0.0.1/adr/0014-agent-turn-ordered-event-cards.md) 的有序 Event Cards：原位卡加入同一条顺序，而不是挂在末尾
- 上游依据：[PRD 033](../prd/033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md)

## 背景

一条回复常常是「一句识别说明 → 写入 → 一段教练评价」。此前所有原位卡统一堆在整条回复的末尾，
用户读到评价文字时，被评价的那张卡还在下面没出现，卡片看起来像附件而不是对话的一部分。

Turn Item 本身已经按真实时序持久化，位置信息一直存在，只是投影时被丢掉了。

## 决策

1. 原位卡按 `record_refs` 插在产生它的那一步之后：单条 Tool 卡之后，或该 Tool 所属的可展开过程
   摘要之后。写入前后的文字保持原有顺序，于是聊天呈现「文字 → 卡片 → 文字」的节奏。
2. 同一条记录在一个 Turn 内被多次引用（先 create 再 update）时只渲染一张卡，按首次出现的位置。
3. 被折叠或过滤掉的 Item 仍可能带引用，这类卡兜底渲染在末尾，保证卡片不会凭空消失。
4. 卡片身份是 `record:<record_type>:<record_id>`，与 Item 身份互不冲突，流式期间插入不会复用
   其它卡片的 `@State`。

## 未选择的方案

- 继续把卡片堆在末尾：文字与卡片脱节，多条记录时更明显。
- 让模型在文字里复述卡片内容来补上下文：重复数据，且文字与本机记录可能不一致。
- 把卡片塞进过程摘要内部：折叠后记录会跟着一起消失，违反可审查边界。

## 结果

### 正向影响

- 教练说明与对应记录相邻，用户不用在末尾反查是哪一条。
- 一次写入多条记录时，卡片仍按写入顺序排列。

### 成本与限制

- 模型不在写入前说话时，顺序退化为「过程卡 → 原位卡 → 评价文字」，节奏依赖提示词引导。
- 兜底路径仍会把无法归位的卡片放在末尾。

## 验证

- `AgentChatPresentationTests` 覆盖卡片跟随产生它的步骤、重复引用只出一张卡、批量写入的顺序。
- `make check`、`make verify`。

## 参考

- `Soma/Services/AgentChatPresentation.swift`
- `Soma/Views/AgentTurnTranscript.swift`
- `Soma/Views/ChatRecordEditorCards.swift`
