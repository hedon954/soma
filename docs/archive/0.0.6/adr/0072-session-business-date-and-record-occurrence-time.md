# ADR 0072：Session 业务日与记录发生时间分离

- 状态：已采纳
- 日期：2026-08-15
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0055](../../0.0.4/adr/0055-hybrid-daily-conversation-sessions.md) 中 Session 只以 startedAt 表达日期的边界
  - [ADR 0063](../../0.0.5/adr/0063-step-resume-fixed-loop-time-and-deadline-hierarchy.md) 中业务写入统一使用 loopStartedAt 的边界
  - [ADR 0067](../../0.0.5/adr/0067-separate-business-time-and-active-loop-budget.md) 中 loopStartedAt 仍是唯一业务记录时间的边界
- 后续替代：暂无
- 上游依据：[PRD 030](../prd/030-agent-prompt-skill-context-and-tool-v3.md)

## 背景

`loopStartedAt` 能避免重试跨午夜漂移，却不能表达用户继续旧 Session 时希望记录其业务日，也会
把排队等待误当成事实发生时间。Tool 没有显式时间参数，用户无法修正历史训练、饮食或身体记录。

## 决策

1. `ConversationSession` 保存 `businessDate` 和 IANA 时区。创建时取设备自然日；旧 Session 由
   startedAt 与当时时区迁移。
2. 每个 Turn 在提交前解析明确的“今天/昨天/具体日期”，得到只对当前 Turn 生效的业务日；没有
   明确日期时使用 Session businessDate。只有日期芯片永久修改 Session。
3. Job 原子保存 `turnSentAt`、`effectiveBusinessDate` 与 `defaultOccurredAt`。默认发生时间把原始
   Turn 的本地时分秒放到生效业务日；同一 Job 的排队、恢复、自动和手动重试均复用。
4. 训练、饮食、身体 create/update Tool 接受可空 ISO-8601 `occurred_at`。省略使用 Job 默认值；
   update 只有用户明确纠正时才改变时间。
5. Tool 结果和记录保存最终发生时间与来源。无效格式、无依据未来时间或与用户表达冲突时返回
   可恢复结构化错误。
6. `loopStartedAt` 继续只负责固定 Loop 解释时间；活动执行预算继续由 ADR 0067 的独立字段管理。

## 未选择的方案

- 不使用 Tool 实际执行墙钟作默认值；它会因排队和跨天重试失真。
- 不让自然语言“今天”静默永久改写旧 Session 的默认业务日。

## 结果

### 正向影响

- 聊天日期、记录发生时间和 Agent 执行时间各自拥有明确事实源。

### 成本与限制

- Session、Job、记录 Tool、查询日期、导出和重试协议都需要同步升级。

## 验证

- 固定时区覆盖新 Session、旧 Session、今天单 Turn 覆盖、日期芯片、排队和跨午夜重试。

## 参考

- [PRD 030](../prd/030-agent-prompt-skill-context-and-tool-v3.md)
