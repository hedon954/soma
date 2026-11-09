# ADR 0149：HealthKit 体重/体脂导入与最初来源溯源

- 状态：已采纳并实现；真机健康授权与后台唤醒待验收
- 日期：2026-11-09
- 版本：未发布
- 维护者：Soma maintainers
- 部分替代：[ADR 0144](0144-healthkit-daily-activity.md)（在日活动只读边界上增加 `bodyMass` 与 `bodyFatPercentage` 导入；其余三项日活动决策仍有效）
- 后续替代：暂无
- 上游依据：[PRD 080](../prd/080-healthkit-body-mass.md)
- 下游落地：[验收](../acceptance.md)、[数据库结构](../engineering/database-schema.md)、[工程原则](../../CLAUDE.md)

## 背景

ADR 0144 明确不读取身体测量。用户需要经 Apple 健康自动获得体重与体脂，并看到最初来源；体重记录页应以一张合并图比较两条曲线（分轴分色）而非切换 Tab 或堆叠两张图。列表导入行与手动行须统一图标容器；本页不展示腰围。须保持幂等、删除感知与「健康事实不进模型/备份」边界。

## 决策

1. 在现有 HealthKit 连接上增加只读 `HKQuantityType(.bodyMass)` 与 `HKQuantityType(.bodyFatPercentage)`；`toShare` 仍为空。
2. 体重与体脂各自使用 `HKAnchoredObjectQuery` + `ExternalSyncCursor`（`stream=bodyMass` / `stream=bodyFat`）；支持删除样本回调与尽力观察者后台。
3. 导入写入 `BodyEntry`：`externalSource=appleHealth`；体重 `externalID=bodyMass:<uuid>` 且填充 `weight`；体脂 `externalID=bodyFat:<uuid>` 且填充 `bodyFat`（百分点）。各自保留 `sourceName`/`sourceBundleIdentifier`。
4. 不因同日或同来源合并体重与体脂样本；手动/教练行（`externalSource==nil`）永不被导入覆盖。
5. HealthKit `.percent()` 中 1.0 = 100%；转换入库为 0…100 百分点，带有效域校验。
6. 已知来源映射 + 未知回退；Keep 自备识别标；主列表简洁来源名。
7. 列表行统一图标容器；「体重记录」合并单图：共享时间域，左 kg / 右 %，体重身体蓝、体脂对比色+虚线点形；无指标切换；不删除 `BodyEntry.waist`。
8. 最新体重只取 `weight != nil` 的记录；纯体脂导入不参与、不清除体重。
9. 自动触发与隐私边界同体重：个人空间、已连接、前台追赶；导入行过滤出备份/导出与教练批量身体历史。
10. 拒权与空结果不可区分时，空结果不擦除本地导入；观察者无论成败调用 `completion()`。已连接用户补体脂权限需再次 `requestAuthorization` 或系统设置，UI 提供入口但不伪称能判定拒绝。

## 未选择的方案

- 同步腰围/BMI/瘦体重/身高健康类型。
- 同日自动把体重与体脂捏成一条 BodyEntry。
- 单 Y 轴混用 kg 与 % 或隐藏归一化刻度；用指标 Tab 切换；堆叠两张独立图占纵向空间。
- 强制实时后台；在主行堆「非官方」免责长文。

## 结果

用户可经健康自动得到体重与体脂并看到统一布局的最初来源；一张图上比较两条曲线且单位诚实。代价是多两个只读权限与可选字段、以及已连接用户的补授权步骤。

## 验证

确定性测试覆盖幂等、删除、手动共存、来源映射、体脂 0…1 转换、独立样本不互删、备份/模型过滤、双轴映射往返、合并图无腰围摘要、统一图标容器。`make verify` 为门禁；真机授权与后台另记。
