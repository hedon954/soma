# BUG 0038：当日训练生成计划后缺少计划执行历史

- 状态：已修复
- 发现日期：2026-08-26
- 影响范围：基于当日训练生成计划的执行历史与统计
- 上游依据：维护者复现反馈
- 下游落地：
  - [PRD 046](../prd/046-coach-records-and-goal-directed-progress.md)
  - [ADR 0102](../adr/0102-source-workout-plan-execution-materialization.md)

## 症状

用户先记录当日多个动作，再让教练总结为计划时，`create_program` 只创建模板，没有把这些已经完成
的动作归入一次 `WorkoutSession`。计划列表存在，但训练历史少一次计划执行。

## 根因

Tool Schema 没有携带来源训练 ID，计划创建服务也没有“从既有事实组装完成 Session”的路径。

## 修复

`create_program.source_workout_record_ids` 明确绑定来源。设备验证同日、未归属、动作在计划中后，
物化完成 Session/Performance/Set/Effort，并把原始 `WorkoutEntry` 作为证据关系连接。删除 Session
解除原始事实关系，不删除原始记录。

## 回归门禁

- 自动化测试：`AgentPlanToolV3Tests.testCreateProgramMaterializesSourceWorkoutsAsCompletedSession` 固定
  创建、证据顺序、终态、关系和删除语义。
- 手工验收：用虚构当日动作要求生成计划，检查计划历史恰有一次已完成执行。
- 仍无法自动化的风险：真机界面跳转与最终文案需交互验收。

## 验证

`make test`、`make check`；数据库文档门禁固定投影键与原始 entry key 的区别。
