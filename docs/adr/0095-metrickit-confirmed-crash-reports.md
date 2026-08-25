# ADR 0095：只有 MetricKit 明确崩溃证据才能生成报告

- 状态：已采纳，个人使用阶段
- 日期：2026-08-23
- 维护者：Soma maintainers
- 部分替代：[ADR 0000](0000-origin-through-0.0.9.md) 中把启动哨兵异常结束作为独立崩溃证据的决定
- 上游依据：[BUG 0032](../bugs/0032-sentinel-false-crash-reports.md)

## 背景

启动哨兵只能证明上次前台运行没有执行干净退出。模拟器停止、Xcode 停止、系统强杀、覆盖安装、
设备重启和真实崩溃都会留下相同标记，因此它无法区分“真的崩溃”与正常开发、部署行为。把该标记
直接组装为崩溃邮件会制造大量误报，掩盖真正的系统诊断。

## 决策

1. 只有 MetricKit 投递的 `MXCrashDiagnostic` 是 Soma 自动崩溃报告的成立证据。
2. `AppRunSentinel` 继续记录上次 Session、Turn、活动和心跳，仅用于在 MetricKit 证据到达时补充
   关联上下文；哨兵未清位本身永远不生成报告。
3. watchdog、强杀、调试器停止、模拟器停止、覆盖安装和普通异常退出在没有
   `MXCrashDiagnostic` 时都不发送崩溃邮件。
4. `DiagnosticReport` 显式记录 `evidenceSource = metricKit`。投递前再次校验证据来源；升级后直接
   清理旧版本留下的无来源或 sentinel 报告，避免继续重试误报。
5. MetricKit 报告继续使用 ADR 0083 的本机留盘、脱敏、最多五份和失败重试边界；用户仍可关闭
   自动发送或丢弃队列。

## 结果

- Gmail 中的崩溃邮件只对应系统明确诊断，开发和安装行为不再混入。
- MetricKit 可能延迟投递，甚至无法覆盖所有非崩溃终止；这是避免误报所接受的精度优先取舍。
- 哨兵仍保留定位上下文，但不再拥有“判定崩溃”的权限。

## 验证

- `CrashDiagnosticsTests` 证明 `sentinel` 与 `watchdog` 均不成立，只有 `metrickit` 成立。
- 仓库静态门禁禁止恢复 sentinel 入队，并要求报告显式写入 `.metricKit` 证据来源。
- 模拟器停止与覆盖安装不应产生新报告；真实系统崩溃由后续 MetricKit payload 验收。
