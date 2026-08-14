# PRD 028：重试活动执行预算

- 状态：已采纳，已实施；待维护者真机验收
- 日期：2026-08-14
- 修订自：
  - [PRD 004](004-soma-current-product.md) 的 Agent 重试与超时基线
  - [PRD 027](027-reliable-efficient-react-and-in-context-review.md) 的整轮预算起算与手动重试边界
- 下游落地：[ADR 0067](../adr/0067-separate-business-time-and-active-loop-budget.md)
- 上游依据：[BUG 0017](../bugs/0017-manual-retry-immediately-cancelled.md)

## 背景

固定 `loopStartedAt` 同时被用于业务记录时间和整轮墙钟超时。欠费进入 `waitingForUser` 后，用户
隔几分钟再重试，等待时间已经耗尽纯文本三分钟预算；每次重试只获得 0.01 秒并立即取消。底层
取消 Event 又先于外层 timeout 投影，界面持续显示“已取消”，后发消息则一直被 FIFO 队首阻塞。

## 用户结果

1. 同一 ReAct Loop 的业务写入继续复用首次执行时间；跨午夜、时区格式化与检查点语义不变。
2. 3/5/10 分钟只累计 Job 处于实际本地 `running` 的时间；`waitingForUser`、`staged`、
   `waitingForNetwork`、`waitingForForeground` 和 `waitingForDevice` 的等待不计入。
3. 自动恢复继续扣除当前执行窗口已经消耗的时间，避免网络抖动无限延长无人值守执行。
4. 用户显式重试为首个未完成 step 开启新的 3/5/10 分钟执行窗口；已成功 step、Tool 幂等回执、
   `responseMessageID`、`loopStartedAt` 和业务记录均不重置。
5. timeout 触发底层取消后，外层可解释失败必须覆盖临时“已取消”投影；成功重试也必须清除旧错误，
   包括从持久 Event 重放聊天时。

## 验收边界

- 首次执行 35 秒后等待用户一小时，再手动重试：业务时间不变，执行预算恢复完整值。
- 自动等待一小时后恢复：等待时间不计入，但此前 35 秒仍从预算扣除。
- timeout 的最终卡片显示实际超时原因而非“已取消”；成功重试后不残留错误卡。
- 队首成功或被删除后，后发暂存消息仍按 FIFO 执行。
- `make verify` 通过；真机使用虚构输入确认重试、错误覆盖和队列推进。

## 非目标

- 不重跑已成功的 LLM/Tool step，不改变业务记录时间，也不放宽首增量门禁。
- 不取消总预算；每个用户授权的执行窗口仍受 3/5/10 分钟限制。
- 不改变远程 Server Job 的独立执行时限或身体业务数据本地事实边界。
