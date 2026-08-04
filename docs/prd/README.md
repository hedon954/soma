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
| [008：连续对话、逐组训练与自适应模型](008-coach-continuity-and-adaptive-models.md) | 体验精化 | 隐藏式可继续 Session、一次性位置确认、逐组训练、媒体上下文、长会话压缩与双档模型 |
| [009：记录媒体归档与单张解绑](009-record-media-association-and-detachment.md) | 媒体审查 | 健身房跨轮照片归档，以及健身房、训练、饮食和身体记录的单张媒体解绑 |
| [010：动作库、训练计划、带练与视频复盘](010-exercise-library-plans-guided-training.md) | 部分修订 | 稳定动作身份、最近值快捷输入、版本化计划、逐组带练和自动录像；计划与带练体验由 012/013 扩展 |
| [011：持久 Agent Job 与远程持续执行](011-durable-agent-jobs-remote-continuity.md) | 已实现 | 本地 Outbox、服务端 Job/Event、设备 Tool handoff、灵动岛和通知 |
| [012：GUI 训练计划编排](012-gui-training-program-authoring.md) | 部分修订 | 从动作库选择、排序并配置处方；折叠处方和最近值由 013 扩展 |
| [013：低摩擦计划与沉浸式带练](013-guided-workout-experience-and-capture.md) | 部分修订 | 动作图编排、显式最近值、聚焦逐组带练和横竖屏真实取景；相机触发与反馈由 014 修订 |
| [014：按需录像、完整语音与完成复盘](014-guided-workout-recording-cues-and-review.md) | 已实现，待真机验收 | 单组/每组/手动录像、按需相机、事件语音、本地总结和历史删除 |
| [015：对话启动计划带练](015-agent-guided-workout-launch.md) | 已实现，待真机验收 | Agent 查询可执行计划并在本机启动确定性带练 |
| [016：训练成为一级执行入口](016-training-primary-tab.md) | 已实现，待真机验收 | 训练计划与带练从进展迁移为一级训练 Tab |

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
