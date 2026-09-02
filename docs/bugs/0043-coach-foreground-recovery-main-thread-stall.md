# BUG 0043：教练页回前台恢复链阻塞主线程

- 状态：已修复，待 Release 真机量化复验
- 发现日期：2026-08-27
- 影响范围：教练长会话从后台返回前台后的首个触摸、滚动与输入
- 上游依据：维护者真机反馈
- 后续修订：[BUG 0050](0050-coach-foreground-recovery-freezes-again.md) 的第二阶段前台恢复量化与缓存边界
- 下游落地：
  - [PRD 049](../prd/049-foreground-responsiveness-and-readable-monthly-progress.md)
  - [ADR 0107](../adr/0107-foreground-recovery-and-progress-evidence-projection.md)

## 症状

Soma 在教练页进入后台后重新打开，页面已经可见，但触摸、滚动和输入短时没有响应，稍后自行恢复。

## 根因

`RootView` 的 active 回调在 `MainActor` 上依次重试远程撤销、解析入口 Session、恢复过期租约、
恢复等待前台 Job、扫描非终态失败回复并领取队首。Session 解析可能改变当前选择并触发消息查询、
观察失效和长会话布局；Job 恢复的多个无上限查询又占用同一主线程周期。教练内容越多，这组生命周期
工作越容易表现为整页冻结。该结论来自当前代码路径；真机各栈占比仍以复验 Trace 为准。

## 修复

- 回前台保持当前 Session、滚动和草稿，只在 App 启动与发送门禁解析业务 Session。
- 首帧恢复任务先让出 MainActor；Agent 过期租约、等待前台和失败回复提升均只处理串行 FIFO 队首。
- 新增匿名 `foreground_recovery` signpost，分开度量异步网络等待与主线程恢复区间。
- 不把 SwiftData 业务写入移出 MainActor，不改变 Job/Event、人工屏障或幂等语义。

## 回归门禁

- 自动化测试或静态检查：`make perf-check` 禁止 active 回调重新调用 `resolveForEntry`，并要求三条
  Job 恢复查询设置 `fetchLimit = 1`；既有 FIFO 与人工失败测试继续通过。
- 手工验收：Release 真机打开长会话，连续三次后台→前台后立即滚动和输入；当前 Session、位置与
  草稿不变，无 250 ms 以上 Hangs 事件。
- 仍无法自动化的风险：真实数据库页缓存、设备热状态和 SwiftUI 布局成本只能由同一真机流程确认。

## 验证

- `make verify` 已通过：XCTest 637 项与 Swift Testing 7 项均为 0 失败；Simulator 构建已通过。
- iPhone 尺寸 Simulator 已检查进展页浅色、深色、大字号、单行能量摘要、30 天曲线与跟随式分项浮层。
- Release 真机后台→前台手感与 Hangs/Time Profiler 仍待量化，不能由 Simulator 代替。
