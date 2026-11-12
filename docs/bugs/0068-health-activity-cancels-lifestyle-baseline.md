# BUG 0068：健康日活动读数使生活系数消失

- 状态：已修复；「不把日活动能量加入总量」已由后续公式修订
- 日期：2026-11-03
- 上游依据：[PRD 076](../prd/076-adaptive-energy-system.md)、[ADR 0145](../adr/0145-adaptive-energy-system.md)
- 后续修订：[PRD 078](../prd/078-residual-energy-coefficient.md)、[ADR 0147](../adr/0147-residual-energy-coefficient.md)（保留系数，并加上所选日活动能量）、[PRD 081](../prd/081-training-energy-in-total.md)、[ADR 0151](../adr/0151-training-energy-in-total.md)（再加入训练列表消耗）

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

## 后续公式

活动读数取消系数仍然是错误。当前总量是静息 × 残差系数 + 所选日活动能量 + Soma 已记录训练消耗，因此「为避免重复而排除日活动能量」不再适用。训练列表消耗作为独立加项直接加入，不猜测与日活动去重。

## 回归门禁

- DailyActivityEnergyTests / DailyEnergyTotalTests / EnergyRuntimeProjectionTests：活动读数不取消系数；同一系数下 100 与 400 kcal 使总量相差 300；训练不叠加到已选日活动能量上；缺数不编造。日周月年使用同一总量。
- EnergyDayCalculationTests / EnergyTrainingAssociationTests：差额、替代时段、毛净口径、整场动作合计、关联/解除、未知时段与缺设备能量回退。
- EnergyContextToolTests / ProgressEnergyDeficitTests：明确完整性、餐食变化失效、空摄入不补零、正式累计排除未确认日。
- EnergyDiskCompatibilityTests / EnergyEvidenceStoreTests：旧磁盘库保留原值，新表、修订、备份与本地健康边界。
- EnergyCalibrationTests / EnergyCalibrationHoldoutTests / EnergyForecastTests：校准门槛、限幅、留出轨迹、预测不进入实际账。
- make verify；EnergySystemUITests 与 DailyActivityUITests 检查虚构数据交互。真机授权、厂商数据范围及个人生理准确度需单独验收。
