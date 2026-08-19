# BUG 0022：在已安装 V5 store 上改当前 schema 导致无法打开容器

- 状态：已修复，待真机复验
- 发现日期：2026-08-17
- 影响范围：启动数据迁移、已安装 V5 个人/演示库、带练 Session 录像暂停字段
- 上游依据：[ADR 0074](../adr/0074-bounded-guided-camera-activation-and-partial-evidence.md)
- 下游落地：[ADR 0075](../adr/0075-current-swiftdata-schema-without-historical-versions.md)
- 修订自：[BUG 0021](0021-unique-optional-projection-key-blocks-launch-migration.md) 修复后仍无法进入教练页的后续故障

## 症状

投影键补齐后启动仍失败。诊断为 `打开演示数据容器` /
`SwiftDataError.loadIssueModelContainer`，`_explanation` 为空。SQLite `quick_check` 通过，
`projectionKey` 已无空值或重复，两个库的 `NSStoreModelVersionIdentifiers` 仍是 `5.0.0`。
`WorkoutSession` 缺少 `ZAUTOMATICRECORDINGPAUSECODERAW` 与
`ZAUTOMATICRECORDINGPAUSEREASON`。

## 根因

已安装库完成当时的 schema 时还没有这两个可选列。后来在同一个 `5.0.0` 上改了
`WorkoutSession`，SwiftData 的 VersionedSchema 计划无法对已安装的 5 做同版本轻量迁移。
继续冻结历史版本并追逐 checksum 也无法打开这台设备上的库。

## 修复

- 打开磁盘库只用当前 `SomaDataSchema`，不带 `migrationPlan`，让系统按字段差补上缺少的可选列。
- 不再维护 `SomaDataSchemaV3/V4/V5/V6` 或 `SomaSchemaMigrationPlan`。长期打开路径见
  [ADR 0075](../adr/0075-current-swiftdata-schema-without-historical-versions.md)。
- 应用层 `DataMigrationMarker` 仍为 5：没有需要回填的新业务事实。

## 回归门禁

- 自动化测试：当前 schema 无 plan 打开磁盘库；新可选列为 `nil` 时训练记录条数不变。
- 手工验收：已安装真机只点重试迁移，进入教练页，个人训练记录仍在。

## 验证

- 打开路径覆盖于 `SomaStoreOpening` 与 `SomaMigrationDiagnosticsTests`。
- 单元测试只使用虚构动作名称，不包含真实健康数据。
