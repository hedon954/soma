# BUG 0026：远程模型调用缺少绑定工具清单

- 状态：已修复，待部署与真机远程模式复验
- 发现日期：2026-08-21
- 影响范围：后台持续处理、远程 Agent Event、执行日志与本机诊断日志
- 上游依据：
  - [PRD 033](../prd/033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md)
  - [ADR 0083](../adr/0083-local-diagnostics-log-and-silent-crash-reporting.md)

## 症状

本机 ReAct 的每次 LLM 调用都会把实际绑定的工具名和数量写入 Trace 与诊断日志；同一消息改用
「后台持续处理」后，执行日志里的「Soma 后台模型」Span 只显示媒体模式和请求次数，无法核对该次
调用是否真正注册了饮食、训练等工具。本机滚动诊断日志同样没有这次远程 LLM 调用。

## 根因

PRD 033 落地时只在 `AIService.announceModelStepStart` 接入了 `AgentDiagnostics.modelRequest`。
远程调用由 Server Worker 发起，`model.started` Event 没有携带 Worker 实际解析后的
`activeTools`；iOS 的远程 Event 投影因此既无法给 Span 写 `exposed_tool_names`，也没有调用统一
诊断日志入口。

## 修复

- Worker 在调用 Provider 前按当前 Job Envelope 解析实际工具集合，把工具名与数量写进
  `model.started` Event。
- iOS 将远程 Event 的工具集合投影为与本机一致的 `exposed_tool_names` /
  `exposed_tool_count` Span metadata，并写入 `AgentDiagnostics.modelRequest`。
- 旧 Server Event 不含新字段时继续兼容为空清单，不影响已有 Job 恢复或终态投影。

## 回归门禁

- Server 测试断言 Worker 的每个 `model.started` Event 精确保留本次 Provider 请求工具清单。
- `RemoteAgentExecutionTests` 断言远程 Event 可生成执行日志所需的可读工具摘要。
- 手工验收：部署 Server 后用虚构内容分别走本机与后台持续处理，在「高级设置 → 执行日志」中
  确认每个 LLM Span 都显示工具数量与完整名称，诊断日志同时出现对应调用。

## 隐私与数据

工具名称与 Schema 已随远程 Job Envelope 发送，本修复只把同一非身体元数据带回设备并写入本机
滚动日志；不新增用户正文、健康数据、密钥或媒体内容，不修改 SwiftData 与 PostgreSQL 结构。
