# ADR 0031：Agent 使用持久 Job、语义 Event Log 与独立投影

- 状态：部分已替代
- 日期：2026-07-31
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0005](0005-trace-span-event-observability.md) 的进程内 Event 作为唯一事件来源
  - [ADR 0008](0008-app-scoped-conversation-processing.md) 的单一内存在途 Task
- 后续替代：
  - [ADR 0037](0037-backend-transparent-streaming-and-notification-wake.md) 分离体验 Event 与 Job 内部状态，并统一 Local/Remote 实时投影
  - [ADR 0048](../../0.0.3/adr/0048-loop-checkpoint-and-same-bubble-resume.md) 修订本地路径中断后从 step 检查点同气泡续跑
- 上游依据：
  - [持久 Agent Job、事件流与 Live Activities 调研](../../../research/2026-07-31-durable-agent-jobs-live-activities.md)
  - [BUG 0004](../../../bugs/0004-agent-background-stream-interruption.md)
- 下游落地：
  - [Agent Job 与远程执行协议](../../../engineering/agent-job-protocol.md)
  - [BUG 0024](../../../bugs/0024-streaming-cross-actor-swiftdata-crash.md)
- 关联：[PRD 011](../prd/011-durable-agent-jobs-remote-continuity.md)

## 背景

App 根层持有 `ConversationProcessingService` 只解决页面生命周期。用户消息、任务状态、
ReAct 内存和 UI 实时 revision 仍可能在进程挂起或终止时丢失。聊天、Trace、Live Activity
和通知也需要读取同一执行事实，不能各自解释网络回调。

## 决策

1. 一次用户发送先在同一持久化事务中创建 Turn、媒体引用、上下文快照和
   `AgentJob(state: queued)`；成功后输入区才清空。
2. `AgentJobRunner` 位于 App 生命周期，原子领取 Job 并创建 Attempt。
3. 第一版保持全局串行；同一 Session 始终 FIFO。
4. `AgentEvent` 保存有业务意义的 Job、Attempt、model、skill、tool、text、output 和 error
   状态，`jobID + sequence` 唯一且单调递增。
5. token delta 和原始 SSE 包不逐条落库。实时增量走进程内总线，按文本片段或语义边界合并。
6. Chat、Trace、Live Activity 和通知是同一 Event Log 的独立投影，各自维护 cursor 或投影
   版本；任何 UI 读取都不删除事件。
7. Tool mutation、Receipt、Event 和 Job 状态使用明确事务边界，避免成功副作用没有对应事实。
8. 本地执行开始时取得有限 `BackgroundExecutionLease`；到期前保存
   `waitingForForeground`、结束当前 Attempt 并取消网络。
9. 恢复创建新 Attempt，不续接半条 SSE 或半次 Tool Call；已成功 mutation 继续用 Receipt
   幂等返回。
10. 任务终态且所有必要投影完成后可以压缩文本增量，但必须保留 Tool、错误和最终输出语义。

## 未选择的方案

- UI 消费事件后删除：会破坏其他投影、重放和诊断。
- 每个 token 一条 SwiftData 记录：写放大严重且没有业务价值。
- 只持久化最终回答：无法恢复 Tool 状态和解释部分成功。
- 尝试续接断开的 SSE：无法可靠恢复半个 `tool_call` 和供应商连接状态。
- 同时并发多个本地 Agent：增加本地 Tool、上下文和数据空间竞态。

## 结果

### 正向影响

- UI 不再拥有任务生命周期。
- 发送、恢复、重放和多消费者投影有统一事实。
- App 被终止后可以识别 queued、waiting 和 interrupted Job。
- Live Activity 和通知不需要解析聊天 View 状态。

### 成本与限制

- 本地持久 Job 仍不能绕过 iOS 挂起，只能可靠暂停和恢复。
- Event 压缩、投影 cursor 和迁移需要确定性测试。
- 现有 `CoachMessage` 编码 Event Cards 需要渐进迁移为投影，而不是一次性丢弃。

## 验证

- 事务提交前失败不清空草稿；提交后立即终止 App，Turn 与 Job 仍可恢复。
- 原子领取保证一个 Job 同时只有一个本地 Runner。
- Event sequence 唯一有序，页面重建后的卡片顺序一致。
- 后台租约所有结束路径只释放一次；到期不永久停留在 running。
- 已写入 Tool 后恢复不会生成第二条业务记录。
- Event 压缩前后 Chat 与 Trace 投影语义相同。

## 参考

- [PRD 011](../prd/011-durable-agent-jobs-remote-continuity.md)
- [ADR 0014](0014-agent-turn-ordered-event-cards.md)
- [ADR 0016](0016-conversation-turn-attempt-and-footprint-projection.md)
- [Apple Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)
