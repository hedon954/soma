# ADR 0125：已加载聊天页即时排版

- 状态：已采纳
- 日期：2026-09-08
- 维护者：Soma maintainers
- 上游依据：
  - [PRD 000](../prd/000-origin-through-0.0.11.md)
  - [BUG 0055](../bugs/0055-coach-history-scroll-repositions.md)
- 部分替代：
  - [ADR 0000](0000-origin-through-0.0.11.md) 仅消息列表懒栈与
    `defaultScrollAnchor` alignment；尾随、双击回尾和 Session 日期标题不变
- 后续替代：暂无
- 后续修订：[PRD 059](../prd/059-coach-ids-progress-and-required-zeros.md)（已排版页不再用渲染缓存过滤助手消息）
- 下游落地：[验收](../acceptance.md)

## 背景

满页后用 `LazyVStack` 省离屏测量，但滑动会卸载气泡。原位记录卡丢掉 `@State` 后以空占位
重挂再撑开，视口持续重定位。用户要求：除分页查询外，已经拿到的消息滑动时必须是静态的；
同时又不能回到大会话主线程卡死。

## 决策

- 当前 `messageLimit` 窗口用即时 `VStack` 一次排版。首次 30 条，到顶再加 30 条。
- 一页的记录卡和完成态 Markdown 先写入常驻缓存再进入列表。命中后第一帧就是终态，
  切 Tab、切 Session 不重跑 `.task`，也不从 1pt 占位再撑开。
- 只有尚未画过的引用才在分页准备里查找；`body` 不同步扫库。流式中的最后一条才允许
  延迟补卡。
- 内存警告按最近使用裁剪，不按当前 Session 清空，也不清空已完成正文缓存。
- 程序化滚动只用于首次贴底、发送/流式跟随、分页恢复、切回教练和双击回尾。
  打开 Session 等当前页画完、最后一条进入列表并量到高度后，才滚到该条末尾；
  空查询或未画完的「装得下」不能结束首次定位。
- 「加载更早」不得用即时栈的 `onAppear`。

## 未选择的方案

- 继续 `LazyVStack` 只改估计高度：SwiftUI 不能给异构气泡稳定估计，滚回来仍会卸状态。
- 取消分页、一次渲染全部消息：与 BUG 0034/0050 的大会话成本冲突。
- 在 `body` 里同步查出所有记录：首帧会卡死。
- 切 Session 或内存警告清空渲染缓存：回来又要重画，视口再跳。
- iOS 17 用 GeometryReader 探测到顶：滚动偏移每帧变化，会持续失效哨兵。旧系统改点按钮加载。

## 结果

### 正向影响

- 已加载页滑动时高度稳定，阅读不再被拽走。
- 热路径仍有分页上限、Equatable 气泡和延迟查库。

### 成本与限制

- 已加载窗口常驻内存；用户连续到顶多次后，窗口变大，成本按页递增而不是按滑动递增。
- iOS 17 到顶自动分页弱于 iOS 18，需点「加载更早」。

## 验证

`make perf-check` 与 `make verify`。真机上滑、打开 Session 贴底，并往返 Session／Tab。

## 参考

- [BUG 0034](../bugs/0034-large-session-inline-editor-render-hang.md)
- [BUG 0046](../bugs/0046-coach-stream-scrolls-into-blank-space.md)
