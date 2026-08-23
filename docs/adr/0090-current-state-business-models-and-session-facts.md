# ADR 0090：业务模型只保留当前状态，历史由事件事实承担

- 状态：已采纳
- 日期：2026-08-23
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0029](0029-versioned-training-plans-and-session-facts.md) 中计划编辑创建模板版本的决策；Session 处方快照和计划/实际分层继续有效
  - [ADR 0036](0036-gui-training-program-authoring.md) 中 GUI 与 Agent 共用不可变模板版本的存储方式；共用 Store 与验证继续有效
  - [ADR 0073](0073-independent-set-prescriptions-efforts-and-guided-finalization.md) 中版本化模板关系和热量算法版本字段；独立组、Effort、执行快照与转换 revision 继续有效
- 上游依据：[PRD 040](../prd/040-current-state-business-data-with-session-facts.md)
- 下游落地：
  - [训练领域模型与运行时协议](../engineering/training-domain-model.md)
  - [数据库结构与 ER 图](../engineering/database-schema.md)

## 背景

计划版本链、版本差异、动作内容修订数组和热量算法版本没有形成有价值的用户操作，却增加了模型、
Tool、备份和 UI 的复杂度。真正需要不可变的是一次已经开始的训练事实，而不是每次业务对象编辑。

## 决策

1. `TrainingProgram` 直接拥有当前 `TemplateExercise`、`scheduleHint` 与逐组处方。
2. GUI 和 `update_program` 直接替换当前处方。计划不保存版本号、版本来源、版本差异或恢复链。
3. `WorkoutSession.prescriptionSnapshotData` 与 `ExercisePerformance.prescriptionSnapshotData` 是执行时
   不可变事实；它们不构成可浏览的计划版本历史。
4. `ExerciseDefinition` 直接保存当前说明、肌群和动作模式；内容生成或手工编辑覆盖当前内容。
5. `WorkoutEntry` 保存热量结果、MET、使用时长和是否估算，不保存算法版本字段。
6. 旧库迁移复用原当前计划对应的处方并删除非当前版本节点。旧列只通过 SwiftData
   `originalName` 作为一次性无损映射，不进入业务 API、UI、文档结构或新写入。
7. `create_program_version` 删除，统一为 `update_program(program_id, program_name?, schedule_hint?,
   template_exercises)`。
8. `transitionRevision` 是状态机 compare-and-set 令牌；数据库 migration、归档格式、远程协议和
   Tool Schema 版本是技术兼容边界。它们继续存在，但不是业务版本追踪。

## 未采用方案

- 隐藏版本 UI、保留版本模型：仍会让 Store、备份与迁移承担无用复杂度。
- 只保留最近若干版本：仍没有明确恢复价值，也不能替代 Session 快照。
- 计划原地更新且 Session 只引用计划：会让历史训练被后续编辑改写。
- 删除所有带 version/revision 的技术字段：会破坏迁移、协议兼容和并发幂等。

## 结果

- 用户只面对当前计划，参数编辑路径直接且唯一。
- 已开始训练仍可准确回看当时处方，计划编辑不会改写执行事实。
- 模型、Tool、归档和文档减少一整套版本链与差异逻辑。
- 迁移必须验证旧库当前计划保存正确，不能把非当前草稿误并入当前计划。

## 验证

- 当前计划更新后只有一组当前处方；开始前后的 Session 快照分别保持正确。
- 动作内容第二次保存直接成为当前内容，没有修订数组或恢复入口。
- 热量投影不含算法版本字段，现有确定性数值测试继续通过。
- App/Server 全仓搜索只允许技术 schema/protocol/format/migration version 与
  `transitionRevision`，以及 SwiftData 旧列 `originalName`。
- `make check`、`make verify` 与 Server 测试通过。
