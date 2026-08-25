# Soma 0.0.5 归档摘要

本目录保存已滑出最近 3 个营销版本窗口的原始 PRD/ADR。Agent 默认不读取；
只有维护者明确要求历史时才打开原始文件。

## 产品要求摘要

- PRD 026：带练记录投影、录像失败可见性与会话入口恢复
- PRD 027：可靠高效 ReAct 与原位审查闭环
- PRD 028：重试活动执行预算

## 架构决策摘要

- ADR 0060：带练动作终态物化为训练记录并组成计划执行
- ADR 0061：会话抽屉同时保留可见时间按钮与边缘手势
- ADR 0062：明确欠费使用人工恢复屏障与严格 FIFO 队列
- ADR 0063：step 续跑复用同一气泡、固定 Loop 时间并采用分层截止时间
- ADR 0064：精确结构化快捷输入直写本地，最新回复提供原位审查
- ADR 0065：Tool 按副作用意图暴露，Prompt 使用版本化稳定前缀
- ADR 0066：静默动作目录维持至少一百个专属动作图
- ADR 0067：固定业务时间与活动执行预算解耦

## 原始文件

- [PRD 026：带练记录投影、录像失败可见性与会话入口恢复](prd/026-guided-workout-record-projection-camera-failures-and-session-entry.md)
- [PRD 027：可靠高效 ReAct 与原位审查闭环](prd/027-reliable-efficient-react-and-in-context-review.md)
- [PRD 028：重试活动执行预算](prd/028-retry-active-runtime-budget.md)
- [ADR 0060：带练动作终态物化为训练记录并组成计划执行](adr/0060-guided-performance-workout-entry-projection.md)
- [ADR 0061：会话抽屉同时保留可见时间按钮与边缘手势](adr/0061-discoverable-conversation-session-entry.md)
- [ADR 0062：明确欠费使用人工恢复屏障与严格 FIFO 队列](adr/0062-user-resumed-llm-interruption-barrier.md)
- [ADR 0063：step 续跑复用同一气泡、固定 Loop 时间并采用分层截止时间](adr/0063-step-resume-fixed-loop-time-and-deadline-hierarchy.md)
- [ADR 0064：精确结构化快捷输入直写本地，最新回复提供原位审查](adr/0064-deterministic-quick-write-and-latest-inline-review.md)
- [ADR 0065：Tool 按副作用意图暴露，Prompt 使用版本化稳定前缀](adr/0065-intent-scoped-tools-and-prefix-stable-prompts.md)
- [ADR 0066：静默动作目录维持至少一百个专属动作图](adr/0066-bundled-action-illustration-coverage.md)
- [ADR 0067：固定业务时间与活动执行预算解耦](adr/0067-separate-business-time-and-active-loop-budget.md)
