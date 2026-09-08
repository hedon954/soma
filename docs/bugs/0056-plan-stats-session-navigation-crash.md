# BUG 0056：计划训练统计点击复盘导致 App 崩溃

- 状态：已修复
- 发现日期：2026-09-08
- 影响范围：训练计划详情「训练统计」里的历史 Session 行
- 上游依据：维护者复现：点击计划内训练记录后进程退出
- 下游落地：[PRD 059](../prd/059-coach-ids-progress-and-required-zeros.md)

## 症状

在计划详情展开训练统计后点击某次完成记录，App 直接崩溃，进不了复盘页。

## 根因

`NavigationLink` 包着活的 SwiftData `WorkoutSession`，又放在 `List` + `DisclosureGroup`
里。展开统计会改写 snapshot，链接目的地拿到已销毁的模型实例。

## 修复

按 Session ID 导航；统计行改为 Button + `navigationDestination(item:)`。物化字典改为
遇重复 ID 保留首个，避免 `uniqueKeysWithValues` 致命错误。

## 回归门禁

- 手工：打开有完成记录的计划 → 训练统计 → 点击最近一次，应进入复盘。
- 自动化：本崩溃依赖 SwiftUI 运行时，不单测 NavigationLink。

## 验证

计划详情改用 ID 目的地后编译通过。真机点进复盘由维护者确认。
