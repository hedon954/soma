# BUG 0017：长时间等待后手动重试立即显示已取消

- 状态：已修复，待维护者真机确认
- 发现日期：2026-08-14
- 影响范围：ReAct step 恢复、欠费人工屏障、聊天错误投影和 FIFO 队列
- 上游依据：无
- 下游落地：
  - [PRD 028](../archive/0.0.5/prd/028-retry-active-runtime-budget.md)
  - [ADR 0067](../archive/0.0.5/adr/0067-separate-business-time-and-active-loop-budget.md)

## 症状

Agent 已成功保存训练记录但后续 step 中断。用户隔几分钟点击“重试”时，界面立即再次显示
“执行失败／已取消”；无论点击多少次都不恢复，后发消息持续显示等待队首处理。

## 根因

整轮剩余预算使用 `当前时间 - loopStartedAt`，而 `loopStartedAt` 又必须跨人工重试保持固定。
纯文本等待超过三分钟后，剩余预算永久成为 0.01 秒。deadline 取消子任务时，内部
`CancellationError` 先写入“已取消”，外层真正的 loop timeout 因已有 error item 而未覆盖。

## 修复

- 固定业务时间与活动执行计时拆分；只有 `running` 区间消耗预算。
- 自动恢复保留累计时长，用户显式重试重置活动预算但保留检查点、业务时间与成功写入。
- 外层 timeout 持久化真实失败并替换临时取消；完成 Event 清除旧失败投影。
- 新增字段为带默认值的 SwiftData 轻量迁移，不修改 PostgreSQL 结构。

## 回归门禁

- 自动化测试：`AgentJobTests`、`AgentReliabilityTests`。
- 手工验收：使用虚构 Provider 先产生可恢复失败，等待超过三分钟后重试；确认不会立即取消、
  训练卡保留且队尾消息在队首结束后继续。
- 仍无法自动化的风险：iOS 前后台租约终止的准确时机需要真机观察。

## 验证

- `make check` 与 `make verify` 必须通过；真机验收不使用真实身体数据或媒体。
