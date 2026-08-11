# ADR 0060：带练动作终态物化为训练记录并组成计划执行

- 状态：已采纳
- 日期：2026-08-12
- 维护者：Soma maintainers
- 部分替代：[ADR 0029](0029-versioned-training-plans-and-session-facts.md) 中计划执行只由
  `ExercisePerformance/WorkoutSet` 表达、不进入 `WorkoutEntry` 的边界
- 后续替代：暂无
- 上游依据：
  - [PRD 026](../prd/026-guided-workout-record-projection-camera-failures-and-session-entry.md)
  - [BUG 0014](../bugs/0014-guided-performance-missing-workout-entry.md)
- 下游落地：[训练领域模型与运行时协议](../engineering/training-domain-model.md)

## 背景

`WorkoutSet` 是可靠的带练原始事实，但进展页、训练记录 CRUD、开放导出和部分建议链路以
`WorkoutEntry` 为统一业务记录。只保存 Session 图会让同一次真实动作在“计划执行”中存在、
却在“训练记录”中缺席。直接让两套统计同时累计又会制造双倍容量。

## 决策

1. `WorkoutSession/ExercisePerformance/WorkoutSet` 继续保存不可变计划快照、执行阶段、跳过、录像
   与逐组原始事实；`WorkoutEntry` 是动作终态的可审查业务投影。
2. Performance 的全部 Set 都进入 `.completed/.skipped` 后才投影。至少一个完成组时创建一条
   `WorkoutEntry`；全跳过不创建空记录。
3. 投影只复制完成组的实际次数与外部重量，保持顺序和 `nil`；不复制跳过组，不用计划值补空。
4. `WorkoutEntry` 增加可空 `sourceWorkoutSessionID` 与 `sourcePerformanceID`。应用层以
   `sourcePerformanceID` 保证一条 Performance 最多一条记录，并允许启动时幂等补投影。
5. 计划执行的动作数与容量优先聚合来源记录；跳过数、时长、录像和恢复状态仍读取 Session 图。
   没有投影的旧 Session 才回退到原始完成 Set，禁止同时累计两份事实。
6. 删除 Session 级联删除关联来源记录；删除计划模板不删除 Session 或训练记录。开放导出与
   加密备份保存两个来源 ID。
7. `WorkoutEntry` 可按既有 CRUD 编辑；原始 Session/Set 仍作为执行证据保留。计划执行的可审查
   动作容量读取当前来源记录，因此用户修正会反映在聚合结果中。
8. 用户单独删除投影记录时在来源 Performance 保存 `workoutProjectionSuppressed`；回填和完成路径
   尊重该标记，不重新创建已明确删除的记录，普通训练历史、趋势和最近容量也不回退显示该动作；
   计划执行仍保留原始证据。删除整个 Session 时直接删除记录与原始事实，无需保留抑制标记。

## 未选择的方案

- 只在 UI 合并 Session 和训练记录：无法让记录进入统一 CRUD、导出和 Agent 查询边界。
- 用名称和日期推测关联：同日同动作多次训练会误合并，改名也会断链。
- 同时累计 `WorkoutEntry` 与原始 Set：会把同一组容量计算两次。
- 为跳过动作创建零组记录：把“没有执行”伪装成训练事实。

## 结果

### 正向影响

- 带练动作与聊天/导入训练统一出现在训练记录中，并保持可编辑、可删除和可导出。
- Session 仍能表达计划执行、跳过、恢复和录像，不牺牲原始证据。
- 来源 ID 让恢复、回填、删除和统计去重都可确定执行。

### 成本与限制

- SwiftData 增加两个可空来源字段与一个投影抑制字段，备份与导出格式需要同步升级。
- 旧 Session 需要一次本机补投影；缺失完成组的历史不会生成伪记录。
- 记录被编辑后可能与原始 Set 不同，这是可审查投影与原始执行证据的有意分层。

## 验证

- 单元测试已覆盖完成、完成后跳过、全跳过、重复回填、来源关联、用户删除抑制和 Session 级联删除。
- 趋势测试已证明同一 Performance 的投影记录与原始 Set 只累计一次，抑制后不会从原始 Set 回退。
- 备份往返已保留来源 ID 与抑制标记；新增字段可空或有默认值，旧快照缺字段仍可恢复。
- `make verify` 已通过；训练记录与计划执行的真实个人数据组合仍由维护者在真机验收。

## 参考

- [ADR 0023：训练记录保存有序逐组证据](0023-ordered-workout-set-evidence.md)
- [ADR 0039：带练录像、语音与复盘由确定性事件驱动](0039-event-driven-guided-recording-cues-and-review.md)
