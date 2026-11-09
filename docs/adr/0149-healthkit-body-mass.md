# ADR 0149：HealthKit 体重导入与最初来源溯源

- 状态：已采纳并实现；真机授权与后台唤醒待验收
- 日期：2026-11-09
- 版本：未发布
- 维护者：Soma maintainers
- 部分替代：[ADR 0144](0144-healthkit-daily-activity.md)（在日活动只读边界上增加 `bodyMass` 导入；其余三项日活动决策仍有效）
- 后续替代：暂无
- 上游依据：[PRD 080](../prd/080-healthkit-body-mass.md)
- 下游落地：[验收](../acceptance.md)、[数据库结构](../engineering/database-schema.md)、[工程原则](../../CLAUDE.md)

## 背景

ADR 0144 明确不读取身体测量。用户需要经 Apple 健康自动获得体重（含 Keep 等写入健康的样本），并在列表看到最初来源，同时在身体记录查看体重/体脂/腰围曲线。必须在扩展只读范围时保持幂等、删除感知与「健康事实不进模型/备份」边界。

## 决策

1. 在现有 HealthKit 连接上增加只读 `HKQuantityType(.bodyMass)`；`toShare` 仍为空。
2. 使用 `HKAnchoredObjectQuery`（或等价增量查询）按 `ExternalSyncCursor` 的 `source=appleHealth`、`stream=bodyMass` 保存游标；支持删除样本回调。
3. 导入写入 `BodyEntry`：`externalSource=appleHealth`，`externalID=<sampleUUID>`，`weight` 为千克；保存 `sourceName`/`sourceBundleIdentifier` 来自 `HKSourceRevision`。
4. 手动/教练 `BodyEntry`（`externalSource==nil`）永不被导入覆盖；同日可并存。
5. 已知来源映射（名称或 bundle 含 keep/gotokeep → Keep 图标；Apple 相关 → 健康图标；其余 → 通用图标 + 原始名称）。不调用私有 API 取 App 图标。
6. 自动触发与日活动一致：个人空间、已连接、前台/冷启动追赶；尽力 `HKObserverQuery` + background delivery。文档诚实写明非实时保证。
7. 隐私：导入行过滤出应用备份/导出与教练批量身体历史；本机「最新体重」与进展曲线可读全部本地 `BodyEntry`（含导入）。体脂/腰围曲线使用已有本地字段，本迭代不申请更多健康类型。
8. 断开保留导入；清空个人数据删除；Info.plist 使用说明补充体重只读用途。
9. HealthKit 无法区分「读权限被拒」与「暂无样本」：两者常表现为空结果且无 error。空 upsert/空 deleted 绝不擦除本地已导入行；仅处理明确删除 UUID。观察者回调无论成败都必须 `completion()`，失败时不触发追赶。

## 未选择的方案

- 同步体脂/BMI/身高：用户本迭代未证明必须从健康读取体脂；曲线可用手动数据。
- 用数值猜测 Keep：不可靠，必须用 HealthKit 来源字段。
- 把导入体重写进 UserProfile：体重事实仍只存在 `BodyEntry`。
- 强制实时后台：超出 iOS 可承诺范围。

## 结果

用户可经健康自动得到体重并看到最初来源；日活动边界保持。代价是多一个只读权限与可选字段，并需真机验收授权与观察者唤醒。

## 验证

确定性测试覆盖幂等、删除、手动共存、来源映射、备份/模型过滤与曲线空态。`make verify` 为门禁；真机授权与后台另记。
