# ADR 0062：明确欠费使用人工恢复屏障与严格 FIFO 队列

- 状态：已采纳
- 日期：2026-08-13
- 维护者：Soma maintainers
- 部分替代：[ADR 0045](0045-llm-outage-staging-and-compensating-drain.md) 中所有可恢复失效都在前台或配置变化后自动补偿的边界
- 上游依据：[PRD 027](../prd/027-reliable-efficient-react-and-in-context-review.md)
- 下游落地：[Agent Job 与远程执行协议](../engineering/agent-job-protocol.md)

## 背景

额度耗尽和普通网络抖动具有不同恢复条件。前者在用户充值或更换配置前必然持续失败；自动恢复会
在每次进 App 时制造请求、失败和噪音。若后发消息能越过它执行，又会使聊天与业务写入错序。

## 决策

1. `insufficient_quota`、billing、payment、credit balance 等明确信号进入持久
   `waitingForUser`；通用 429 不据此推断欠费。
2. `waitingForUser` 是非终态但不可运行的队首屏障。队首未释放时，后续消息只进入 `staged`，
   `claimNext` 不得跳过。
3. App 前台、重启、定时器与配置变化都不释放欠费屏障；只有用户明确重试或删除屏障消息可以
   释放。配置变化只可能唤醒普通 `staged` Job。
4. 用户从按 `createdAt` 排列的暂存列表审查待处理消息，可单删暂存 Turn 或清空暂存队列。
   删除同时清理该 Turn 的 Job/Event/Trace/消息与私有媒体，再从新队首继续。
5. “按顺序重试全部”只负责把当前待处理状态统一释放为 `queued`；实际领取仍由 `claimNext`
   严格 FIFO 串行完成，不为批量操作新增并行执行路径。
6. 暂存管理中的 LLM 配置入口读取共享 `AIService`，不复制凭据或建立第二套持久配置。
7. 普通网络、认证、服务端与通用限流仍沿用 ADR 0045 的可恢复暂存。

## 未选择的方案

- 不把所有 429 都视为欠费，避免普通限流被永久卡住；也不让后发消息绕过屏障破坏顺序。

## 结果

### 正向影响

- 不再以“进入 App”代表用户愿意为欠费请求继续消耗资源。
- 队列吞吐受最早屏障约束，但顺序和用户意图比并行越过更重要。

### 成本与限制

- 错误分类必须保留响应 code 与描述，同时不得记录 Authorization 或密钥。

## 验证

- `LLMOutageStagingTests` 覆盖欠费分类、跨前台不释放、严格 FIFO、按顺序重试全部、单删与全清；
  `LLMConfigurationTests` 覆盖不同设置入口读取同一配置事实。

## 参考

- [PRD 027](../prd/027-reliable-efficient-react-and-in-context-review.md)
