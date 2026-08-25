# ADR 0075：SwiftData 只打开当前模型，不维护历史 VersionedSchema

- 状态：已采纳
- 日期：2026-08-17
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0071](../../0.0.6/adr/0071-integer-business-identities-and-explicit-relations.md) 中使用 VersionedSchema 分阶段打开历史 store 的打开路径
  - [ADR 0073](0073-independent-set-prescriptions-efforts-and-guided-finalization.md) 中冻结历史 schema、注册连续 versioned migration，以及用跨级磁盘夹具自证打开路径的要求
- 后续修订：
  - [ADR 0097](../../../adr/0097-current-baseline-performance-budget-and-cache-invalidation.md) 部分替代每次启动继续执行整表业务回填的边界；当前 marker 命中后立即返回
- 上游依据：
  - [PRD 031](../prd/031-guided-workout-v5-independent-sets-and-automatic-completion.md)
  - [BUG 0022](../../../bugs/0022-installed-v5-schema-checksum-blocks-container-open.md)
- 下游落地：
  - [数据库结构与 ER 图](../../../engineering/database-schema.md)
  - [训练领域模型与运行时协议](../../../engineering/training-domain-model.md)

## 背景

已安装个人库停在“正在准备 Soma 数据”。先是可空唯一 `projectionKey` 让启动回填失败
（BUG 0021），修好后容器仍打不开（BUG 0022）：已安装 store 的 identifier 是 `5.0.0`，
而后来在同一版本号上追加了 `WorkoutSession` 可选暂停列。冻结历史 `VersionedSchema` 并
追逐 checksum，既对不上磁盘哈希，也把打开路径做成了多套 fallback。

当前只有一名用户、一台已打开成功的设备。继续维护 V3/V4/V5 冻结模型、跨级夹具和
versioned plan 没有产品收益。

## 决策

1. App 只注册 `SomaDataSchema` 的当前 `@Model` 列表，用 `Schema(SomaDataSchema.models)`
   打开个人与演示容器。不声明 `VersionedSchema`，不传入 `migrationPlan`。
2. 删除历史冻结模型、`SomaSchemaMigrationPlan` 以及 v0.0.5/v0.0.6 磁盘夹具。不再用合成
   旧 schema 或发布版 store 证明打开路径。
3. 启动门禁继续负责业务回填：SQLite 预修复空 `projectionKey`，再展开旧聚合处方、建立
   Effort、补齐不重复投影键、分配 Int64、校验快照，并写入 `DataMigrationMarker`
   schemaVersion 5。打开失败时仍不挂载业务 Root，只提供可重试错误和脱敏诊断。
4. 追加可选列依赖系统在无 plan 时做轻量推断。不兼容变更必须新增 ADR，写明启动回填或
   明确的数据重建，不能再为了“兼容从未再安装的中间版本”恢复历史 VersionedSchema 链。

独立组、Effort、一对一投影键、nil 真值和双空间 marker 仍按 ADR 0073 其余条款执行。

## 未选择的方案

- 继续冻结 V3/V4/V5 并修补 checksum：已安装库对不上冻结哈希，维护成本高于收益。
- 先走 versioned plan、失败再 inferred fallback：半套计划仍会挡住已安装 `5.0.0` store。
- 清空个人数据后重建：用户明确禁止；业务事实必须留下。

## 结果

### 正向影响

- 打开路径与已安装设备一致，历史 schema 文件不再反向污染当前模型。
- 启动门禁仍能补 key、展开旧处方并分配业务 ID。

### 成本与限制

- 仓库不再证明从未再安装的 v0.0.5/v0.0.6 磁盘 store 可经 versioned plan 升级。
- 以后若出现无法推断的破坏性 schema 变更，必须靠新 ADR 决定回填或重建，而不是默默加回
  历史版本链。

## 验证

- 当前 schema 无 `migrationPlan` 打开磁盘库；预修复把 UUID blob 写成 `entry:<uuid>`。
- marker 已是 5 时仍补齐空/重复 `projectionKey`；旧聚合处方展开可幂等。
- 缺失目标次数保持 `nil` 并阻止开练。
- `make check`、`make verify`；真机只点重试迁移，个人训练记录仍在。

## 参考

- [`Soma/Models/SomaDataMigration.swift`](../../../../Soma/Models/SomaDataMigration.swift)
- [`Soma/Models/SomaStoreOpening.swift`](../../../../Soma/Models/SomaStoreOpening.swift)
- [BUG 0021](../../../bugs/0021-unique-optional-projection-key-blocks-launch-migration.md)
