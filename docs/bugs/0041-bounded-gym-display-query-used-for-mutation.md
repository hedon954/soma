# BUG 0041：健身房展示上限被写路径复用

- 状态：已修复
- 发现日期：2026-08-26
- 影响范围：健身房 Tool 更新/切换、教练快捷切馆、健身房列表与详情的设为当前和删除
- 上游依据：PR #13 / #14 本地集成审查；[ADR 0100](../adr/0100-bounded-snapshots-continuous-stream-rendering-and-query-first-data-access.md)

## 症状

健身房和器械的展示查询分别限制为 100 与 1000 条，但同一数组也被身份匹配、去重、当前馆唯一性
和级联删除使用。超过展示窗口后可能出现三类数据错误：Agent 找不到已有馆并重复创建、已有器械被
重复插入、切馆后旧的隐藏当前馆仍保留 `isCurrent = true`。

## 根因

- `ConversationRecorder.fetchGyms` / `fetchEquipment` 的展示上限被 `update_gym` 与
  `switch_gym` 直接复用。
- `GymLibraryView`、`GymDetailView` 和教练快捷切馆把有界 `@Query` 结果传给
  `GymSelection.activate` 与 `StructuredDataStore.deleteGym`。
- 展示返回规模和写入不变量没有独立边界，导致“未展示”被误判为“不存在”。

## 修复

- Tool 列表序列化继续保持有界；更新和切换使用完整健身房身份集合，器械更新只读取目标馆范围。
- overview 用当前馆/指定馆谓词和 `fetchLimit = 1` 定位身份，再有界读取该馆器械。
- `StructuredDataStore` 在激活和删除时自行读取完整健身房集合，并按 `gymID` 查询级联器械与媒体；
  View 只提交用户意图，不再传展示快照维护唯一性。

## 回归门禁

- `GymRecorderBoundaryTests` 插入 101 个健身房，确认窗口外目标可切换、可更新且不重复创建；插入
  1000 条其他馆器械后确认目标馆的既有器械仍被原位更新。
- `GymStructuredDataTests` 确认第 101 个隐藏当前馆会在选择首馆后清除，数据库只剩一个当前馆。
- `make check`、`make verify` 与健身房/Tab 模拟器交互回归通过。

## 验证

- 7 项健身房边界定向测试通过。
- `make check` 与 `make verify` 通过：622 项 XCTest、7 项 Swift Testing 及 31 项 Server 测试
  通过，1 项依赖数据库 URL 的 Server 测试按预期跳过。
