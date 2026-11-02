# BUG 0066：带练替换动作因计算属性 Predicate 闪退

- 状态：已修复，完整本地门禁通过，真机交互待验收
- 日期：2026-09-19
- 修订自：[BUG 0045](0045-guided-workout-coredata-abort.md)（替换列表必须使用不可变候选）
- 修订自：[BUG 0062](0062-guided-replacement-retains-old-targets.md)（更换动作确认边界）
- 上游依据：[PRD 000](../prd/000-origin-through-0.0.11.md)、[训练领域协议](../engineering/training-domain-model.md)
- 下游落地：[验收](../acceptance.md)

## 症状

准备动作页点「替换动作」后 App 直接退出。0.0.24 (28) 真机 MetricKit 报告为 exception 6、
信号 5（SIGTRAP），发生在打开替换列表时。

## 根因

替换列表用 `#Predicate { !$0.isArchived }` 查询动作库。`isArchived` 是 `archivedAt != nil`
的计算属性，SwiftData Predicate 不能编译它，运行时 abort。这同时绕过了 BUG 0045 已要求的
不可变 DTO 列表。

## 修复

- 替换列表改走 `GuidedWorkoutScreenSnapshotLoader.replacementChoices`，按 `archivedAt == nil`
  投影不可变候选。
- 确认页再按动作 ID 从当前 Context 取一条未归档定义，失败可见、不改训练。
- 准备页展示并允许调整本次分组参数；保存复用现有尚未开始动作的运行时重建。
- 静态门禁禁止替换列表再次使用计算属性 `isArchived`。

## 回归门禁

`GuidedExerciseReplacementTests` 覆盖同动作改目标后重建待练组。
`WorkoutPrescriptionFormatterTests` 覆盖准备页分组投影。
`check-performance-hotpaths.rb` 拒绝 `isArchived` Predicate，并要求 `replacementChoices`
与 `archivedAt == nil`。
交互：点替换看到未归档列表且不闪退；确认或取消后训练可继续。
