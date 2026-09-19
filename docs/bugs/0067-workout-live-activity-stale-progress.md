# BUG 0067：带练灵动岛和锁屏状态卡进度不更新

- 状态：已修复，完整本地门禁通过，真机锁屏与灵动岛待验收
- 日期：2026-09-19
- 上游依据：[训练领域协议](../engineering/training-domain-model.md)、[验收](../acceptance.md)
- 下游落地：[验收](../acceptance.md)

## 症状

带练进行中，灵动岛和锁屏状态卡停在首次「已完成 0/总组数」，完成组或一侧后数字
与进度条都不动。锁屏呈现被压成搜索条，只有一行进度，没有阶段标题。

## 根因

系统投影只在 SwiftUI `.task(id:)` 里写 ActivityKit；同一阶段下完成一侧时
`ContentState` 可哈希相等，系统丢弃更新。找不到已有 Activity 时再次
`request` 被吞掉，旧活动停在初始 0。锁屏只提供稀疏中等布局，没有 small
family，iOS 26/27 把它收成搜索条。

## 修复

快照刷新后立即投影；进度分数计入一侧完成；每次写入递增 `updateSequence`
并复用已有 Activity。锁屏改为带标题和进度条的状态卡，并适配 small family。

## 回归门禁

- 自动化：`WorkoutSystemProjectionTests` 覆盖旧 ContentState 解码、休息倒计时
  边界，以及一侧完成时分数前进、组数仍为 0。
- 手工：真机带练完成至少两组和一侧，确认灵动岛与锁屏数字/进度条同步，卡片
  不再是搜索条。
- 仍无法自动化：ActivityKit 宿主、锁屏搜索槽和灵动岛横竖屏由系统绘制。

## 验证

`make format`、`make check` 与 `make verify` 通过：860 XCTest、8 Swift Testing，含
`WorkoutSystemProjectionTests` 3 项。真机锁屏与灵动岛仍需装新包后手工确认。
