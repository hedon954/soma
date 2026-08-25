# ADR 0091：计划间歇归动作，执行事实仍归逻辑组

- 状态：已采纳
- 日期：2026-08-23
- 维护者：Soma maintainers
- 部分替代：[ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 中把计划换侧间歇与组后间歇作为每条 `TemplateSetPrescription` 新写入事实的决策；独立组、Effort、侧别归动作定义与实际休息证据继续有效
- 上游依据：[PRD 041](../prd/041-action-level-rest-and-compact-progress.md)
- 下游落地：
  - [训练领域模型与运行时协议](../../../engineering/training-domain-model.md)
  - [数据库结构与 ER 图](../../../engineering/database-schema.md)

## 背景

计划中的组间歇和换侧间歇通常描述整个动作的执行节奏。逐组重复编辑会扩大页面、干扰相同组压缩，
最后一组没有后续组间歇又会制造无意义差异。实际训练的休息仍是逐组发生的证据，两者不能混为一层。

## 决策

1. `TemplateExercise.targetRestSeconds` 保存计划动作的组间歇，新增
   `TemplateExercise.restBetweenSidesSeconds` 保存左右分开动作的换侧间歇。
2. `TemplateSetPrescription` 继续保存独立逻辑组的类型、目标、重量和备注。旧间歇列仅用于无损读取
   已有数据，不属于当前 GUI、Tool、备份值对象或新业务写入。
3. 旧逐组值只有在所有适用组完整且一致时才提升到动作级；冲突或缺失不猜测。提升后当前处方中的
   逐组计划间歇清空。
4. 开始 Session 时把动作级组间歇复制到所有非最终 `WorkoutSet`，最终组保持 `nil`；换侧间歇复制到
   `.both` 动作的每个逻辑组。
5. 已开始 Session 的快照、`WorkoutSet` 与 `WorkoutEffort.actualRestSeconds` 继续保存当次计划和实际
   证据；修改当前计划不回写历史。
6. Agent Tool 与 Server 校验在 exercise 层接收两类间歇。非 `.both` 动作不得保存换侧间歇。

## 未采用方案

- 每组继续显示两个间歇字段：重复且让最后一组产生无意义配置。
- 只在 UI 隐藏、底层继续逐组复制：会保留两个可漂移的事实来源。
- 删除训练事实中的逐组休息：会损失执行恢复、历史审查和真实时长证据。
- 用第一组或任意非空旧值提升：会把不完整数据冒充统一计划。

## 结果

- 计划动作只维护一套节奏，独立组仍能表达真正的目标差异。
- 旧模型列暂留兼容，数据库文档必须明确它们不再是当前计划写入边界。

## 验证

- 测试覆盖旧值一致/缺失、非左右动作校验、最后一组无组间歇、左右换侧执行、摘要与 Tool Schema。
- `make check`、Server 测试与 `make verify` 通过。
