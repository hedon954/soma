# Soma 架构决策记录

ADR 记录已经生效且会影响后续实现的关键决策。每篇只回答一个问题：当时有哪些选择、最终选了什么、为什么，以及这一选择带来的约束。

| ADR | 状态 | 决策 |
| --- | --- | --- |
| [0001](0001-local-first-dual-data-spaces.md) | 已采纳 | 无账户、本地优先，演示与个人数据空间隔离 |
| [0002](0002-chat-write-path-review-gui.md) | 已采纳 | 聊天是唯一创建路径，GUI 负责审查与统计 |
| [0003](0003-native-streaming-react-tool-calling.md) | 已采纳 | 使用原生流式 Tool Calling 构建 ReAct |
| [0004](0004-progressive-skills-fixed-tool-contract.md) | 已采纳 | Skills 渐进披露且可编辑，Tool 协议固定 |
| [0005](0005-trace-span-event-observability.md) | 部分已替代 | 一条消息一条 Trace，Span 通过 Event 流式渲染 |
| [0006](0006-data-truth-and-derived-metrics.md) | 已采纳 | 缺失值为空，统计和热量采用可追溯确定性规则 |
| [0007](0007-health-import-normalization-and-dedup.md) | 已采纳 | 外部健康数据先归一化，并用游标与外部 ID 去重 |
| [0008](0008-app-scoped-conversation-processing.md) | 已采纳 | 对话处理提升到 App 生命周期，而不是绑定聊天 View |
| [0009](0009-soma-brand-migration.md) | 已采纳 | 从代码到 Bundle ID 全量迁移为 Soma |
| [0010](0010-repository-governance-and-xcodegen.md) | 部分已替代 | 统一 Agent 契约、质量门禁与 XcodeGen 事实来源 |
| [0011](0011-fast-check-full-verify.md) | 部分已替代 | `make check` 快速静态检查，`make verify` 完整构建测试 |
| [0012](0012-ordered-mixed-media-collections.md) | 已采纳 | 有序混合媒体贯穿聊天、Agent、记录和审查 |
| [0013](0013-widget-and-app-intent-capture-routing.md) | 已采纳 | Widget 与 App Intent 只负责进入聊天录入 |
| [0014](0014-agent-turn-ordered-event-cards.md) | 已采纳 | 一次 Agent Turn 由有序异构 Event Cards 组成 |
| [0015](0015-daily-conversation-session-lifecycle.md) | 已采纳 | 进入前台时按自然日解析并持久化当前对话 Session |
| [0016](0016-conversation-turn-attempt-and-footprint-projection.md) | 已采纳 | Turn 可包含多次 Attempt，成功后投影到足迹并跨重试幂等 |
| [0017](0017-location-and-weather-context.md) | 部分已替代 | 位置作为最小、受控、非阻塞的 Turn 上下文；天气 Provider 由 ADR 0020 替代 |
| [0018](0018-provenance-aware-record-merge.md) | 已采纳 | 业务记录按来源、时间、内容、数值和纠错语义确定性合并 |
| [0019](0019-cost-aware-github-actions-gates.md) | 已采纳 | 日常 Actions 只跑快速门禁，完整验证与 CodeQL 收敛到 release tag |
| [0020](0020-open-meteo-transient-weather-provider.md) | 已采纳 | 使用 Open-Meteo 获取公里级、临时、非阻塞的天气上下文 |
| [0021](0021-portable-export-encrypted-backup-and-erasure.md) | 已采纳 | 分离开放年月日导出、外部加密备份恢复与个人数据清除 |
| [0022](0022-user-controlled-conversation-sessions.md) | 已采纳 | Session 由用户新建、选择并继续，不再按自然日强制切换 |
| [0023](0023-ordered-workout-set-evidence.md) | 已采纳 | 训练使用有序逐组次数与重量，组数和容量由逐组事实派生 |
| [0024](0024-session-context-projection-and-compaction.md) | 部分已替代 | 投影 Session 最近十个来回并在视觉额度内恢复历史媒体 |
| [0025](0025-tiered-model-profiles-and-routing.md) | 已采纳 | 使用小模型/标准双档配置与本地保守路由 |
| [0026](0026-bounded-gym-media-attribution.md) | 已采纳 | 只在紧邻命名确认时把上一轮健身房照片归入档案 |

新决策使用 [ADR 模板](template.md)。

状态定义：

- **已采纳**：当前实现和后续开发都应遵守；
- **部分已替代**：部分决策由后续 ADR 修订，其余部分仍生效；
- **已替代**：由后续 ADR 明确取代；
- **已废弃**：不再适用，但保留历史原因。
