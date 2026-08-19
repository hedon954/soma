# BUG 0021：可空唯一 projectionKey 导致启动迁移失败

- 状态：已修复，待真机复验
- 发现日期：2026-08-16
- 影响范围：启动数据迁移、个人空间训练记录、空 projectionKey 唯一冲突
- 上游依据：[ADR 0073](../adr/0073-independent-set-prescriptions-efforts-and-guided-finalization.md)
- 后续修订：[BUG 0022](0022-installed-v5-schema-checksum-blocks-container-open.md)
- 下游落地：暂无

## 症状

已安装用户打开 App 后停在“正在准备 Soma 数据”，红色错误为
`未能完成操作。(SwiftData.SwiftDataError 错误 1。)`。容器可以打开，因此恢复入口是清空个人
数据而不是同时清空两个空间。夹具里只有一条训练记录时迁移通过，真实个人空间有多条
`WorkoutEntry` 时失败。

## 根因

V5 给 `WorkoutEntry.projectionKey` 加了 `@Attribute(.unique)`，但聊天写入的普通训练记录仍是
`nil`。SQLite 允许多个 NULL，已安装个人库因此能带着 20+ 条空 key 和 version 5 marker 存活。
之后任何一次同时弄脏多条空 key 记录的 `save()` 都会被 SwiftData 判成唯一冲突，表面是
error 1。

第一次修复若直接从当前 V5 模型撤掉 unique，已安装 store 的 checksum 对不上，容器会打不开；
同时 `schemaVersion >= 5` 的提前返回会跳过补 key，重试仍然失败。

## 修复

- 保留 unique 索引，不再为了避开冲突去改当前 schema checksum。
- 启动迁移在检查 marker 之前先补齐稳定 key：带练投影用 `guided-performance:<uuid>`，其余用
  `entry:<uuid>`；有变更才保存。marker 已是 5 时也要执行这一步。
- 打开 `ModelContainer` 前用 SQLite 预修复空 `projectionKey`，避免 SwiftData 在唯一索引上
  物化多条 `nil` 时直接抛 error 1。
- 迁移失败诊断导出堆栈、SwiftDataError Mirror/Dump、SQLite 表/索引/model hash、空与重复
  key 计数，以及最多 30 条训练记录结构样例（动作名、key、ID、组次数重量）。不导出身体测量、
  饮食原文、聊天正文和媒体文件。
- 新写入和备份恢复也补齐 key。重复投影不再写回 `nil`。

## 回归门禁

- 自动化测试：当前 schema 上多条 `projectionKey=nil` 的记录在 marker 已是 5 时仍补齐不重复
  key；磁盘预修复必须把 UUID blob 写成 `entry:<uuid>`；失败诊断必须含堆栈、SQLite 结构和
  训练样例。
- 手工验收：已安装个人空间重试迁移后应进入教练页，训练记录条数与升级前一致。
- 仍无法自动化的风险：若某台设备已经在 unique 冲突时丢掉多余行，应用层无法恢复被丢掉的记录。

## 验证

- 新增 `testStorePreflightRepairsNilProjectionKeysOnDiskBeforeLaunch`。
- 新增 `testCompletedV5MarkerStillRepairsNilProjectionKeys`。
- 新增 `SomaMigrationDiagnosticsTests`：诊断必须含堆栈、步骤名和虚构训练样例。
- 单元测试只使用虚构动作名称，不包含真实健康数据。
