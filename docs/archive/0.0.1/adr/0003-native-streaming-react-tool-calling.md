# ADR 0003：使用原生流式 Tool Calling 构建 ReAct

- 状态：部分已替代
- 决策阶段：2026-07-28
- 后续替代：
  - [ADR 0032](0032-optional-remote-agent-execution.md) 增加可选服务器 ReAct 与设备 Tool handoff
  - [ADR 0050](../../0.0.3/adr/0050-per-turn-tool-group-exposure-and-parallel-calls.md) 修订每步全量工具暴露与串行 tool_calls 默认
- 后续修订：固定八轮上限改为高级设置可配置（默认 100，见 `ReActAgentPreference`）

## 背景

让模型输出一份自定义 JSON，再由 App 猜测它想执行什么，会把自然对话、结构化写入和错误恢复耦合在一个脆弱协议里。OpenAI-compatible API 已提供原生 Tool Calling 和流式返回。

## 决策

1. 使用 `SwiftOpenAI` 负责 OpenAI-compatible 网络请求与 SSE 解析。
2. App 负责有上限的 ReAct 编排；步数上限由 `ReActAgentPreference` 配置，默认 100（原固定八轮）。
3. 工具通过 API 的 `tools` 字段注册。
4. 模型可以自然输出文本，也可以返回 `assistant.tool_calls`。
5. 本地执行结果使用匹配的 `tool_call_id` 作为 `role: tool` 消息返回。
6. 每轮都使用流式调用；暂不消费或展示 thinking/reasoning。
7. 所有业务写入必须由 Tool Call 完成，不从最终回复文本中反向解析。

## 未选择的方案

- 自定义决策 JSON：重复发明协议，限制自然语言，并与供应商原生能力冲突。
- 把工具名称写进系统提示词：容易与真实 Tool Schema 漂移，也浪费上下文。
- 一次性非流式请求：用户无法看到长任务的即时进展。
- 自行维护底层 SSE 客户端：增加重复代码和供应商兼容成本。

## 结果

- 工具执行是确定性边界；自然语言负责解释和沟通。
- 工具错误可以回到下一轮让模型修正。
- 供应商必须至少兼容本产品使用的 Chat Completions、流式事件与 Tool Calling 子集。
- thinking 不是业务数据源，也不进入 Trace。
