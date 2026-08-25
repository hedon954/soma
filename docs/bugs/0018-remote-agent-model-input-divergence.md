# BUG 0018：远程 Agent 使用独立 Prompt 并丢失 ReAct 输入

- 状态：已修复；部署后端到端与真机授权文案待确认
- 发现日期：2026-08-15
- 影响范围：远程持续执行、Prompt、Skills、历史媒体、并行 Tool 与恢复
- 上游依据：无
- 下游落地：
  - [PRD 029](../archive/0.0.6/prd/029-unified-local-remote-agent-model-input.md)
  - [ADR 0068](../archive/0.0.6/adr/0068-versioned-unified-agent-model-input.md)

## 症状

同一消息选择本机执行时使用用户当前 Prompt、Skill 目录、最近历史和完整 Tool 契约；选择远程
持续执行时却使用 Server 写死的简短 Prompt 和扁平“最小上下文”。远程还会把 runtime Tool
交回设备，并在模型返回多个 `tool_calls` 时只保留第一项。

## 根因

早期远程实现只提交 `text/contextSnapshot/uploadIDs`，Server 为尽快打通 Worker 自行拼请求。
此后本地 Prompt、Tool 暴露、Skills、历史媒体、时限与检查点持续演进，但远程协议没有以同一
模型输入对象为事实来源；名称同步门禁也只能发现 Tool 缺项，不能发现描述、参数或消息差异。

## 修复

- 新增设备生成的版本化 `AgentModelInputEnvelope`，本地和远程共用 `AgentModelInputBuilder`。
- Envelope 传递原生消息序列、媒体 ID、当前 Skill 快照、完整 Tool 定义、初始集合和运行参数。
- 删除 Server 固定 Prompt 与最小上下文拼接，Provider 只消费 Envelope。
- Server 就地执行 `load_skill`，业务 Tool 继续设备 handoff。
- 持久化全部并行 Tool Call；所有结果到齐才排队续跑，并按原调用顺序恢复消息。
- 更新首次授权文案，明确 Prompt、Skills 与有界历史也会随远程 Job 临时发送。

## 回归门禁

- `scripts/check-agent-model-input-parity.rb`：两条路径必须共用 Builder，Server 禁止 Agent Prompt。
- `RemoteAgentExecutionTests`：逐项检查远程请求中的自定义 Prompt、历史、Skill、Tool 和运行参数。
- Server 测试：自定义 Skill 不产生设备请求；并行设备 Tool 不丢失且最后一个结果前不续跑。
- `make verify`：Swift/Server 静态检查、构建与模拟器测试。
- 手工验收：用虚构内容分别选择“本次仅本机”和后台持续处理，对照 Trace 的 Skill、Tool、媒体
  模式和最终记录；远程部署与真机网络切换仍需维护者确认。
