# BUG 0045：带练 SwiftData/CoreData abort

- 状态：第二轮修复完成，待新 Release 真机复验
- 发现日期：2026-09-02
- 影响范围：带练阶段切换、保存、恢复、退出与删除
- 上游依据：维护者提供的三份 0.0.18 (22) MetricKit 崩溃报告
- 下游落地：
  - [PRD 052](../archive/0.0.19/prd/052-coach-training-and-lifecycle-reliability.md)
  - [ADR 0113](../archive/0.0.19/adr/0113-capture-and-foreground-lifecycle.md)

## 症状

带练进行中 App 直接退出。三份报告均为 iOS 26.3.1、Soma 0.0.18 (22) 的 `SIGABRT`。
本机保留的 Release dSYM slice UUID 与三份报告完全匹配；符号化后三次栈完全一致。

## 根因

CoreData 在 `NSSQLGenerator` 生成查询时抛出 Objective-C 异常并最终 abort。业务触发点精确位于
旧 `GuidedWorkoutView.swift:182`：页面读取 `allEfforts` 时执行
`workoutSet → performance → sessionID` 多层 relationship `@Query`。第一轮只把写入集中到
MainActor，未移除这条渲染查询，因此真机仍会崩溃。`SIGABRT` 不能由外围 `do/catch` 捕获。

## 修复

- `GuidedWorkoutView` 只接收 `sessionID`；画面和子视图只渲染不可变
  `GuidedWorkoutScreenSnapshot`，不再持有 Session/Performance/Set/Effort 模型或 relationship
  `@Query`。
- 快照在独立读取 Context 中按 `sessionID → performanceID → workoutSetID` 做单层标量查询；事务
  完成后按 generation 刷新，失败时保留最后成功画面并提供重试/退出。
- 动作替换列表同样投影为不可变 DTO；阶段操作、投影和删除只传稳定 ID，并在 MainActor 当前
  Context 重新 fetch。
- `GuidedWorkoutRecordStore` 按标量 ID 获取 Session、Performance、Set 与 Effort，并拒绝
  performance/session 不匹配的调用。
- 删除或退出前取消计时、录像、投影和保存；真正可抛出的保存错误 rollback 并提示重试/退出。
- 阶段切换、保存、恢复、投影和删除记录隐私安全 breadcrumb；未完成训练支持系统左滑删除。

## 回归门禁

- 自动化：真实磁盘临时 `ModelContainer` 验证多 Session、左右 effort、不可变刷新、动作选择 DTO
  与 performance/session 标量 ID 防串写。
- 静态门禁：带练和复盘热路径不得重新出现跨 relationship predicate。
- 手工：新 Release 真机至少十次进入/恢复，覆盖完成、暂停、Home、锁屏、强退恢复、复盘与删除；
  导出崩溃日志确认不再出现 `NSSQLGenerator`/`GuidedWorkoutView` abort。

## 验证

匹配 dSYM 的旧崩溃已完成符号化；第二轮 Simulator 单元/集成与静态门禁完成后再记录具体命令
结果。新 Release 真机十轮与崩溃日志尚未完成，状态不得标为完全修复。
