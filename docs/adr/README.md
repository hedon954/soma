# Soma 架构决策记录

ADR 记录已经生效且会影响后续实现的关键决策。每篇只回答一个问题：当时有哪些选择、最终选了什么、为什么，以及这一选择带来的约束。

| ADR | 状态 | 决策 |
| --- | --- | --- |
| [0001](0001-local-first-dual-data-spaces.md) | 部分已替代 | 无账户、本地优先，演示与个人数据空间隔离；AI 门禁和远程 Job 由 0027/0032 扩展 |
| [0002](0002-chat-write-path-review-gui.md) | 部分已替代 | 聊天是非结构化事实默认创建路径；带练与计划 GUI 分别由 0030/0036 扩展 |
| [0003](0003-native-streaming-react-tool-calling.md) | 部分已替代 | 原生流式 Tool Calling 保留；远程编排由 0032 扩展；工具暴露与并行由 0050 修订；步数上限改为可配置（默认 100） |
| [0004](0004-progressive-skills-fixed-tool-contract.md) | 部分已替代 | Skills 渐进披露且可编辑，Tool 协议固定；动态 Registry 与首轮直载由 0069 修订 |
| [0005](0005-trace-span-event-observability.md) | 部分已替代 | 一条消息一条 Trace，Span 通过 Event 流式渲染 |
| [0006](0006-data-truth-and-derived-metrics.md) | 部分已替代 | 缺失值为空；标量容量由 0023 的逐组事实替代 |
| [0007](0007-health-import-normalization-and-dedup.md) | 已采纳 | 外部健康数据先归一化，并用游标与外部 ID 去重 |
| [0008](0008-app-scoped-conversation-processing.md) | 部分已替代 | View 解耦保留；持久 Job 和远程执行由 0031/0032 扩展 |
| [0009](0009-soma-brand-migration.md) | 已采纳 | 从代码到 Bundle ID 全量迁移为 Soma |
| [0010](0010-repository-governance-and-xcodegen.md) | 部分已替代 | 统一 Agent 契约、质量门禁与 XcodeGen 事实来源 |
| [0011](0011-fast-check-full-verify.md) | 部分已替代 | `make check` 快速静态检查，`make verify` 完整构建测试 |
| [0012](0012-ordered-mixed-media-collections.md) | 已采纳 | 有序混合媒体贯穿聊天、Agent、记录和审查 |
| [0013](0013-widget-and-app-intent-capture-routing.md) | 已采纳 | Widget 与 App Intent 只负责快速进入；当前主屏保持静态快速记录 |
| [0014](0014-agent-turn-ordered-event-cards.md) | 部分已替代 | 有序 Event Cards 保留；多 Attempt 关系由 0016 修订 |
| [0015](0015-daily-conversation-session-lifecycle.md) | 部分已替代并恢复 | 旧消息归档保留；每日解析由 0055 恢复，手动继续旧会话仍有效 |
| [0016](0016-conversation-turn-attempt-and-footprint-projection.md) | 部分已替代 | Turn 可包含多次 Attempt；本地分析器路径由 0027 替代；同气泡续跑由 0048 修订 |
| [0017](0017-location-and-weather-context.md) | 部分已替代 | 位置作为最小、受控、非阻塞的 Turn 上下文；天气 Provider 由 ADR 0020 替代 |
| [0018](0018-provenance-aware-record-merge.md) | 部分已替代 | 业务记录按来源、时间、内容、数值和纠错语义确定性合并；规范化幂等与疑似重复由 0049 补充 |
| [0019](0019-cost-aware-github-actions-gates.md) | 已采纳 | 日常 Actions 只跑快速门禁，完整验证与 CodeQL 收敛到 release tag |
| [0020](0020-open-meteo-transient-weather-provider.md) | 已采纳 | 使用 Open-Meteo 获取公里级、临时、非阻塞的天气上下文 |
| [0021](0021-portable-export-encrypted-backup-and-erasure.md) | 已采纳 | 分离开放年月日导出、外部加密备份恢复与个人数据清除 |
| [0022](0022-user-controlled-conversation-sessions.md) | 部分已替代 | 用户新建、选择和继续保留；跨日默认恢复由 0055 修订 |
| [0023](0023-ordered-workout-set-evidence.md) | 已采纳 | 训练使用有序逐组次数与重量，组数和容量由逐组事实派生 |
| [0024](0024-session-context-projection-and-compaction.md) | 部分已替代 | 最近十个完整来回保留；十轮外滚动压缩由 0070 修订 |
| [0025](0025-tiered-model-profiles-and-routing.md) | 部分已替代 | 双档配置与本地保守路由保留；远程启用前提由 0027 替代，模型选择控件由 0046 替代 |
| [0026](0026-bounded-gym-media-attribution.md) | 已采纳 | 只在紧邻命名确认时把上一轮健身房照片归入档案 |
| [0027](0027-required-ai-configuration-and-send-gate.md) | 部分已替代 | 聊天始终使用 AI；发送前硬门禁由 0045 改为暂存补偿，页面命名由 0046 改为「LLM 配置」 |
| [0028](0028-semantic-exercise-identity.md) | 部分已替代 | 稳定动作身份保留；搜索分页由 0059 修订，Int64 表示和关系由 0071 修订 |
| [0029](0029-versioned-training-plans-and-session-facts.md) | 部分已替代 | 计划版本与事实分层保留；Int64 身份和动作关系由 0071 修订 |
| [0030](0030-deterministic-guided-workout-and-session-recording.md) | 部分已替代 | 确定性状态机和录像目标保留；UI 与录像几何由 0038 修订 |
| [0031](0031-durable-agent-jobs-event-log-and-projections.md) | 部分已替代 | Agent 使用持久 Job、语义 Event Log 与独立投影；本地同气泡检查点续跑由 0048 修订 |
| [0032](0032-optional-remote-agent-execution.md) | 已采纳 | 以匿名设备身份提供可选远程持续执行与本地 Tool handoff |
| [0033](0033-live-activity-agent-job-projection.md) | 已采纳 | Live Activity 只投影隐私安全的 Agent Job 状态 |
| [0034](0034-bidirectional-document-lifecycle-links.md) | 已采纳 | 文档修订、替代与研究落地关系使用双向生命周期索引 |
| [0035](0035-silent-bundled-exercise-content-and-on-demand-images.md) | 部分已替代 | 静默内置内容与按需动作插画保留；通用肌群图素材与生成由 0044 替代 |
| [0036](0036-gui-training-program-authoring.md) | 部分已替代 | GUI 确定性创建保留；折叠处方和最近值由 0038 扩展 |
| [0037](0037-backend-transparent-streaming-and-notification-wake.md) | 部分已替代 | Local/Remote 流式等价保留；Provider 时限由 0058 扩展 |
| [0038](0038-focused-guided-workout-and-capture-geometry.md) | 部分已替代 | 聚焦投影、单步组确认与放大画幅保留；按需相机与紧凑预览由 0039 修订 |
| [0039](0039-event-driven-guided-recording-cues-and-review.md) | 已采纳 | 录像策略与实际活动分离，按 Set 保存证据，并以事件驱动语音、复盘和删除 |
| [0040](0040-agent-guided-workout-launch.md) | 已采纳 | Agent 用固定计划 Tool 在设备本地创建快照并路由到既有带练 |
| [0041](0041-training-primary-tab.md) | 已采纳 | 训练计划与带练迁移为一级训练 Tab，进展保留审查与趋势 |
| [0042](0042-contextual-widget-snapshot-and-privacy.md) | 暂缓 | 主屏最小快照方案，待支持 App Groups 的 Team 后恢复 |
| [0043](0043-free-team-widget-fallback.md) | 已采纳 | 免费签名阶段保留静态快速记录，不使用 App Groups |
| [0044](0044-programmatic-muscle-map-and-training-share-poster.md) | 已采纳 | 规范肌群枚举与矢量路径程序化渲染受力图，分享海报本地生成 |
| [0045](0045-llm-outage-staging-and-compensating-drain.md) | 已采纳 | LLM 失效时消息落盘暂存，恢复后按 FIFO 自动补偿消费 |
| [0046](0046-explicit-llm-configuration-and-input-history-suggestions.md) | 已采纳 | LLM 配置字段直接摊开并即时落盘，模型与动作候选统一为输入历史式建议 |
| [0047](0047-deterministic-context-pack-and-cross-turn-facts.md) | 部分已替代 | 确定性当轮上下文包保留；十轮外 digest 由 0070 的滚动摘要替代 |
| [0048](0048-loop-checkpoint-and-same-bubble-resume.md) | 已采纳 | 本地 ReAct 在 step 边界落检查点，中断后同气泡续跑且不递增 attemptNumber |
| [0049](0049-normalized-idempotency-and-business-dedup.md) | 已采纳 | 规范化幂等签名、pending 账本与跨 Turn 疑似重复反馈 |
| [0050](0050-per-turn-tool-group-exposure-and-parallel-calls.md) | 部分已替代 | 每轮工具组预选、expand_tool_group 逃生、并行 tool_calls 与历史帧 clearing；feedback 组由 0054 增加 |
| [0051](0051-authenticated-in-app-feedback-email-delivery.md) | 部分已替代 | 应用内多模态反馈经认证 Server 和临时上传投递到固定维护者邮箱；邮件供应商由 0052 替代 |
| [0052](0052-gmail-self-delivery-for-in-app-feedback.md) | 部分已替代 | Gmail OAuth 从 `hedonwang@gmail.com` 向同一邮箱自发自收；个人阶段的凭据位置由 0053 临时替代 |
| [0053](0053-personal-only-direct-qq-mail-feedback.md) | 已采纳，仅限个人使用阶段 | App 直连 QQ SMTP 并投递到固定 Gmail；外部分发由 online check 强制迁移凭据 |
| [0054](0054-device-executed-chat-feedback-tool.md) | 已采纳 | Chat 通过无参数固定 Tool 提交当前 Turn 原文与媒体；本机等待 SMTP，远程模式交回设备执行 |
| [0055](0055-hybrid-daily-conversation-sessions.md) | 部分已替代 | 自动按日解析保留；可编辑业务日与 Turn 日期覆盖由 0072 修订 |
| [0056](0056-trusted-selective-multimodal-context.md) | 部分已替代 | 可信时间、token 预算与选择性媒体保留；滚动摘要由 0070 修订 |
| [0057](0057-direct-video-capability-and-observable-fallback.md) | 已采纳 | 按 provider/model 能力直传视频，失败后才按需抽帧并诚实降级 |
| [0058](0058-first-delta-deadline-and-bounded-retry.md) | 已采纳 | 8/10/20 秒首增量门禁、单次重试、idle/total timeout 与取消传播 |
| [0059](0059-precise-tools-and-reviewable-meal-items.md) | 部分已替代 | 可审查饮食分项保留；通用查询与 CRUD 由 0069 的强类型 Tool 替代 |
| [0060](0060-guided-performance-workout-entry-projection.md) | 已采纳 | 终态带练动作物化为训练记录，以来源 ID 组成计划执行并避免重复统计 |
| [0061](0061-discoverable-conversation-session-entry.md) | 已采纳 | 会话抽屉同时保留左上角时间按钮、左缘手势与 VoiceOver 操作 |
| [0062](0062-user-resumed-llm-interruption-barrier.md) | 已采纳 | 明确欠费只由用户释放，后续消息受严格 FIFO 屏障约束 |
| [0063](0063-step-resume-fixed-loop-time-and-deadline-hierarchy.md) | 部分已替代 | 失败 step 同气泡续跑和冻结业务时间保留；墙钟预算由 0067 改为活动执行预算 |
| [0064](0064-deterministic-quick-write-and-latest-inline-review.md) | 已采纳 | 未修改 typed 快捷训练直写本地，最新 AI 回复提供原位记录 CRUD 与修订上下文 |
| [0065](0065-intent-scoped-tools-and-prefix-stable-prompts.md) | 部分已替代 | 明确副作用意图和原生协议保留；Prompt v2 与 Skill 最小工具集由 0069 修订 |
| [0066](0066-bundled-action-illustration-coverage.md) | 已采纳 | 静默内置目录至少维持一百个 common action 专属离线图 |
| [0067](0067-separate-business-time-and-active-loop-budget.md) | 部分已替代 | 活动执行预算保持；记录发生时间由 0072 从 Loop 时间拆分 |
| [0068](0068-versioned-unified-agent-model-input.md) | 部分已替代 | 设备生成统一输入保持；Prompt、Skill 与 Tool v3 由 0069 升级 |
| [0069](0069-layered-agent-prompt-skill-middleware-and-typed-tools.md) | 已采纳 | 分层 Prompt、动态 Skill Middleware 与按领域强类型 Tool |
| [0070](0070-reviewable-rolling-session-compaction.md) | 已采纳 | 十轮外对话在 Loop 前形成可追溯、可回退的替代式滚动摘要 |
| [0071](0071-integer-business-identities-and-explicit-relations.md) | 已采纳 | 本机业务身份使用 Int64，训练动作建立明确关系，并以启动门禁迁移旧库 |
| [0072](0072-session-business-date-and-record-occurrence-time.md) | 已采纳 | Session 业务日与记录发生时间分离，Tool 可显式覆盖 occurred_at |

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
