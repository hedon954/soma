# Soma 0.0.3 归档摘要

本目录保存已滑出最近 3 个营销版本窗口的原始 PRD/ADR。Agent 默认不读取；
只有维护者明确要求历史时才打开原始文件。

## 产品要求摘要

- PRD 020：GUI 精简与渐进披露
- PRD 021：LLM 暂存补偿、显式 LLM 配置与一步输入建议
- PRD 022：ReAct 可靠性与上下文感知

## 架构决策摘要

- ADR 0045：LLM 失效时本地暂存并在恢复后补偿消费
- ADR 0046：LLM 配置直接摊开，候选值统一为输入历史式建议
- ADR 0047：确定性上下文包与跨轮工具事实摘要
- ADR 0048：循环检查点与同气泡中断续跑
- ADR 0049：规范化幂等键与业务级重复识别
- ADR 0050：每轮工具组渐进披露与并行 tool_calls

## 原始文件

- [PRD 020：GUI 精简与渐进披露](prd/020-gui-simplification-and-progressive-disclosure.md)
- [PRD 021：LLM 暂存补偿、显式 LLM 配置与一步输入建议](prd/021-llm-staging-explicit-configuration-and-input-suggestions.md)
- [PRD 022：ReAct 可靠性与上下文感知](prd/022-react-reliability-and-context-awareness.md)
- [ADR 0045：LLM 失效时本地暂存并在恢复后补偿消费](adr/0045-llm-outage-staging-and-compensating-drain.md)
- [ADR 0046：LLM 配置直接摊开，候选值统一为输入历史式建议](adr/0046-explicit-llm-configuration-and-input-history-suggestions.md)
- [ADR 0047：确定性上下文包与跨轮工具事实摘要](adr/0047-deterministic-context-pack-and-cross-turn-facts.md)
- [ADR 0048：循环检查点与同气泡中断续跑](adr/0048-loop-checkpoint-and-same-bubble-resume.md)
- [ADR 0049：规范化幂等键与业务级重复识别](adr/0049-normalized-idempotency-and-business-dedup.md)
- [ADR 0050：每轮工具组渐进披露与并行 tool_calls](adr/0050-per-turn-tool-group-exposure-and-parallel-calls.md)
