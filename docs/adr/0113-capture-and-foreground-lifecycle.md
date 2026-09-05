# ADR 0113：快捷相机与前台恢复生命周期

- 状态：已采纳，代码已实施；待 Release 真机量化验收
- 日期：2026-09-02
- 维护者：Soma maintainers
- 部分替代：[ADR 0000](0000-origin-through-0.0.11.md) 的前台恢复执行顺序
- 后续替代：暂无
- 上游依据：
  - [PRD 052](../prd/052-coach-training-and-lifecycle-reliability.md)
  - [BUG 0045](../bugs/0045-guided-workout-coredata-abort.md)
  - [BUG 0049](../bugs/0049-quick-camera-presentation-deadlock.md)
  - [BUG 0050](../bugs/0050-coach-foreground-recovery-freezes-again.md)

## 背景

快捷入口依赖 Tab、外层 Sheet 和相机 Sheet 连续竞争展示，取消只关闭内层 Picker；前台恢复则把
备份、网络撤销、Job 查询和长会话布局塞进首个主线程周期。带练崩溃报告还显示 SwiftData/CoreData
路径中的 abort，说明跨异步边界持有模型对象存在高风险。

## 决策

- 所有快捷媒体入口归一为 `soma://capture/<mode>`。根层 `CapturePresentationCoordinator` 持有
  `queued → waitingForActiveScene → presenting → completed/cancelled/failed` 状态，并用一个
  顶层 `fullScreenCover` 展示相机。后台或锁屏结束当前请求，恢复后不自动重开。
- 前台恢复由 generation 协调器所有；Scene active 后先取消自动备份，等待一次真实显示帧，再恢复
  Job。独立 ModelActor 只返回 FIFO 稳定 ID，主线程重新 fetch；远程撤销和网络等待在首帧之后执行。
- 内存警告保留当前 Session 有界不可变渲染 DTO，不缓存 SwiftData 对象。Scene 再次变化取消旧
  generation。
- 带练异步边界只传稳定 ID；状态写入、重新 fetch、rollback 和删除集中在当前 MainActor
  `ModelContext`，退出/删除前先取消计时、录像、投影和保存任务。

## 未选择的方案

- 不用单次 `Task.yield()` 猜展示层级，也不嵌套相机 Sheet。
- 不尝试用外围 `do/catch` 捕获进程级 `SIGABRT`，无匹配 dSYM 时不虚构业务栈。
- 不跨 Context 缓存或传递 `@Model` 实例。

## 结果

相机请求有明确终态，前台可交互区间与恢复工作分离；成本是必须用 Release 真机覆盖权限、锁屏、
相机设备和真实长会话性能，Simulator 不能关闭门禁。

## 验证

- 相机状态机、重复 URL、Scene 切换、单次交付、前台 generation、渲染缓存成本与 FIFO ID 测试。
- Release 真机桌面/锁屏各 10 次；长会话 Home/锁屏各 5 次，warm p95 `<100ms` 且无 Hangs。
