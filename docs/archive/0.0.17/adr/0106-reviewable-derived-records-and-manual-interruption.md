# ADR 0106：可审查派生记录与人工中断屏障

- 状态：已采纳
- 日期：2026-08-27
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 的饮食派生、训练记录目标单位投影、人工恢复和设置/消息元信息细则
- 后续替代：[ADR 0108](../../0.0.18/adr/0108-contextual-progress-disclosure-and-reviewable-meal-order.md) 的输入区暂停、元信息视觉间距与饮食顺序字段
- 上游依据：
  - [PRD 048](../prd/048-reviewable-record-derivation-and-user-controlled-interruption.md)
  - [BUG 0027](../../../bugs/0027-meal-aggregate-overrides-item-facts.md)
  - [BUG 0029](../../../bugs/0029-visible-failure-keeps-retrying-and-stale-error.md)
  - [BUG 0031](../../../bugs/0031-feedback-sheet-transition-jank.md)
  - [BUG 0039](../../../bugs/0039-meal-occurrence-and-duration-target-truth.md)
- 下游落地：[验收矩阵](../../../acceptance.md)

## 背景

单一事实来源不只约束持久层，还必须约束编辑投影。此前严格营养总计在任一菜品缺字段时整体为空，
使 UI 丢掉已有小计；旧训练 evidence 的 `targetKind` 也能覆盖动作定义。Agent 失败已有人工屏障，但
用户主动停止仍没有相同的持久状态与恢复语义。

## 决策

1. `MealNutritionTotals` 同时计算“完整精确总计”和“已知小计 + 完整性”。持久聚合只写完整精确值；
   审查 UI 在不完整时显示带 `≥` 的已知小计，字段完全未知时显示破折号。
2. `MealItemDraft` 只在份数字段提交相同单位的正数变化时缩放已有营养值。缩放以当前草稿为基线，
   热量取整数、宏量营养保留有限小数；空字段保持空。其他字段使用普通 Binding，互不级联。
3. `ExerciseDefinition.targetKind` 与 `laterality` 是训练编辑投影的配置源。`WorkoutRecordDraft` 接收
   不持久化的 profile snapshot；旧 evidence 只有另一目标槽位时，把同一个已记录数值解释到动作定义
   的目标槽位并清空错误槽位。重量、间歇、顺序、录像和逻辑组身份不变。
4. `ConversationProcessingService` 在领取 Job 后记录当前 Job ID。用户中断时，先把取消事件同步投影到
   同一回复，再把 Job 转为 `waitingForUser`、暂存后续 Job，最后取消底层本地 Task 或远程 Job。
   Task 的取消错误不得覆盖已经可见的人工中断投影。
5. 中断后的重试不增加平行入口：继续使用既有 `ConversationTurnProjection.canRetry` 与手动恢复路径，
   复用同一气泡、清理旧失败项并从已保存检查点继续。
6. 设置根页面删除无语义的“更多”标题并直接平铺低频入口；出生日期使用可清空的可选日期编辑器。
   消息元信息用等宽触达槽与固定可见间隔实现时间、Trace、反馈等距，处理中行复用相同左边界。

## 未选择的方案

- 不把缺失菜品营养当作零后显示精确总计；这会把未知伪装为事实。
- 不在修改任一营养字段时反推份数或其他宏量；用户显式纠错优先。
- 不把目标单位和侧别重新持久化为记录级配置；这会继续产生动作定义之外的第二事实源。
- 不把主动停止映射为成功或直接删除 Job；用户需要审查已经完成的步骤并可恢复。
- 不在网络恢复、回到前台或设置变化时自动重启被用户中断的 Turn。

## 结果

### 正向影响

- 饮食、训练与 Agent 恢复都只有一个可解释的配置源；已有事实不会因字段不完整而在审查界面消失。
- 用户可停止耗时处理并决定是否恢复，后续消息不会越过人工屏障。

### 成本与限制

- 旧训练记录第一次打开时才按动作定义纠正草稿语义；未保存前不会批量重写历史数据。
- 远程取消是尽力而为，最终仍以本地持久 Job/Event 状态与幂等副作用为准。

## 数据兼容

本决策不改变 SwiftData schema 或备份格式。训练的纠正发生在草稿投影和下一次用户保存时；未打开的
历史记录不做批量重写。中断复用现有 Job state、Event 与 response message 字段。

## 验证

`MealNutritionTotalsTests`、`WorkoutRecordEditorProjectionTests`、`LLMOutageStagingTests`、
`SomaUILayoutContractTests`、`make check`、`make verify` 与双主题模拟器检查。
