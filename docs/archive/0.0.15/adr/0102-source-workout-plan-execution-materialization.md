# ADR 0102：原始训练生成计划时物化已完成执行

- 状态：已采纳
- 日期：2026-08-26
- 维护者：Soma maintainers
- 修订自：[ADR 0101](0101-record-truth-and-agent-profile-context.md)
- 部分替代：[ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 的计划创建与 Session 事实边界
- 后续替代：[ADR 0103](0103-goal-directed-progress-energy-and-hypertrophy.md)
- 上游依据：
  - [PRD 046](../prd/046-coach-records-and-goal-directed-progress.md)
  - [BUG 0038](../../../bugs/0038-source-workouts-missing-plan-execution.md)
- 下游落地：[验收矩阵](../../../acceptance.md)

## 背景

计划模板和训练执行是两类实体。只从当日记录生成模板会丢失“用户已经执行过一次该计划”的历史；
直接复制训练记录又会重复统计。

## 决策

`create_program` 增加 `source_workout_record_ids`。仅当用户要求基于当日训练总结计划时传入；设备验证
ID 唯一、均存在、属于同一日、未归入其他 Session，且动作全部包含在新计划中。

创建或复用内容相同计划后，设备建立 `.completed` `WorkoutSession`、Performance、Set 与 Effort，
按原始记录时间和逐组证据排序。原 `WorkoutEntry` 通过关系连接执行，不复制第二条业务记录。删除此
Session 只解除原始记录关系；只有 `guided-performance:` 投影键标识的带练派生记录才随 Session 删除。

## 未选择的方案

- 不复制一份新的 `WorkoutEntry`；这会重复容量、热量和动作历史。
- 不只在计划上保存来源 ID；缺少 Session/Set/Effort 就无法复用执行统计和详情。

## 结果

### 正向影响

用户既得到可继续执行的计划，也保留已完成一次该计划的历史。

### 成本与限制

来源记录必须同日、未归入其他 Session 且动作全部进入计划；否则创建确定性失败。

## 验证

`AgentPlanToolV3Tests` 固定组装、关系、
终态、逐组证据和删除后原始记录仍存在；重复归入或跨日输入确定性失败。

## 参考

- [训练领域模型](../../../engineering/training-domain-model.md)
- [BUG 0038](../../../bugs/0038-source-workouts-missing-plan-execution.md)
