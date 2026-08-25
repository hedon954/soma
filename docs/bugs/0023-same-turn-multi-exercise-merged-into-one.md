# BUG 0023：同一条消息的多个动作被合并成一条训练记录

- 状态：已修复，待真机复验
- 发现日期：2026-08-18
- 影响范围：聊天写入训练/饮食记录、原位审查卡、教练 Event Cards
- 上游依据：
  - [ADR 0014](../archive/0.0.1/adr/0014-agent-turn-ordered-event-cards.md)
  - [ADR 0018](../archive/0.0.1/adr/0018-provenance-aware-record-merge.md)
  - [ADR 0064](../archive/0.0.5/adr/0064-deterministic-quick-write-and-latest-inline-review.md)
- 下游落地：
  - [ADR 0077](../archive/0.0.7/adr/0077-same-turn-identity-merge-and-additive-inline-review.md)
  - [ADR 0078](../archive/0.0.7/adr/0078-batch-create-exercise-and-workout.md)
  - [ADR 0079](../archive/0.0.7/adr/0079-create-inserts-update-by-id.md)

## 症状

用户在一条消息里列出多个动作（例如硬拉、引体向上、深蹲）。Agent 会为每个动作调用
`create_workout` / `record_workout`，但 SwiftData 里只留下一条训练记录。聊天原位卡和
「训练记录」列表都只显示最后一次写入的动作名，组次重量却常常来自第一个动作。

同一回复里的 Skill/Tool Event Cards 被全部隐藏，只剩结果卡和最终文字。原位卡点
「保存」没有可见确认。

## 根因

这是本地合并规则的工程缺陷，不是模型漏调用工具。

1. `RecordMergePolicy.sameTurnCandidate` 把同一 `sourceTurnID` 的**任意**训练记录当成同一
   现实事件。ADR 0018 的「同一 Turn 永远更新原记录」是为纠错/补图准备的，实现没有再核
   对动作身份。第二次及以后的写入全部 `mergeWorkout` 进第一条。
2. 非纠错合并保留先写入的组次，`ConversationRecorder` 却用后一次的动作名覆盖
   `exercise`，于是出现「抗旋 + 硬拉 4×5×60kg」这种错配。
3. `AgentTurnTranscript` 在存在 `record_refs` 时过滤掉 Skill/Tool 卡，把原位审查卡当成
   Event 流的替代品，违反 ADR 0014。
4. 原位「保存」直接 `modelContext.save()`，按钮状态不变。

## 修复

- create / record 不再按同一 Turn、身份或纠错词合并。训练、饮食、身体每次创建都新增；
  纠正和补图只走更新工具。
- 原位审查卡叠加在 Event Cards 之上，不再过滤 Skill/Tool。
- 保存成功后按钮变为「已保存」，并给出成功触觉。
- 已经被错误合并的历史记录不自动拆分：结构化组次无法从一条错配记录可靠还原，用户可在
  修复后重新发送或在记录页补写。

## 回归门禁

- 自动化测试：同一 Turn 两个不同动作产生两条 `WorkoutEntry` 且重量不串；同一 Turn 重复
  create 训练/饮食/身体仍保持独立；有 `record_refs` 时 Tool Event 仍进入可见 Item。
- 手工验收：用虚构多动作文本发送一次，聊天出现多张原位卡和完整 Event 流；进展「训练
  记录」按动作条数展示；点保存后按钮短暂显示「已保存」。

## 验证

- `RecordMutationTests.testSameTurnDifferentExercisesStayIndependentRecords`
- `RecordMutationTests.testSameTurnRepeatedCreatesStayIndependentRecords`
- `AgentChatPresentationTests.testVisibleItemsKeepToolEventsWhenRecordReferencesExist`
- 夹具只使用虚构动作名和重量，不含真实健康数据。
