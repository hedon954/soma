# Soma 0.0.6 归档摘要

本目录保存已滑出最近 3 个营销版本窗口的原始 PRD/ADR。Agent 默认不读取；
只有维护者明确要求历史时才打开原始文件。

## 产品要求摘要

- PRD 029：本地与远程 Agent 模型输入完全统一
- PRD 030：Agent Prompt、Skill、上下文与强类型 Tool v3

## 架构决策摘要

- ADR 0068：版本化统一 Agent 模型输入由设备生成
- ADR 0069：分层 Agent Prompt、Skill Middleware 与强类型 Tool
- ADR 0070：可审查的滚动 Session 压缩
- ADR 0071：整型业务身份与明确领域关系
- ADR 0072：Session 业务日与记录发生时间分离

## 原始文件

- [PRD 029：本地与远程 Agent 模型输入完全统一](prd/029-unified-local-remote-agent-model-input.md)
- [PRD 030：Agent Prompt、Skill、上下文与强类型 Tool v3](prd/030-agent-prompt-skill-context-and-tool-v3.md)
- [ADR 0068：版本化统一 Agent 模型输入由设备生成](adr/0068-versioned-unified-agent-model-input.md)
- [ADR 0069：分层 Agent Prompt、Skill Middleware 与强类型 Tool](adr/0069-layered-agent-prompt-skill-middleware-and-typed-tools.md)
- [ADR 0070：可审查的滚动 Session 压缩](adr/0070-reviewable-rolling-session-compaction.md)
- [ADR 0071：整型业务身份与明确领域关系](adr/0071-integer-business-identities-and-explicit-relations.md)
- [ADR 0072：Session 业务日与记录发生时间分离](adr/0072-session-business-date-and-record-occurrence-time.md)
