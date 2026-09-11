# BUG 0059：调整休息后旧子视图计时仍提前推进

- 状态：定向回归通过，完整门禁与真机待验收
- 发现日期：2026-09-10
- 影响范围：带练休息加减、自动进入下一组与暂停
- 上游依据：[训练领域模型与运行时协议](../engineering/training-domain-model.md)
- 下游落地：[验收](../acceptance.md)

## 症状

点击增加或减少休息后，可见倒计时改变，但训练仍可能在原截止时间进入下一组。

## 根因

`adjustRest` 已正确持久化 `restTargetEndAt`、`phaseDeadlineAt` 并递增
`transitionRevision`。主页面按 revision 与截止时间重建任务，并由 coordinator 再校验。

但 `GuidedRestView` 同时持有另一条仅以目标 effort ID 为 key 的任务。加减休息不改变
effort ID，所以任务继续调用旧视图捕获的 `remainingSeconds`。到零后直接调用 `onFinish`，
绕过 revision 和 active 状态校验。这条路径还可能在暂停期间结束休息。

## 修复

自动推进只由主页面 deadline 任务及 coordinator 的持久状态校验负责。休息子视图只显示
当前时间、播报最后三秒与收集加减/跳过意图。暂停时可见剩余时间冻结，停止倒计时播报；
恢复后由更新的截止时间继续。

锁屏和通知只在 active/resting 状态投影截止时间。每个 Session 的系统写入按顺序完成，
新的更新取消未开始的旧更新，并等待已进入系统调用的旧写入结束后再覆盖；暂停或结束会撤销通知。

## 回归门禁

- `GuidedRestTimingTests.testRestDisplayCannotAdvanceSessionUsingItsCapturedDeadline`：实际挂载
  SwiftUI 休息子视图，旧实现错误触发推进，修复后不得自主推进。
- 同组测试覆盖加时后旧 revision/旧截止时间无效，缩短到零只推进一次，暂停不自动到期且恢复
  保留剩余时间。
- 继续运行 `GuidedWorkoutCoordinatorTests` 与 `GuidedWorkoutLayoutTests`，最后 `make verify`。
- 真机：休息时连续 +15/-15，检查原截止点、更新后的截止点、暂停/恢复和锁屏投影。

## 证据

修复前定向回归实际失败，断言为 `Fulfilled inverted expectation`：子视图越权推进。
暂停/结束仍带锁屏截止时间的新增断言也在修复前实际失败。修复后 `GuidedRestTimingTests`
五项通过，带练 coordinator 36 项通过。局部测试不代表真机交互与完整交付已完成。
