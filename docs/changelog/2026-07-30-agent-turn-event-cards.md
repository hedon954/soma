# 2026-07-30：Agent Turn 有序 Event Cards

## 问题修正

此前聊天把模型文字合并为一个最终气泡，再把 Tool/Skill 放进回复下方的时间线。这个结构无法表达真实的 ReAct 顺序，还可能在工具开始时覆盖模型已经输出的前置文字。

## 新交互

- 一次 Agent Turn 由多张同级卡片组成。
- 自然语言、Skill、Tool 和错误按真实发生顺序流式追加。
- 连续 token 合并到同一张文字卡，不为每个 delta 生成卡片。
- Tool/Skill 从运行到成功或失败都更新同一张卡片。
- Tool/Skill 之后的模型输出创建新的文字卡。
- 已完成卡片持续保留，重新进入聊天仍能审查。
- 主聊天只显示简要结果；完整参数、Token、耗时和错误上下文继续留在开发者 Trace。

## 工程调整

- 新增 `AgentTurnItem` 持久化模型与确定性 reducer。
- `assistantTextDelta` 增加稳定 Item ID，并增加文字段完成事件。
- 聊天 UI 改为基于稳定 ID 的 SwiftUI Event Cards。
- 演示空间内置一条完整的文字、Skill、Tool、文字示例 Turn。
- 增加交错顺序、delta 合并、失败卡片和流式事件顺序测试。
- ADR 0014 部分替代 ADR 0005 的“最终回复下挂时间线”方案。
