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

## 阅读约定

- “当前要求”表示仍然有效，并应由当前实现持续满足。
- “被替代”表示曾经实现或讨论过，但已被后续决策取代。
- 产品验收证据集中在 [验收清单](../acceptance.md)。
- 技术与交互取舍集中在 [ADR](../adr/README.md)。
- 按日期重建的变更记录集中在 [Changelog](../changelog/README.md)。
