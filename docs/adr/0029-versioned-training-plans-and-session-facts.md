# ADR 0029：计划版本、执行快照与逐组事实分层

- 状态：已采纳
- 日期：2026-07-31
- 维护者：Soma maintainers
- 部分替代：无
- 后续替代：暂无
- 上游依据：[动作库、训练计划、带练与视频复盘调研](../research/2026-07-31-exercise-library-plans-guided-training.md)
- 下游落地：[训练领域模型与运行时协议](../engineering/training-domain-model.md)
- 关联：[PRD 010](../prd/010-exercise-library-plans-guided-training.md)

## 背景

当前 `WorkoutEntry` 用一条聚合的组、次、重量表达训练。计划、实际执行和 AI 建议如果继续
共用同一模型，会把“准备做什么”误算成“已经完成什么”；计划编辑还可能重写历史。

旧记录没有逐组证据，迁移时不能将 `4 × 8` 虚构成四条完全相同的 Set。

## 决策

1. 训练领域分为三层：
   - `TrainingProgram`：周期安排；
   - `WorkoutTemplate`：可复用的一次训练处方及版本；
   - `WorkoutSession`：一次实际执行事实。
2. `TemplateExercise` 引用稳定动作 ID，保存目标组、次、重量、间歇和
   `firstSetIsWarmup`。
3. 计划编辑产生新版本。用户开始训练时把模板和动作处方完整快照到 Session。
4. 已开始 Session 只读取快照，不随模板刷新、Agent 建议或外部导入改变。
5. `ExercisePerformance` 表示 Session 中一个动作，`WorkoutSet` 表示逐组计划值和实际值。
6. 计划字段、实际字段和 AI Recommendation 使用不同存储位置；统计只读取实际完成字段。
7. 旧 `WorkoutEntry` 增加可空 `exerciseID` 并继续作为聚合历史。没有逐组证据时不创建 Set。
8. 聚合统计同时支持旧记录与新完成 Set，并通过来源 ID 防止同一 Session 被计两次。
9. 删除计划可删除未执行模板节点，但不得级联删除已开始或已完成 Session。
10. 推荐快照保存输入指纹、依据摘要和生成时间；依据变化后标记过期，不静默改写。

## 未选择的方案

- 计划和实际值共用 `WorkoutEntry`：会污染完成统计并丢失偏差。
- 每次打开计划都原地刷新：用户开始后的内容可能变化，历史不可解释。
- 将旧聚合记录机械拆组：制造用户从未提供的逐组事实。
- 完成后只保留计划名称：无法回答当时计划、实际完成和中途修改。

## 结果

### 正向影响

- 计划、执行和建议拥有清晰真值边界。
- 历史 Session 可以准确回看当时处方和实际偏差。
- 新逐组能力不会破坏旧训练历史和现有趋势。
- 热身组和录像目标组有稳定的数据依据。

### 成本与限制

- 统计、导出和备份需要同时兼容旧聚合记录与新逐组事实。
- 模板版本不可直接覆盖，会增加可管理的历史对象。
- 左右侧、递减组和自定义组只在用户实际提供时保存。

## 验证

- 模板编辑后，已开始 Session 快照保持不变。
- 计划值、建议值和跳过组不进入完成容量。
- 旧聚合记录迁移后数值与统计不改变，不生成虚构 Set。
- 同一完成 Session 不会同时通过 `WorkoutEntry` 和 `WorkoutSet` 重复统计。
- 删除计划不删除已完成 Session、媒体、分析或聊天 Turn。
- 新模型完成导出、加密备份、恢复、清除和双数据空间隔离测试。

## 参考

- [PRD 010](../prd/010-exercise-library-plans-guided-training.md)
- [ADR 0006](0006-data-truth-and-derived-metrics.md)
- [ADR 0021](0021-portable-export-encrypted-backup-and-erasure.md)
