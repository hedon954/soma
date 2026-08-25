# ADR 0063：step 续跑复用同一气泡、固定 Loop 时间并采用分层截止时间

- 状态：部分已替代
- 日期：2026-08-13
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0048](../../0.0.3/adr/0048-loop-checkpoint-and-same-bubble-resume.md) 中只有完成 step 后才能同气泡恢复、手动重试新建 Attempt 的边界
  - [ADR 0056](../../0.0.4/adr/0056-trusted-selective-multimodal-context.md) 中每次模型请求刷新 Attempt 时间并持久化格式化日期字段的边界
  - [ADR 0058](../../0.0.4/adr/0058-first-delta-deadline-and-bounded-retry.md) 中每个模型 step 使用 8/10/20 秒首增量、idle 与单步总时限的边界
- 上游依据：[PRD 027](../prd/027-reliable-efficient-react-and-in-context-review.md)
- 后续替代：
  - [ADR 0067](0067-separate-business-time-and-active-loop-budget.md) 修订整轮预算的计时来源与用户显式重试窗口
  - [ADR 0072](../../0.0.6/adr/0072-session-business-date-and-record-occurrence-time.md) 将记录发生时间从 Loop 时间拆分为稳定的 Turn 业务时间

## 背景

重跑完整 ReAct Loop 会重复 token、Tool 读取和潜在副作用；复制失败气泡使 UI 充满历史错误。
同时，每个请求刷新本地日期会让跨午夜或很晚重试的同一 Loop 产生互相冲突的“今天”。

## 决策

1. Job 首次 claim 时冻结 `loopStartedAt`；检查点把每个 LLM invoke 和每个 Tool Call 分别计为
   step，并保存原生 `assistant.tool_calls`、逐条 `role=tool` 结果、可展示段落、已暴露工具组和
   幂等信息。批量 tool calls 中途失败时，已完成 Tool 不会重新执行。
2. 所有可重试失败复用 `responseMessageID`；重试前移除 error/running Event 与半截失败文本，恢复
   已完成段落，从首个未完成 step 继续。
3. `TrustedTurnContext` 只持久化 `turnSentAt`、`loopStartedAt`、IANA timezone identifier；日期、
   weekday 与 offset 在 prompt 或 UI format 时生成。
   同一 Loop 创建或更新业务记录时也统一使用 `loopStartedAt`，不再使用消息发送时间或重试墙钟。
4. 第一次模型处理的首增量门禁为文字 20 秒、图片 40 秒、视频 60 秒；后续 step 不设单 step
   截止时间，也不做传输级自动重试。
5. 整个 Loop 的墙钟预算分别为 3/5/10 分钟，从 `loopStartedAt` 计算；恢复和手动重试都不重置。
   此项已由 [ADR 0067](0067-separate-business-time-and-active-loop-budget.md) 替代；业务时间仍保持冻结。
6. timeout 通过结构化并发取消底层流，完整 Tool Call 形成前不执行副作用。

## 未选择的方案

- 不重跑完整 Loop，不给每个后续 step 设置独立短 deadline，也不持久化格式化日期字符串。

## 结果

### 正向影响

- 手动重试可能仍创建新的请求 Trace，但用户 Turn、AI 气泡、检查点和 Loop 时间保持同一语义。
- 后续 step 可以等待较久，只受整轮预算约束；这避免在复杂 Tool 循环中用过短单步时限误杀。

### 成本与限制

- 格式化时间不再进入持久协议，迁移时仍兼容读取旧 `attemptStartedAt`。

## 验证

- `AgentJobTests`、`AgentV2Tests` 与 `AgentReliabilityTests` 覆盖固定时间、旧数据解码、预算、原生
  assistant/tool 消息恢复，以及批量 Tool 中途失败后只重试首个未完成 step。

## 参考

- [PRD 027](../prd/027-reliable-efficient-react-and-in-context-review.md)
