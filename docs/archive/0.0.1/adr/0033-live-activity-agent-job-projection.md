# ADR 0033：Live Activity 只投影 Agent Job 的隐私安全状态

- 状态：已采纳
- 日期：2026-07-31
- 维护者：Soma maintainers
- 部分替代：无
- 后续替代：暂无
- 上游依据：[持久 Agent Job、事件流与 Live Activities 调研](../../../research/2026-07-31-durable-agent-jobs-live-activities.md)
- 下游落地：[Agent Job 与远程执行协议](../../../engineering/agent-job-protocol.md)
- 关联：[PRD 011](../prd/011-durable-agent-jobs-remote-continuity.md)

## 背景

长 Agent 任务离开聊天后需要可见状态。Live Activity 能在锁屏和灵动岛展示持续活动，但它
不是后台执行器；内容还可能在锁屏上被旁人看到。

## 决策

1. Live Activity 是 `AgentJob` Event Log 的只读投影，不拥有任务状态和业务数据。
2. 只有用户开启“锁屏和灵动岛显示 Agent 任务”且任务预计较长时启动。
3. 普通短文本默认只在 App 内显示，避免频繁闪现。
4. 一个当前 Job 对应一个 Live Activity；未来队列只显示运行数和等待数，不为每条消息并发
   创建活动。
5. 锁屏和紧凑态只显示通用阶段、操作数、队列数和完成/失败/等待，不显示动作、重量、饮食、
   身体数据、用户原文或媒体摘要。
6. 不显示百分比。ReAct 的最大轮数不能转换为可靠完成度。
7. 本地后台租约到期后立即投影“等待返回 Soma 继续”，不能保持虚假运行动画。
8. 远程 Job 使用 ActivityKit push token 由服务器更新和结束；push payload 只包含渲染所需的
   通用状态。
9. `staleDate` 到期或推送丢失时，Activity 明确显示状态可能过期；App 打开后以 Event cursor
   同步纠正。
10. Live Activity 关闭、设备不支持、推送权限缺失或 token 失效不影响 Job 执行。
11. 点击活动深链到对应 Turn。第一版不在锁屏直接执行敏感 Tool 或业务 mutation。

## 未选择的方案

- 把 Live Activity 当作 Worker：不会获得额外后台执行时间。
- 展示每个模型 token 或内部 Span：高频、嘈杂且泄露实现细节。
- 展示用户具体训练或身体内容：锁屏隐私风险高。
- 用八轮上限计算进度百分比：剩余轮数未知，会误导用户。
- 为所有短消息启动：体验闪烁且容易被用户整体关闭。

## 结果

### 正向影响

- 用户离开聊天后仍知道任务处于运行、等待设备还是完成。
- 本地和远程执行共享相同投影模型。
- 锁屏默认内容不泄露健康事实。

### 成本与限制

- 远程更新需要 APNs Provider、ActivityKit token 生命周期和推送预算。
- 推送不保证到达，因此 Event Log 与 App 同步仍是最终事实。
- 没有灵动岛的设备只显示系统支持的锁屏等表面。

## 验证

- Job 每个终态、等待态和恢复态映射为唯一 ContentState。
- 本地租约到期后不再显示“正在处理”。
- ActivityKit push 丢失、乱序、重复和终态后迟到均不会回退状态。
- 锁屏快照、通知 payload 和日志中没有健康文本或媒体内容。
- 用户关闭活动、系统禁用频繁更新和 token 轮换时正常降级。
- 点击活动准确打开对应 Session/Turn。

## 参考

- [PRD 011](../prd/011-durable-agent-jobs-remote-continuity.md)
- [ActivityKit](https://developer.apple.com/documentation/activitykit/)
- [Starting and updating Live Activities with push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- [Human Interface Guidelines: Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)
