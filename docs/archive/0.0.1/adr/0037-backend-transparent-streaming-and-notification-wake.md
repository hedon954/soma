# ADR 0037：Backend 透明流式体验与通知驱动唤醒

- 状态：已采纳
- 日期：2026-08-03
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0031](0031-durable-agent-jobs-event-log-and-projections.md) 中把 Job 调度状态与用户体验 Event 混合、远程实时增量未形成统一流的边界
  - [ADR 0032](0032-optional-remote-agent-execution.md) 中 Remote Backend 以分页补拉作为前台正常交互路径的边界
- 后续替代：[ADR 0058](../../0.0.4/adr/0058-first-delta-deadline-and-bounded-retry.md) 增加 Provider 首增量、流空闲和单步骤总时限
- 上游依据：[BUG 0005](../../../bugs/0005-remote-agent-streaming-latency-regression.md)
- 下游落地：[Agent Job 与远程执行协议](../../../engineering/agent-job-protocol.md)
- 关联：[PRD 011](../prd/011-durable-agent-jobs-remote-continuity.md)

## 背景

持久 Job、服务器队列和 Event cursor 解决了 App 生命周期、断网恢复和幂等副作用，但第一版
Remote Backend 使用非流式 Provider、Worker 一秒轮询和 iOS 两秒分页补拉。用户必须等待完整
答案，Tool 往返还会叠加固定等待；执行位置已经泄漏为可感知的产品差异。

架构解耦只能改变任务所有权和恢复方式，不能降低聊天既有的流式体验。Soma 需要把本机直连与
远程 Job 定义为对 UI 观测等价的两个事件生产者。

## 决策

1. Local Backend 的 Provider Event 和 Remote Backend 的 Server Event 在 Service 层先归一为
   `AgentTraceEvent`，再使用同一聊天 reducer 更新文本、Skill、Tool、错误、Trace 和最终状态；
   View 不按 Backend 分支解释事件。
2. UI 观测等价指：发送回显、首段文本、增量文本、Agent 事件顺序、取消、错误和完成投影使用
   同一语义。不同网络跳数和模型性能可以影响物理耗时，但正常路径不得包含固定轮询等待。
3. 体验 Event 只保存用户能够观察或恢复流程所需的语义：文本片段、model、skill、tool、
   waiting、output、error 和 cancellation。queued、upload、ACK、lease、cursor 与 retry 作为
   Job 状态或无内容遥测，不生成聊天 Event Card。
4. Provider 使用原生流式 Tool Calling。文本按首段立即、自然边界、有限字符或短合并窗口形成
   chunk Event；禁止每个 token 一条数据库记录。最终 output 保存完整答案并校正增量快照。
5. API 在 Job 创建、Tool Result 入队和 Event 提交的 PostgreSQL 事务中发出 `NOTIFY`。Worker
   与 SSE 服务通过专用 `LISTEN` 连接立即唤醒；定时扫描仅用于通知丢失、进程重启和 lease
   恢复，不参与健康路径延迟。
6. iOS Remote Backend 在前台持续消费 SSE，以 `Last-Event-ID` / sequence 恢复。分页 Event
   端点只用于初始补齐、断线缺口和兼容降级；ACK 在本地持久化后异步提交，不阻塞 UI。
7. 设备 Tool Request 沿同一 SSE 到达。Tool Result 提交后立即通知 Worker 继续；连接保持时不
   重新等待轮询周期。App 被 iOS 挂起时仍诚实进入 `waitingForDevice`，回前台立即重连补齐。
8. 远端 Event 应用以 `remoteJobID + sequence` 幂等，本地 Event 以
   `jobID + attemptNumber + sequence` 幂等。聊天、Trace、Live Activity 和通知各自投影且不
   删除 Event；PostgreSQL 继续是远程事实来源，`NOTIFY` 只提供可丢失的唤醒提示。
9. Worker 在长模型流中续租或在提交 Event 时验证 epoch。失去 lease 的 Worker 不再输出，避免
   一个流被两个 Worker 同时投影。
10. 不并行发送本机和远端模型请求来伪造低延迟；一个 Job 只选择一个 Backend，副作用继续由
    稳定 Tool Call 和 `AgentMutationReceipt` 幂等。

## 未选择的方案

- 把一秒、两秒轮询改成更短间隔：仍然制造固定等待并放大网络、数据库与电量开销。
- UI 直接消费并删除队列：会破坏 Trace、系统投影、重放和断线恢复。
- WebSocket 作为首选：当前主要是服务器到设备的事件流；SSE 加幂等 POST 已覆盖需求且更容易
  按 cursor 恢复。
- 本机请求与远端 Job 竞速：会重复模型成本，并使 Tool 副作用和取消竞态失去单一事实来源。
- 每 token 持久化：写放大严重，Event Log 只需要可恢复的合并文本片段。

## 结果

### 正向影响

- 队列、数据库和服务器执行不再改变流式聊天外观。
- Job/Event 仍可恢复，同时首段文本和 Tool 请求在健康连接上即时到达。
- Local/Remote 可以使用同一确定性事件脚本验证 UI 等价。
- 调度与认证细节不再污染用户可见 Agent 轨迹。

### 成本与限制

- API 和 Worker 各需要 PostgreSQL 通知监听连接，并保留低频恢复扫描。
- Provider SSE 解析、文本合并、lease 续租和客户端重连需要新的协议测试。
- Remote Backend 使用 Soma 管理模型，模型本身或网络区域仍可能与用户 BYOK 路径耗时不同。
- iOS 挂起时不能即时执行设备 Tool；此平台限制不会通过后台模式伪装绕过。

## 验证

- 同一确定性 Provider 脚本经 Local/Remote Backend 后，移除时间戳和内部 ID，体验 Event 序列
  与 reducer 每一步状态完全一致。
- Provider 首段文本形成后不存在一秒或两秒固定等待。
- Job 创建、Tool Result 和 Event append 都会唤醒对应监听者；通知丢失后恢复扫描仍能完成。
- SSE 在任意 sequence 中断后从 cursor 补齐，不丢失、不重复文本或 Event Card。
- ACK、APNs 和 Live Activity 失败不阻塞聊天流。
- 数据库文本 Event 是合并 chunk，不是逐 token 行。
- `make verify`、服务端流式集成测试、模拟器交互和真机网络/后台验收通过。

## 参考

- [PRD 011](../prd/011-durable-agent-jobs-remote-continuity.md)
- [ADR 0031](0031-durable-agent-jobs-event-log-and-projections.md)
- [ADR 0032](0032-optional-remote-agent-execution.md)
- [BUG 0005](../../../bugs/0005-remote-agent-streaming-latency-regression.md)
- [Agent Job 与远程执行协议](../../../engineering/agent-job-protocol.md)
