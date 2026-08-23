# BUG 0032：启动哨兵把非崩溃终止误报为崩溃

- 状态：已修复，待真实 MetricKit 崩溃验收
- 发现日期：2026-08-23
- 影响范围：自动崩溃诊断、Gmail 噪声、历史待发送报告
- 下游落地：[ADR 0095](../adr/0095-metrickit-confirmed-crash-reports.md)

## 症状

Gmail 间歇收到崩溃诊断，但近期邮件只有 Simulator sentinel，没有异常码、信号、堆栈或 MetricKit
证据。停止模拟器、Xcode 调试或覆盖安装后也可能产生同类邮件。

## 根因

`AppRunSentinel` 的“上次运行未清位”被当作独立崩溃证据并直接入队。这个标记无法区分真实崩溃、
强杀、调试停止、模拟器停止和安装替换；调试器过滤只能减少一部分误报，不能让哨兵具备诊断能力。

## 修复

- 哨兵降为上下文来源，启动时只记录日志并清理标记，不生成报告。
- 只有 MetricKit `MXCrashDiagnostic` 可入队，报告显式保存 `.metricKit` 证据来源。
- 每次激活和投递前清理无证据或旧 sentinel 报告，防止升级后继续发送历史误报。
- 设置页明确说明强杀、模拟器停止、安装替换和哨兵未清位不会生成报告。

## 回归门禁

- `CrashDiagnosticsTests` 覆盖 sentinel/watchdog 拒绝和 MetricKit 接受。
- `make check` 禁止恢复 sentinel 入队，并要求 `.metricKit` 证据字段。
- 手工停止模拟器与覆盖安装后不应新增报告；真实崩溃需等待系统投递 MetricKit 证据。

## 本轮验证

- `make verify` 通过；`CrashDiagnosticsTests` 覆盖来源字符串和旧无来源报告对象两层门禁。
- 本轮模拟器构建、停止、重新安装与真机覆盖安装均未通过 sentinel 创建报告；真实 MetricKit
  payload 仍需等待系统在后续真实崩溃时投递。
