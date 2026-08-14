# ADR 0067：固定业务时间与活动执行预算解耦

- 状态：已采纳
- 日期：2026-08-14
- 维护者：Soma maintainers
- 部分替代：[ADR 0063](0063-step-resume-fixed-loop-time-and-deadline-hierarchy.md) 中从 `loopStartedAt` 连续计算墙钟预算且手动重试不重置的边界
- 后续替代：暂无
- 上游依据：
  - [PRD 028](../prd/028-retry-active-runtime-budget.md)
  - [BUG 0017](../bugs/0017-manual-retry-immediately-cancelled.md)

## 背景

`loopStartedAt` 是可信业务时间，但人工处理欠费、网络恢复和系统挂起都可能持续数小时。把这些
等待算进 3/5/10 分钟预算，会让恢复请求在 0.01 秒后被立即取消，且任何后续手动重试都无法
离开失败状态。时间真值和资源治理因此不能继续共用一个时钟。

## 决策

1. `loopStartedAt` 只承担固定业务时间和可信上下文职责，后续 step 与重试均不修改。
2. `AgentJob` 持久化累计活动时长和当前活动区间起点；进入本地 `running` 开始计时，离开时暂停。
3. 自动恢复保留已消耗活动时长；用户显式重试把活动时长归零，为未完成 step 开启新的总预算。
4. 已完成检查点、Tool 幂等回执、业务写入和同一回复气泡均不因预算刷新而重置。
5. App 异常退出后的遗留活动区间最多累计到执行租约结束，不把离线时间计入。
6. 外层 timeout 结论必须以持久失败 Event 覆盖结构化取消产生的临时 Event；完成 Event 清理旧失败
   投影，确保实时界面与重放结果一致。

## 未选择的方案

- 不再使用 `loopStartedAt` 直接减当前墙钟；它会把人工等待永久变成不可恢复超时。
- 不在每次自动网络恢复时重置预算；无人值守失败不应无限延长资源消耗。
- 不丢弃旧 Job 新建完整 Loop；这会重复成功 step、Token 和潜在 Tool 副作用。

## 结果

### 正向影响

- 欠费解除后即使相隔数小时，用户仍能从失败 step 继续，后发消息随后按 FIFO 推进。
- 业务日期稳定与资源时限各自拥有明确事实源。
- timeout 和成功重试不再残留误导性的“已取消”卡片。

### 成本与限制

- `AgentJob` 增加两个有默认值的 SwiftData 字段；旧数据使用轻量迁移得到零时长和空活动起点。
- 用户每次显式重试都获得新预算窗口，因此总资源消耗可能跨多次用户授权累积，但每个窗口仍有界。

## 验证

- `AgentJobTests` 覆盖人工等待重置、自动等待暂停与冻结业务时间。
- `AgentReliabilityTests` 覆盖取消被真实失败替换，以及成功完成清除旧错误。
- `make verify`；真机使用虚构输入复验长时间等待后的重试和 FIFO。

## 参考

- [PRD 028](../prd/028-retry-active-runtime-budget.md)
- [BUG 0017](../bugs/0017-manual-retry-immediately-cancelled.md)
