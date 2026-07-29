# Soma 架构决策记录

ADR 记录已经生效且会影响后续实现的关键决策。每篇只回答一个问题：当时有哪些选择、最终选了什么、为什么，以及这一选择带来的约束。

| ADR | 状态 | 决策 |
| --- | --- | --- |
| [0001](0001-local-first-dual-data-spaces.md) | 已采纳 | 无账户、本地优先，演示与个人数据空间隔离 |
| [0002](0002-chat-write-path-review-gui.md) | 已采纳 | 聊天是唯一创建路径，GUI 负责审查与统计 |
| [0003](0003-native-streaming-react-tool-calling.md) | 已采纳 | 使用原生流式 Tool Calling 构建 ReAct |
| [0004](0004-progressive-skills-fixed-tool-contract.md) | 已采纳 | Skills 渐进披露且可编辑，Tool 协议固定 |
| [0005](0005-trace-span-event-observability.md) | 已采纳 | 一条消息一条 Trace，Span 通过 Event 流式渲染 |
| [0006](0006-data-truth-and-derived-metrics.md) | 已采纳 | 缺失值为空，统计和热量采用可追溯确定性规则 |
| [0007](0007-health-import-normalization-and-dedup.md) | 已采纳 | 外部健康数据先归一化，并用游标与外部 ID 去重 |
| [0008](0008-app-scoped-conversation-processing.md) | 已采纳 | 对话处理提升到 App 生命周期，而不是绑定聊天 View |
| [0009](0009-soma-brand-migration.md) | 已采纳 | 从代码到 Bundle ID 全量迁移为 Soma |
| [0010](0010-repository-governance-and-xcodegen.md) | 部分已替代 | 统一 Agent 契约、质量门禁与 XcodeGen 事实来源 |
| [0011](0011-fast-check-full-verify.md) | 已采纳 | `make check` 快速静态检查，`make verify` 完整构建测试 |

新决策使用 [ADR 模板](template.md)。

状态定义：

- **已采纳**：当前实现和后续开发都应遵守；
- **部分已替代**：部分决策由后续 ADR 修订，其余部分仍生效；
- **已替代**：由后续 ADR 明确取代；
- **已废弃**：不再适用，但保留历史原因。
