# Soma 产品需求文档

本目录按产品决策形成的先后顺序，记录 Soma 从最初的“个人 AI 健身工具”演进为“聊天优先、本地优先的私人身体智能”的过程。

这些文件不是聊天记录的逐句转写，而是三层整理：

1. 当时要解决的用户问题；
2. 该阶段确定、保留或否决的需求；
3. 这些需求如何进入当前 Soma。

## 迭代索引

| 文档 | 阶段 | 核心变化 |
| --- | --- | --- |
| [001：私人 AI 健身教练基础](001-private-ai-fitness-coach.md) | 初始构想 | 多健身房、饮食、身体、训练、多模态、本地隐私和统计 |
| [002：聊天优先与审查闭环](002-chat-first-review-loop.md) | 产品收敛 | 聊天成为唯一录入入口，GUI 退回审查、纠错与统计 |
| [003：流式 ReAct Agent 平台](003-streaming-react-agent.md) | 智能化重构 | 原生 Tool Calling、渐进式 Skills、流式 Event、Trace/Span |
| [004：Soma 当前产品基线](004-soma-current-product.md) | 当前基线 | 身体信息、热量估算、有序混合媒体、Widget/系统快捷入口、健康数据接入和异步处理 |
| [005：对话 Session 与发送反馈](005-conversation-sessions-and-send-feedback.md) | 对话收敛 | 跨天 Session、发送后收起输入并滚到底部、开发者日志入口 |
| [006：足迹、位置上下文与失败重试](006-footprints-location-and-retry.md) | 个人回顾 | 成功消息足迹、一次性位置、场馆上下文、按需天气和可幂等重试 |
| [007：数据导出、自动备份与主动清除](007-data-export-backup-and-erasure.md) | 数据主权 | 开放年月日导出、外部加密自动备份、恢复与个人数据清除 |
| [008：连续对话、逐组训练与自适应模型](008-coach-continuity-and-adaptive-models.md) | 体验精化，部分修订 | 隐藏式可继续 Session、一次性位置确认、逐组训练、媒体上下文、长会话压缩与双档模型；双档配置呈现由 021 修订 |
| [009：记录媒体归档与单张解绑](009-record-media-association-and-detachment.md) | 媒体审查 | 健身房跨轮照片归档，以及健身房、训练、饮食和身体记录的单张媒体解绑 |
| [010：动作库、训练计划、带练与视频复盘](010-exercise-library-plans-guided-training.md) | 部分修订 | 稳定动作身份、最近值快捷输入、版本化计划、逐组带练和自动录像；计划与带练体验由 012/013 扩展，版本历史、归档恢复与肌群图由 019 修订 |
| [011：持久 Agent Job 与远程持续执行](011-durable-agent-jobs-remote-continuity.md) | 已实现，部分修订 | 本地 Outbox、服务端 Job/Event、设备 Tool handoff、灵动岛和通知；发送前置条件由 021 改为暂存补偿 |
| [012：GUI 训练计划编排](012-gui-training-program-authoring.md) | 部分修订 | 从动作库选择、排序并配置处方；折叠处方和最近值由 013 扩展 |
| [013：低摩擦计划与沉浸式带练](013-guided-workout-experience-and-capture.md) | 部分修订 | 动作图编排、显式最近值、聚焦逐组带练和横竖屏真实取景；相机触发与反馈由 014 修订 |
| [014：按需录像、完整语音与完成复盘](014-guided-workout-recording-cues-and-review.md) | 已实现，部分修订 | 单组/每组/手动录像、按需相机、事件语音、本地总结和历史删除；录像失败反馈由 019 修订 |
| [015：对话启动计划带练](015-agent-guided-workout-launch.md) | 已实现，待真机验收 | Agent 查询可执行计划并在本机启动确定性带练 |
| [016：训练成为一级执行入口](016-training-primary-tab.md) | 已实现，待真机验收 | 训练计划与带练从进展迁移为一级训练 Tab |
| [017：情境化私人教练主屏组件](017-contextual-private-coach-widgets.md) | 暂缓 | 需支持 App Groups 的 Team 后恢复动态训练状态 |
| [018：免费签名 Widget 能力降级](018-free-team-widget-fallback.md) | 已实现，待真机验收 | 保留静态快速记录和锁屏入口，移除 App Groups 依赖 |
| [019：训练回顾分组筛选、计划管理补全与程序化受力图分享](019-training-review-plan-management-and-muscle-map-share.md) | 已实现，待真机验收 | 记录按天分组筛选分页、回复排版修复、计划删除/恢复/变更说明、录像失败提示、程序化受力图与分享海报 |
| [020：GUI 精简与渐进披露](020-gui-simplification-and-progressive-disclosure.md) | 已实现，部分修订 | 全界面渐进披露：输入区单层上下文、过程卡折叠、详情只读优先、低频入口下沉，不删任何能力；LLM 配置折叠与输入区候选由 021 修订 |
| [021：LLM 暂存补偿、显式 LLM 配置与一步输入建议](021-llm-staging-explicit-configuration-and-input-suggestions.md) | 已实现，待真机验收 | LLM 失效时消息落盘暂存并在恢复后自动补偿；LLM 配置双档同屏可改、支持 opencode 与自定义 URL；模型与动作候选统一为输入历史式建议 |
| [022：ReAct 可靠性与上下文感知](022-react-reliability-and-context-awareness.md) | 已实现，待真机验收 | 确定性上下文包与聚合查询、规范化幂等与疑似重复、同气泡 step 检查点续跑、工具组渐进披露与并行 tool_calls |
| [023：应用内多模态反馈](023-in-app-multimodal-feedback.md) | 已实现，待生产服务配置与真机验收 | Soma 内文字、照片和视频反馈，经认证 Server 幂等投递到固定维护者邮箱 |

## 阅读约定

- “当前要求”表示仍然有效，并应由当前实现持续满足。
- “被替代”表示曾经实现或讨论过，但已被后续决策取代。
- 产品验收证据集中在 [验收清单](../acceptance.md)。
- 技术与交互取舍集中在 [ADR](../adr/README.md)。
- 按日期重建的变更记录集中在 [Changelog](../changelog/README.md)。
- 新 PRD 从 [模板](template.md) 开始。

## 修订关系

- 旧 PRD 用“后续修订”链接所有改变其边界的新 PRD。
- 新 PRD 用“修订自”反向链接每一份被改变的旧 PRD。
- 部分修订只改变明确段落，其余旧要求继续有效；索引阶段必须与文档头部状态一致。
- 双向链接由 `make check` 自动验证，不能只在正文或本索引单向提及。
