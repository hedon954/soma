# ADR 0048：循环检查点与同气泡中断续跑

- 状态：已采纳
- 日期：2026-08-05
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0031](0031-durable-agent-jobs-event-log-and-projections.md) 中本地路径「恢复即新 Attempt / 不重建 LLM 循环状态」的隐含语义
  - [ADR 0016](0016-conversation-turn-attempt-and-footprint-projection.md) 中「中断后续跑等同新 Attempt」的展示语义
- 上游依据：[PRD 022](../prd/022-react-reliability-and-context-awareness.md)
- 后续替代：[ADR 0063](0063-step-resume-fixed-loop-time-and-deadline-hierarchy.md) 将同气泡续跑扩展到失败 step，并固定 Loop 时间与整轮预算

## 背景

Job 与 PersistentAgentEvent 已能持久化 tool span，但 `AppServices.runAgent` 的
messages / observations / executedMutations 仍是内存变量。租约过期或进程被杀后，
本地路径总是新建 CoachMessage 并从 step 1 重跑，用户看到多余气泡，也浪费已完成步骤。

## 决策

1. 每个 ReAct step 结束后把 `AgentLoopCheckpoint` 写入 Job（lastCompletedStep、
   passages、压缩 observation、已暴露工具组）。
2. 中断恢复时复用 `job.responseMessageID` 指向的同一条 CoachMessage；丢掉 running /
   半截文本；从 `lastCompletedStep + 1` 继续。
3. 续跑不递增 `attemptNumber`。真正失败或用户手动重试才新开 Attempt / 新 Job。
4. 恢复上下文使用压缩观察摘要，不逐字复原 tool_call_id 协议消息。
5. 执行租约延长到 45 秒；`DataIntegrityRepair` 对有有效检查点的中断标记为可恢复，
   而不是 failed；无检查点中断必须同时把 Job 与回复气泡标为 failed，重新进入 App
   不得自动重跑，只能由用户手动重试。

## 未选择的方案

- 继续「永远新 Attempt」：简单但体感差、重复 prefill。
- 完整复原 OpenAI tool_call 消息：tool_call_id 与供应商状态难对齐。
- 引入 Temporal 类工作流运行时：超出当前本地优先边界。

## 结果

### 正向影响

- 中断后用户看到同一气泡继续，而不是第二条失败回复。
- 已成功 mutation 由规范化回执保护，续跑不重复写。

### 成本与限制

- 检查点落在 step 边界；正在流式的半截文本仍会丢弃。
- 续跑压缩摘要有损，模型需依赖摘要与本机事实包。

## 验证

- 租约过期模拟：同 responseMessageID，attemptNumber 不变，mutation 不重复。
- 无检查点的中断仍可标记 failed 并允许手动重试。

## 参考

- [PRD 022](../prd/022-react-reliability-and-context-awareness.md)
- [ADR 0031](0031-durable-agent-jobs-event-log-and-projections.md)
- [ADR 0016](0016-conversation-turn-attempt-and-footprint-projection.md)
