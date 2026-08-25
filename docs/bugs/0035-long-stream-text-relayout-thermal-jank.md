# BUG 0035：长流式回复重复排版导致持续卡顿与发热

- 状态：首次修复不足，后续见 [BUG 0036](0036-long-stream-continuous-text-and-completion-cliff.md)
- 日期：2026-08-25
- 影响：教练页长时间流式后持续占用主线程，滚动、Session 与 Tab 交互逐渐变卡，设备可能发热
- 上游依据：用户真机反馈与 iPhone 17 Pro Max Release Time Profiler
- 后续修订：[BUG 0036](0036-long-stream-continuous-text-and-completion-cliff.md)

## 症状

流式刚开始时基本正常，正文持续增长后教练页越来越卡；随后切 Session 或切 Tab 也会感到延迟。
这容易被误判为切换时重新读取数据库，但同场景的真机采样没有把 SwiftData 指向主要热点。

## 根因

流式 Event 已经约 5 Hz 合批，但每次更新仍把越来越长的历史正文放在一个立即布局的内层
`VStack` 中。SwiftUI 因尾部变化重新测量已经冻结的全部文本块，CoreText/
`NSOptimalLineBreaker` 反复执行断行，`LazyHVStack.measureEstimates` 同时扩大布局工作量。

修复前同一 35 秒虚构长流 Release 场景消耗 `6.047 s` CPU，其中主线程 `6.004 s`；流式 5 秒
后的持续负载约为单核 `16.885%`，15 秒后仍为 `17.053%`，证明成本没有随稳定块冻结而收敛。

## 修复

- 正文继续使用稳定块与可变尾块，但可变尾块目标从 768 字符收紧到 256 字符。
- 流式正文块使用 `LazyVStack`；离屏稳定块不再参与每次尾部更新的立即测量。
- 每块 `Text` 固定纵向理想尺寸，避免外层宽度确定后重复探索高度。
- 完整正文仍只在流式结束时合并并持久化；不丢弃历史内容，也不建立 SwiftData 对象缓存。

## 回归门禁

- 单元测试持续追加 200 个段落，要求形成多个稳定块，且可变尾块始终小于默认 256 字符目标。
- `make perf-check` 要求流式正文保持 `LazyVStack`、纵向 `fixedSize` 和 256 字符尾块，避免回退到
  整段即时布局。
- 修复后同一真机 Release 场景的总 CPU 为 `0.998 s`、主线程 `0.950 s`，分别下降
  `83.5%` 与 `84.2%`；流式 5 秒后主线程单核占用从 `16.785%` 降到 `2.643%`。
- 独立 35 秒 Animation Hitches 录制为 0 个 actual hitch、0 个 `>33 ms` 潜在交互延迟，设备
  热状态全程 `Nominal`。
- 最终仍需在用户真实 Session 中确认向上阅读、切换 Session、切 Tab 与长按重命名手感。
