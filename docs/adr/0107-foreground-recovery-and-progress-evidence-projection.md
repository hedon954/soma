# ADR 0107：前台恢复与进展证据投影

- 状态：已采纳，已实施；待 Release 真机量化复验
- 日期：2026-08-27
- 维护者：Soma maintainers
- 部分替代：[ADR 0103](0103-goal-directed-progress-energy-and-hypertrophy.md) 的集中说明入口与仅展示截至当前总消耗
- 后续替代：[ADR 0108](0108-contextual-progress-disclosure-and-reviewable-meal-order.md) 的跟随式进展明细与目标直选
- 上游依据：
  - [PRD 049](../prd/049-foreground-responsiveness-and-readable-monthly-progress.md)
  - [BUG 0043](../bugs/0043-coach-foreground-recovery-main-thread-stall.md)
- 下游落地：[验收矩阵](../acceptance.md)

## 背景

Scene 进入 active 时同时解析 Session、扫描 Job 状态并触发 SwiftData 保存，会把前台生命周期事件
放大为教练树的查询、观察失效和布局工作。进展数据则需要在保持有界查询与缺失值真值的前提下，
提供可读的月度变化和单项证据。

## 决策

1. App 启动时解析入口 Session；后台回前台只恢复可能挂起的 FIFO 队首 Job，不重新选择 Session。
   发送前继续执行跨日 Session 门禁。前台恢复以独立匿名 signpost 量化。
2. 训练、饮食和身体记录在独立 ModelActor 内读取有界时间窗并投影为不可变 30 天 DTO；SwiftUI 只
   绘制 DTO 和选中点，不在 `body` 查询或聚合 SwiftData 模型。
3. 来源说明按指标分散：每个按钮把组成该指标的实际记录、HealthKit 来源或公式项投影为“名称 +
   数值”的账单行；外层负责总计，Sheet 不重复合计。公式按“原始公式 → 用户当前事实代入式”两行
   补充，不提供集中长文或泛化口径说明。
4. 全天总消耗投影不猜活动等级：HealthKit 路径用 `(截至当前静息 + 截至当前活动) ÷ 已过比例`；
   本地路径用 `24h Mifflin 静息 + 截至当前活动 ÷ 已过比例`。任一必要事实未知则不产生结果。

## 未选择的方案

- 不在回前台时重选当天 Session；该行为没有用户价值并扩大可见树失效。
- 不把 SwiftData 模型跨 `ModelContext` 缓存，也不在图表 `body` 做全表聚合。
- 不用固定活动系数计算 TDEE；用户没有提供活动等级，固定系数会伪造事实。
- 不保留一张包含全部指标的长说明页；查一个来源不应阅读其他指标。

## 结果

### 正向影响

- 前台首个交互与会话上下文不再被 Session 解析打断；月度趋势和来源可直接审查。

### 成本与限制

- 当天外推假设余下时间维持当前活动节奏，越早查看波动越大，因此只标为预估，不作为目标。
- HealthKit、身体资料或活动事实缺失时，全天总消耗仍可能为空。

## 验证

- 确定性公式/时间窗测试、`make perf-check`、`make verify`、模拟器视觉检查与 Release 真机
  `foreground_recovery`/Hangs 采样共同验证。

## 参考

- [Apple：Understanding hangs in your app](https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app)
- [Apple：Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)
- [SwiftData `FetchDescriptor.fetchLimit`](https://developer.apple.com/documentation/swiftdata/fetchdescriptor/fetchlimit)
