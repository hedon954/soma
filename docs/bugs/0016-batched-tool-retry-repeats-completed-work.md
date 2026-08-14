# BUG 0016：批量 Tool 中途失败会重复已成功的模型与工具步骤

- 状态：已修复，待维护者真机观察复杂 Loop
- 发现日期：2026-08-13
- 影响范围：ReAct 成本、延迟、幂等副作用、Trace 与聊天失败样式
- 上游依据：无
- 下游落地：[PRD 027](../prd/027-reliable-efficient-react-and-in-context-review.md)

## 症状

一次模型响应同时返回多个 `tool_calls` 时，只有整批工具全部执行成功才保存检查点。若第一个工具
成功、第二个工具抛出传输错误，重试会再次调用模型，也可能再次调用第一个工具；多次失败还会在
同一回复里残留重复失败状态。

## 根因

旧实现把一次“LLM + 整批 Tool”当成检查点 step，检查点只保存压缩 observation，没有保存原生
`assistant.tool_calls` 与逐条 `role=tool` 结果，因此无法从批次中间精确恢复。

## 修复

- 每个 LLM invoke 和每个 Tool Call 独立计步；模型成功产生 Tool 后先持久化批次，再逐条执行。
- 每个成功 Tool 立即保存完整 call ID、参数和结构化结果；重试先执行批次中首个未完成 Tool。
- 完成批次后，下一次模型请求恢复原生 assistant/tool 消息尾部，不用用户摘要伪装协议帧。
- Tool 抛错写入同一 Span 的失败终态；同气泡重试移除旧失败／运行投影并覆盖当前 step。

## 回归门禁

- `SomaTests.testAgentRetryContinuesAtFailedToolWithoutRepeatingCompletedSteps` 使用两个并行 Tool，证明
  第二个失败后重试只执行第二个，首个模型请求和第一个 Tool 均不重复。
- 固定 Loop 时间测试证明业务记录复用第一次执行时间，重试和跨午夜不刷新自然日。

## 验证

- `make verify` 必须通过；开发者 Trace 中 step 序号应按模型、工具、工具、模型递增。
