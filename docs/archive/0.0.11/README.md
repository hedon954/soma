# Soma 0.0.11 归档摘要

本目录保存已滑出最近 3 个营销版本窗口的原始 PRD/ADR。Agent 默认不读取；只有维护者明确要求
历史时才打开原始文件。仍有效的最终状态已经折叠进活的 PRD 000 与 ADR 0000 压缩起点。

## 产品要求摘要

- PRD 042：可见失败后只允许用户恢复；每条 AI 回复支持原位有界多模态反馈；用户动作图优先，
  专属离线图不少于 239。

## 架构决策摘要

- ADR 0092：无可见增量的模型步骤最多三次 1/2/4 秒退避，Loop 外统一人工恢复。
- ADR 0093：逐回复反馈只携带单 Turn 有界脱敏上下文，发送时才定向组装。
- ADR 0094：动作图优先级为 user、bundled、generated、fallback。
- ADR 0095：只有 MetricKit 明确崩溃证据能够生成自动报告。
- ADR 0096：多模态能力必须有模型目录字段或远程部署显式来源，禁止按名称推断。

## 原始文件

- [PRD 042：用户控制的失败恢复、逐回复反馈与动作图扩容](prd/042-user-controlled-recovery-message-feedback-and-action-art.md)
- [ADR 0092：三次 ReAct 内部退避与 Loop 外人工恢复](adr/0092-react-internal-retry-and-user-controlled-recovery.md)
- [ADR 0093：逐条 AI 回复使用有界多模态反馈上下文](adr/0093-bounded-per-reply-multimodal-feedback-context.md)
- [ADR 0094：用户图优先与可升级的 239 张内置动作图](adr/0094-user-first-versioned-bundled-action-art.md)
- [ADR 0095：只有 MetricKit 明确崩溃证据才能生成报告](adr/0095-metrickit-confirmed-crash-reports.md)
- [ADR 0096：模型多模态能力必须由明确来源证明](adr/0096-source-backed-model-multimodal-capabilities.md)
