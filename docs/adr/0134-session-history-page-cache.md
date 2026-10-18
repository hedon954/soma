# ADR 0134：会话历史按未缓存身份分页

- 状态：已采纳，已实现
- 日期：2026-09-12
- 版本：0.0.24
- 上游依据：[PRD 065](../prd/065-history-order-and-session-pages.md)
- 部分替代：[ADR 0000](0000-origin-through-0.0.11.md) 仅教练会话目录查询与缓存寿命；聊天消息分页保持不变
- 下游落地：[PRD 073](../prd/073-training-session-pages.md)、[ADR 0142](0142-training-session-pages.md)（训练页最近训练沿用未缓存身份分页）

## 背景

抽屉局部状态随关闭丢失；旧查询从 80 条开始扩大前缀，每次打开和加载更多都会重复读取。用户要求以 14 条分页并跨导航缓存。

## 决策

- `CoachView` 持有独立的 `ConversationSessionHistory`，位置在 Session 身份和条件抽屉之外。
- MainActor 每页以 `updatedAt` 倒序、UUID 次序查询最多 14 条，并把已缓存 ID 的排除谓词下推数据库；不得重查累计前缀或全表物化。
- 满 14 条允许继续加载；不足 14 条结束。整页恰好是尾页时下一次空查询关闭入口，不额外查询总数。
- 同容器保存通知只合并变化 Session，删除只移除对应缓存。无关模型保存及 Tab 切换不发起历史查询。
- 缓存绑定 ModelContext，切换上下文即重置；保存失败保留缓存，读取失败保留已加载页并提供重试。

## 结果

递增 offset 会在新建、删除或更新时间变化后重复/跳行；递增 fetchLimit 会反复物化历史前缀。
排除已加载身份可保留当前页且避免漏项，代价是内存和排除谓词随用户实际加载页数增长。
不改变持久 schema，不增加跨进程缓存或远程同步。

## 验证

`ConversationSessionHistoryTests`、`ProgressHistoryProjectionTests`、会话历史 UI 回归与 `make perf-check` / `make verify`。
