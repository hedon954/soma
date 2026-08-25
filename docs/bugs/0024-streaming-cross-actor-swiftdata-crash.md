# BUG 0024：流式回复期间跨 actor 写 SwiftData 导致频繁闪退

- 状态：已修复，待真机连续对话复验
- 发现日期：2026-08-20
- 影响范围：教练聊天流式回复、Agent Event 投影、Turn Item 卡片渲染
- 上游依据：
  - [ADR 0031](../archive/0.0.1/adr/0031-durable-agent-jobs-event-log-and-projections.md)
  - [ADR 0014](../archive/0.0.1/adr/0014-agent-turn-ordered-event-cards.md)
- 下游落地：
  - [PRD 033](../archive/0.0.7/prd/033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md)
  - [ADR 0083](../archive/0.0.7/adr/0083-local-diagnostics-log-and-silent-crash-reporting.md)

## 症状

教练回复正在逐字输出时 App 直接退到桌面，频率高到影响正常使用。崩溃没有固定内容触发点，
长回复、带工具调用的回复都会发生。重新进入 App 后该 Turn 停在中断状态。

崩溃现场没有任何可读证据：`os.Logger` 在进程被杀后无法检索，Trace 只保留到最后一次成功落盘的事件。

## 根因

`AgentStreamDeadline.consume` 与它的 `onChunk` 回调都是 nonisolated。SSE chunk 在
`AgentStreamChunkReader` actor 或 URLSession executor 上恢复后，回调同步直链走到
`AIServiceAgentStreaming.consumeAgentStream` → `trace?(.assistantTextDelta)` →
`ConversationProcessingService` → `PersistentAgentEventProjection.persistAndProject`，
在非主线程修改 `@Model` 与 `@Observable`。

项目当前是 Swift 5 language mode，`@MainActor` 标注不产生运行时跳转，因此编译静默通过，
而每个 token 都触发一次跨 actor 写入，命中 SwiftData 与 AttributeGraph 的非线程安全路径。

放大因素有两个：

1. 每个文字增量都要全量解码-编码 `agentTurnItemsData`，写入频率与 token 数同阶。
2. `AgentChatPresentation` 的 process segment 用首个 item 的 UUID 作为 id，而
   `AgentTurnTranscript` 在同一 id 上会从单卡切换到分组卡，`ForEach` 身份漂移让 SwiftUI 在
   已被并发修改的模型上重建视图。

## 修复

- `AgentStreamDeadline.consume` 与 `onChunk` 显式标为 `@MainActor`，恢复点回到主 actor 后才投影。
- 文字增量经 `AgentTextDeltaCoalescer` 合批（约 100ms 或 span 边界刷新一次），把每 token 的持久化
  与 Markdown 重排降到人眼可接受的频率。
- segment id 携带形态标记（`process-group` / `process-single` / `item`），同一批 item 在切换呈现
  形态时不再复用同一身份。
- `persistAndProject` 与 `applyLiveAgentEvent` 入口在 DEBUG 下 `MainActor.assertIsolated()`，
  后续任何跨 actor 投影在开发期立即失败。
- 崩溃证据不再依赖复现：诊断日志与自动上报见 ADR 0083。

## 回归门禁

- 自动化测试：合批缓冲按时间与 flush 边界输出、不丢字符也不重复；segment id 在单卡与分组形态下唯一
  且在分组增长时保持稳定。
- `make check` 静态门禁：流式 chunk 回调保持 `@MainActor`，事件投影保留主 actor 断言。
- 手工验收：真机连续发送 10 轮含工具调用的长回复，不出现闪退；诊断日志能看到完整的 turn 终态。

## 验证

- `AgentStreamProjectionSafetyTests`
- `AgentChatPresentationTests`
- 夹具只使用虚构文本，不含真实健康数据或密钥。
