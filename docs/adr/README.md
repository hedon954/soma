# Soma 架构决策记录

ADR 记录已经生效且会影响后续实现的关键决策。每篇只回答一个问题：当时有哪些选择、最终选了什么、为什么，以及这一选择带来的约束。

| ADR | 状态 | 决策 |
| --- | --- | --- |
| [0001](0001-local-first-dual-data-spaces.md) | 部分已替代 | 无账户、本地优先，演示与个人数据空间隔离；AI 门禁和远程 Job 由 0027/0032 扩展 |
| [0002](0002-chat-write-path-review-gui.md) | 部分已替代 | 聊天是非结构化事实默认创建路径；带练与计划 GUI 分别由 0030/0036 扩展 |
| [0003](0003-native-streaming-react-tool-calling.md) | 部分已替代 | 原生流式 Tool Calling 保留；远程编排由 0032 扩展 |
| [0004](0004-progressive-skills-fixed-tool-contract.md) | 已采纳 | Skills 渐进披露且可编辑，Tool 协议固定 |
| [0005](0005-trace-span-event-observability.md) | 部分已替代 | 一条消息一条 Trace，Span 通过 Event 流式渲染 |
| [0006](0006-data-truth-and-derived-metrics.md) | 部分已替代 | 缺失值为空；标量容量由 0023 的逐组事实替代 |
| [0007](0007-health-import-normalization-and-dedup.md) | 已采纳 | 外部健康数据先归一化，并用游标与外部 ID 去重 |
| [0008](0008-app-scoped-conversation-processing.md) | 部分已替代 | View 解耦保留；持久 Job 和远程执行由 0031/0032 扩展 |
| [0009](0009-soma-brand-migration.md) | 已采纳 | 从代码到 Bundle ID 全量迁移为 Soma |
| [0010](0010-repository-governance-and-xcodegen.md) | 部分已替代 | 统一 Agent 契约、质量门禁与 XcodeGen 事实来源 |
| [0011](0011-fast-check-full-verify.md) | 部分已替代 | `make check` 快速静态检查，`make verify` 完整构建测试 |
| [0012](0012-ordered-mixed-media-collections.md) | 已采纳 | 有序混合媒体贯穿聊天、Agent、记录和审查 |
| [0013](0013-widget-and-app-intent-capture-routing.md) | 已采纳 | Widget 与 App Intent 只负责进入聊天录入 |
| [0014](0014-agent-turn-ordered-event-cards.md) | 部分已替代 | 有序 Event Cards 保留；多 Attempt 关系由 0016 修订 |
| [0015](0015-daily-conversation-session-lifecycle.md) | 已替代 | 旧消息归档等约束保留；每日自动切换由 0022 替代 |
| [0016](0016-conversation-turn-attempt-and-footprint-projection.md) | 部分已替代 | Turn 可包含多次 Attempt；本地分析器路径由 0027 替代 |
| [0017](0017-location-and-weather-context.md) | 部分已替代 | 位置作为最小、受控、非阻塞的 Turn 上下文；天气 Provider 由 ADR 0020 替代 |
| [0018](0018-provenance-aware-record-merge.md) | 已采纳 | 业务记录按来源、时间、内容、数值和纠错语义确定性合并 |
| [0019](0019-cost-aware-github-actions-gates.md) | 已采纳 | 日常 Actions 只跑快速门禁，完整验证与 CodeQL 收敛到 release tag |
| [0020](0020-open-meteo-transient-weather-provider.md) | 已采纳 | 使用 Open-Meteo 获取公里级、临时、非阻塞的天气上下文 |
| [0021](0021-portable-export-encrypted-backup-and-erasure.md) | 已采纳 | 分离开放年月日导出、外部加密备份恢复与个人数据清除 |
| [0022](0022-user-controlled-conversation-sessions.md) | 已采纳 | Session 由用户新建、选择并继续，不再按自然日强制切换 |
| [0023](0023-ordered-workout-set-evidence.md) | 已采纳 | 训练使用有序逐组次数与重量，组数和容量由逐组事实派生 |
| [0024](0024-session-context-projection-and-compaction.md) | 部分已替代 | 投影 Session 最近十个来回并在视觉额度内恢复历史媒体 |
| [0025](0025-tiered-model-profiles-and-routing.md) | 部分已替代 | 双档配置与本地保守路由保留；远程启用前提由 0027 替代 |
| [0026](0026-bounded-gym-media-attribution.md) | 已采纳 | 只在紧邻命名确认时把上一轮健身房照片归入档案 |
| [0027](0027-required-ai-configuration-and-send-gate.md) | 已采纳 | 聊天始终使用 AI，并在发送前引导补齐标准档 API Key |
| [0028](0028-semantic-exercise-identity.md) | 已采纳 | 动作使用稳定 ID，模型基于完整 ID/名称列表完成语义归一 |
| [0029](0029-versioned-training-plans-and-session-facts.md) | 已采纳 | 分离计划版本、执行快照、逐组事实与 AI 建议 |
| [0030](0030-deterministic-guided-workout-and-session-recording.md) | 部分已替代 | 确定性状态机和录像目标保留；UI 与录像几何由 0038 修订 |
| [0031](0031-durable-agent-jobs-event-log-and-projections.md) | 已采纳 | Agent 使用持久 Job、语义 Event Log 与独立投影 |
| [0032](0032-optional-remote-agent-execution.md) | 已采纳 | 以匿名设备身份提供可选远程持续执行与本地 Tool handoff |
| [0033](0033-live-activity-agent-job-projection.md) | 已采纳 | Live Activity 只投影隐私安全的 Agent Job 状态 |
| [0034](0034-bidirectional-document-lifecycle-links.md) | 已采纳 | 文档修订、替代与研究落地关系使用双向生命周期索引 |
| [0035](0035-silent-bundled-exercise-content-and-on-demand-images.md) | 已采纳 | 内置动作内容保持静默，用户使用动作后才关联素材，长尾图片按需生成 |
| [0036](0036-gui-training-program-authoring.md) | 部分已替代 | GUI 确定性创建保留；折叠处方和最近值由 0038 扩展 |
| [0037](0037-backend-transparent-streaming-and-notification-wake.md) | 已采纳 | Local/Remote Backend 对 UI 提供等价流式事件，并由 PostgreSQL 通知即时唤醒 |
| [0038](0038-focused-guided-workout-and-capture-geometry.md) | 部分已替代 | 聚焦投影、单步组确认与放大画幅保留；按需相机与紧凑预览由 0039 修订 |
| [0039](0039-event-driven-guided-recording-cues-and-review.md) | 已采纳 | 录像策略与实际活动分离，按 Set 保存证据，并以事件驱动语音、复盘和删除 |
| [0040](0040-agent-guided-workout-launch.md) | 已采纳 | Agent 用固定计划 Tool 在设备本地创建快照并路由到既有带练 |

新决策使用 [ADR 模板](template.md)。

状态定义：

- **已采纳**：当前实现和后续开发都应遵守；
- **部分已替代**：部分决策由后续 ADR 修订，其余部分仍生效；
- **已替代**：由后续 ADR 明确取代；
- **已废弃**：不再适用，但保留历史原因。

## 替代关系

- 旧 ADR 用“后续替代”链接新 ADR；新 ADR 用“替代”或“部分替代”反向链接旧 ADR。
- 一个决策只被部分替代时，旧文继续保存仍有效内容和替代范围，不能直接改写成仿佛旧决策
  从未存在。
- 研究转 ADR 时使用“下游落地”与“上游依据”形成双向关系。
- 双向链接由 `make check` 自动验证；新增决策从 [ADR 模板](template.md) 开始。
