# ADR 0101：记录真值与 Agent 身体资料上下文

- 状态：已采纳
- 日期：2026-08-26
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0000](0000-origin-through-0.0.11.md) 的总糖字段、参考体重回退和记录展示收口
  - [ADR 0100](0100-bounded-snapshots-continuous-stream-rendering-and-query-first-data-access.md) 的会话初始定位细则
- 后续替代：[ADR 0102](0102-source-workout-plan-execution-materialization.md)
- 上游依据：
  - [PRD 046](../prd/046-coach-records-and-goal-directed-progress.md)
  - [BUG 0039](../bugs/0039-meal-occurrence-and-duration-target-truth.md)
- 下游落地：[验收矩阵](../acceptance.md)

## 背景

模型曾能覆盖设备可确定的餐次，训练 Tool 丢失按时长动作的秒数，身体资料也没有完整进入 Agent；
同时低可信总糖和独立参考体重制造了无法审查的平行事实来源。

## 决策

1. `MealEntry`、`MealItem`、Agent Schema、查询结果、备份和开放导出不再定义总糖；图片识别不足以
   支撑该字段成为可审查事实。升糖速度继续只作为带依据的餐食组成定性评价。
2. `UserProfile` 不再保存参考体重。热量、界面和 Agent 只使用按时间定向读取的最新有效
   `BodyEntry.weight`；缺失即未知。
3. Agent 身体上下文包含昵称、性别、动态年龄、身高、最新体重及日期、目标和限制，保持有界单行，
   不拼接到 View。
4. 餐次先检查用户原文中的明确名称，否则按 `occurred_at` 本地时区推断；Tool 的 `meal_type` 不能
   单独覆盖。增加 `afternoonSnack`。
5. 训练逐组输入同时支持 `reps` 与 `duration_seconds`，每组二选一；动作定义的 `targetKind` 决定
   卡片和保存语义。
6. 消息反向分页只影响查询方向，不反转屏幕阅读顺序。短内容顶部对齐，长内容首次贴底；每条 AI
   回复的 Trace 入口按该消息绑定的 trace ID 定向查询。

## 数据兼容

当前应用仍只打开 `SomaDataSchema`。删除持久字段不伪造历史迁移对象；启动门禁按既有不兼容 schema
策略明确失败/重建。备份解码不再承诺恢复已删除字段，其他记录事实保持。

## 未选择的方案

- 不保留总糖为隐藏兼容字段；隐藏字段仍会继续进入备份、查询或未来 UI。
- 不让模型 `meal_type` 优先；可确定的本地时钟事实不应交给概率输出。
- 不保留 UserProfile 体重回退；两个可编辑体重来源无法定义时间真值。

## 结果

### 正向影响

- 餐次、训练目标单位和身体上下文都有单一可审查事实来源。

### 成本与限制

- 删除当前 SwiftData 字段是不兼容变更；旧备份中的字段不再恢复。

## 验证

`MealOccurrenceTimeTests`、`ConversationRecorderToolTests`、`ConversationContextProjectionTests`、
归档往返测试、静态数据库目录门禁与 `make verify`。

## 参考

- [数据库结构](../engineering/database-schema.md)
- [Agent Tool 目录](../engineering/agent-tool-catalog.md)
