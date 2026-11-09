# ADR 0149：HealthKit 体重导入与最初来源溯源

- 状态：已采纳并实现；真机健康授权与后台唤醒待验收
- 日期：2026-11-09
- 版本：未发布
- 维护者：Soma maintainers
- 部分替代：[ADR 0144](0144-healthkit-daily-activity.md)（在日活动只读边界上增加 `bodyMass` 导入；其余三项日活动决策仍有效）
- 后续替代：暂无
- 上游依据：[PRD 080](../prd/080-healthkit-body-mass.md)
- 下游落地：[验收](../acceptance.md)、[数据库结构](../engineering/database-schema.md)、[工程原则](../../CLAUDE.md)

## 背景

ADR 0144 明确不读取身体测量。用户需要经 Apple 健康自动获得体重并看到最初来源，同时在身体记录查看体重/体脂曲线。列表导入行与手动行曾出现图标容器不一致；本页也暂不需要腰围展示。须在扩展只读范围时保持幂等、删除感知与「健康事实不进模型/备份」边界。

## 决策

1. 在现有 HealthKit 连接上增加只读 `HKQuantityType(.bodyMass)`；`toShare` 仍为空。
2. 使用 `HKAnchoredObjectQuery` 按 `ExternalSyncCursor` 的 `source=appleHealth`、`stream=bodyMass` 保存游标；支持删除样本回调。
3. 导入写入 `BodyEntry`：`externalSource=appleHealth`，`externalID=<sampleUUID>`，`weight` 为千克；保存 `sourceName`/`sourceBundleIdentifier`。
4. 手动/教练 `BodyEntry`（`externalSource==nil`）永不被导入覆盖；同日可并存。
5. 已知来源映射 + 未知回退；Keep 为自备识别标（非官方图标）。主列表用简洁来源名；诚实说明放无障碍与品牌文档。
6. 列表行统一图标容器（与手动 `MediaThumbnail` 同尺寸/圆角/软底），仅字形区分来源。
7. 「体重记录」页曲线与行摘要只含体重、体脂；不删除 `BodyEntry.waist`，不做破坏性迁移；详情/教练腰围能力保持。
8. 自动触发：个人空间、已连接、前台/冷启动追赶；尽力观察者后台。文档不承诺实时。
9. 隐私：导入行过滤出应用备份/导出与教练批量身体历史；最新体重仍供本机计算。
10. 断开保留导入；清空个人数据删除。拒权与空结果不可区分时，空结果不擦除本地导入；观察者无论成败调用 `completion()`。

## 未选择的方案

- 同步体脂/腰围健康类型：本页不需要腰围展示，体脂曲线用本地记录即可。
- 用数值猜测 Keep；把导入体重写进 UserProfile；强制实时后台。
- 在主行堆「非官方」免责长文：干扰扫读；诚实性由无障碍与文档承担。

## 结果

用户可经健康自动得到体重并看到统一布局的最初来源；本页聚焦体重/体脂。代价是多一个只读权限与可选字段。

## 验证

确定性测试覆盖幂等、删除、手动共存、来源映射、备份/模型过滤、无腰围分段/摘要与统一图标容器。`make verify` 为门禁；真机授权与后台另记。
