# ADR 0128：当前产品不接入 HealthKit

- 状态：部分已替代
- 日期：2026-09-09
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 仅 Apple 健康导入、设备历史活动系数与 HealthKit 去重热路径；Mifflin × 活动系数公式、记录 `externalSource` 与 `ExternalSyncCursor` 模型仍有效
- 上游依据：
  - [PRD 060](../prd/060-remove-healthkit-until-redesign.md)
  - [日消耗统计：本地公式不含手表](../../../research/2026-09-08-daily-energy-expenditure-methods.md)
- 后续替代：[ADR 0129](0129-daily-energy-net-training-increment.md)（仅日总计加入去重训练增量；不接入 HealthKit 仍有效）
- 下游落地：[验收](../../../acceptance.md)

## 背景

HealthKit 同时承担设置导入和进展 PAL 校准，但手表热量与导入边界尚未设计。半成品读取会把
未审查的设备数写进日消耗，并迫使工程长期持有健康权限。

## 决策

删除 HealthKit 导入器、基础/活动能量读取、设置「健康数据与设备」页、健康用途说明和
entitlement。进展估算只使用身体资料上的 Mifflin 静息，乘以用户确认的生活方式系数或默认
1.4。已导入记录不级联删除。重新接入必须新 PRD/ADR，不能把旧读取路径静默加回。

## 未选择的方案

只停进展侧能量、保留设置导入；保留权限但暂时不调用。前者仍会写入未经设计的训练/体重样本；
后者会继续向用户要健康授权。

## 结果

### 正向影响

- 日消耗和设置不再假装已经接好手表。
- 工程不再持有未使用的健康权限。

### 成本与限制

- 有表用户不能从 Soma 同步健康样本，直到后续设计落地。
- 默认 1.4 仍是日常粗估；训练日是否升高见 [ADR 0129](0129-daily-energy-net-training-increment.md)。

## 验证

无 HealthKit 源文件与权限键；`AdaptiveEnergyEstimator` 无 `deviceHistory`；设置根页无健康入口；
`make verify`。

## 参考

- [PRD 060](../prd/060-remove-healthkit-until-redesign.md)
- [日消耗调研](../../../research/2026-09-08-daily-energy-expenditure-methods.md)
