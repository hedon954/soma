# Soma 迭代日志

本目录依据 2026-07-27 至 2026-07-30 的产品对话、界面反馈和当前实现重建迭代过程。

它与传统版本 Changelog 的区别是：

- 记录产品如何收敛，而不只罗列最终功能；
- 保留重要的撤回与修正，避免将来重复犯同样的问题；
- 日期代表主要决策与实现阶段，不代表已发布到 App Store 的语义化版本。

## 时间线

| 日期 | 阶段 | 摘要 |
| --- | --- | --- |
| [2026-07-27](2026-07-27-foundation-and-chat-first.md) | 从零到可运行 MVP | 私人多模态教练、多健身房、本地数据、聊天优先和基础统计 |
| [2026-07-28](2026-07-28-react-data-and-observability.md) | Agent 与数据可信度 | 原生 ReAct、CRUD、Trace/Span、Skills、流式事件和数据真值 |
| [2026-07-29](2026-07-29-soma-health-and-polish.md) | Soma 当前基线 | 身体信息、热量估算、HealthKit、有序混合媒体、Widget、异步处理和交互打磨 |
| [2026-07-30](2026-07-30-agent-turn-event-cards.md) | Agent 聊天模型修正 | 文字、Skill、Tool 和错误按真实顺序流式追加为 Event Cards |

相关文档：

- [PRD 演进](../prd/README.md)
- [架构决策](../adr/README.md)
- [当前验收清单](../acceptance.md)
