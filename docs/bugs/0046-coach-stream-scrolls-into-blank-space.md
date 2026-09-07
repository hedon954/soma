# BUG 0046：教练流式处理滚入空白区域

- 状态：已修复，待 Release 真机长会话复验
- 发现日期：2026-09-02
- 影响范围：发送消息、零 token 等待、首 token、Markdown 流式增长与键盘切换
- 上游依据：维护者截图与复现描述
- 下游落地：
  - [PRD 052](../archive/0.0.19/prd/052-coach-training-and-lifecycle-reliability.md)
  - [ADR 0112](../archive/0.0.19/adr/0112-coach-scroll-and-session-behavior.md)

## 症状

发送消息后 Agent 尚未输出正文，消息列表突然上滑，屏幕主体变成空白；用户必须手动反向滚动才能
找回消息。首次进入还可能停在一条用户消息的起点。

## 根因

零高度 bottom anchor、固定 yield 和多处独立 `scrollTo` 在内容高度尚未稳定时竞争。ScrollView
允许把零高度目标对齐到可视区域后，实际消息尾部可能已在屏幕之外；随后 revision 又继续叠加滚动。

## 修复

- 删除零高度 anchor，以最后一条 AI 消息真实尾部为目标。
- 内容高度/视口测量决定短内容贴顶或长内容 tail-follow；布局 revision 后再执行单一滚动状态机。
- 用户上滑暂停跟随，发送/双击教练恢复；首次进入和切回等待布局后定位最后 AI 尾部。

## 回归门禁

- 自动化：零 token、首 token、完成态替换、短内容、长内容、键盘、主动上滑与初始定位。
- 手工：Release 真机长会话连续发送和流式 Markdown，页面不得出现空白过滚。

## 验证

单元与 Simulator 测试已覆盖状态决策；Release 真机滚动手感待复验。
