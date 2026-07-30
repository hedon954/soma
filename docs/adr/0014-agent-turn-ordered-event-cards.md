# ADR 0014：Agent Turn 使用有序异构 Event Cards

- 状态：已采纳
- 决策阶段：2026-07-30
- 部分替代：[ADR 0005](0005-trace-span-event-observability.md) 中“最终回复下挂 Skill/Tool 时间线”的聊天呈现方案

## 背景

一个 ReAct Turn 可能依次经历自然语言输出、Skill 加载、工具执行和后续自然语言输出。如果把模型文本保存为一个字符串，再把 Skill/Tool 挂在最终回复下方，系统会丢失真实时序，也无法重放：

```text
文字 → Skill → Tool → 文字 → Tool → 文字
```

这不仅是视觉问题，也会导致前置文字被覆盖、工具执行和解释脱节，以及重新进入聊天后无法恢复执行过程。

## 决策

- 一条 Agent Attempt 对应一条 Trace；同一用户 Turn 可按 ADR 0016 拥有多次 Attempt。每次
  Attempt 仍由多个有序 `AgentTurnItem` 组成。
- Item 类型至少包括 `text`、`skill`、`tool` 和 `error`，它们在聊天中是同级 Event Card。
- 原始流式 Event 进入确定性 reducer，再更新持久化 Turn Item：
  - 同一 `itemID` 的文字 delta 合并进同一张文字卡；
  - Skill/Tool 开始时追加卡片，运行、成功和失败按稳定 Span ID 原地更新；
  - Skill/Tool 之后再次出现文字时，创建新的文字卡，而不是追加到此前文字；
  - Turn 完成只结束运行状态，不生成冗余“完成”卡；
  - Turn 失败保留已完成的卡片，并追加可理解的错误卡。
- `sequence` 只在 Item 首次出现时确定，后续状态更新不得改变顺序。
- 聊天 UI 直接按 Item 顺序渲染并实时追加，不再使用“最终回复 + 下挂执行时间线”。
- 普通聊天展示用户可理解的标题、状态和简要结果；模型入参、完整 Tool 参数、Token、耗时等仍在开发者 Trace 中展示。
- thinking/reasoning 继续不在聊天中展示或持久化。

## 协议分层

```text
Agent runtime
  -> AgentTraceEvent（传输事实）
  -> Agent Turn reducer（确定性归并）
  -> AgentTurnItem[]（聊天持久化与重放）
  -> SwiftUI Event Cards（用户投影）

同一批 Event
  -> AgentTraceSpan[]（开发者诊断投影）
```

传输 Event 与 UI Card 不是一一对应：token delta 不应产生大量卡片，Tool 的 started/succeeded/failed 也应更新同一张卡片。

## 结果

- 用户能按真实顺序看到 Agent 说了什么、加载了什么 Skill、调用了什么工具，以及工具之后如何继续解释。
- 页面切换或重新进入聊天后，Event Cards 仍按原顺序恢复。
- Trace 诊断能力与聊天可读性共享同一事件来源，但保持不同信息密度。
- SwiftUI 列表使用稳定 ID，流式更新只影响目标卡片。

## 未选择的方案

- 最终文字气泡下挂 Skill/Tool 时间线：丢失交错顺序。
- 每个原始 Event 都新增卡片：token 和生命周期事件会造成大量噪声。
- 任务结束后一次性生成展示列表：无法提供实时反馈。
