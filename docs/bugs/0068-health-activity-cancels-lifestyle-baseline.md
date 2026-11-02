# BUG 0068：健康日活动读数使生活系数消失

- 状态：已修复，本地回归与界面验收通过；真机数据待验收
- 日期：2026-11-03
- 上游依据：[PRD 076](../prd/076-adaptive-energy-system.md)、[ADR 0145](../adr/0145-adaptive-energy-system.md)

## 症状

导入活动卡路里后，原来的生活系数不再参与总消耗。

## 根因

总消耗从“静息 × 生活系数”切换为“静息 + 活动日合计”。
COROS 的活动合计不能证明低强度生活活动已完整覆盖，因此该分支删除了生活活动估算。
反过来，直接把日合计加到原基线、步行和训练上，又会重复计算。

## 修复

采用单一参考日差额模型：参考生活消耗 + 非训练步行差额 + 去重训练增量 + 长期修正。
健康日合计继续保存为原始观察，不替换基线、不再次累加。所有时间范围和饮食目标共享投影。
新增热量口径字段；旧 MET 不能证明旧热量口径。Soma 同一场动作先聚合，再通过原始身份或
本人明确关联选择一份能量。跨来源、时段未知时保留未决依据，不同时累计可能重复的记录。

## 回归门禁

- DailyActivityEnergyTests / EnergyRuntimeProjectionTests：活动日读数不能取消 1.4，也不多奖励日合计；日周月年一致。
- EnergyDayCalculationTests / EnergyTrainingAssociationTests：差额、替代时段、毛净口径、整场动作合计、关联/解除、未知时段与缺设备能量回退。
- EnergyContextToolTests / ProgressEnergyDeficitTests：明确完整性、餐食变化失效、空摄入不补零、正式累计排除未确认日。
- EnergyDiskCompatibilityTests / EnergyEvidenceStoreTests：旧磁盘库保留原值，新表、修订、备份与本地健康边界。
- EnergyCalibrationTests / EnergyCalibrationHoldoutTests / EnergyForecastTests：校准门槛、限幅、留出轨迹、预测不进入实际账。
- make verify；EnergySystemUITests 与 DailyActivityUITests 检查虚构数据交互。真机授权、厂商数据范围及个人生理准确度需单独验收。
