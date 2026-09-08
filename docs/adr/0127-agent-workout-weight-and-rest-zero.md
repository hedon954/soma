# ADR 0127：Agent 训练重量与间歇未说明时写 0

- 状态：已采纳
- 日期：2026-09-08
- 维护者：Soma maintainers
- 部分替代：[ADR 0000](0000-origin-through-0.0.11.md) 仅训练 Tool 的外部重量与组间间歇；其他缺事实仍为 `nil`
- 上游依据：[PRD 059](../prd/059-coach-ids-progress-and-required-zeros.md)
- 后续替代：暂无
- 下游落地：[验收](../acceptance.md)

## 背景

模型常在回复里提到间歇或自重，却省略 Tool 字段，卡片显示“— kg / 间歇 — 秒”。把 0 当未知
又会把明确的零秒休息丢掉。

## 决策

`create_workout` / `update_workout` 的 `external_weight_kg` 与非最后逻辑组 `rest_seconds`
必须有数。用户未说明时写 0：0kg 是自重，0 秒是没有休息。最后一组仍不写组后间歇。设备在
模型省略时同样落 0，避免再试一轮。GUI 留空仍是 `nil`，界面继续显示“—”。

## 未选择的方案

继续省略并让模型自己 list；把 0 一律当成未知再回填。

## 结果

新写入的训练卡能区分自重与未记录、零秒休息与未记录。加权动作若被模型漏填重量，会被写成
自重，用户可在卡片里改。

## 验证

`WorkoutRestPropagation` 与 `ConversationRecorder` 省略字段测试；`make verify`。
