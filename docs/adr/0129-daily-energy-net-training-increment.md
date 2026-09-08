# ADR 0129：日总计只加去重后的训练增量

- 状态：已采纳
- 日期：2026-09-09
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0000](0000-origin-through-0.0.11.md) 仅「全天消耗 = 有效静息 × 活动系数」；不读设备能量、缺资料不写 0 仍有效
  - [ADR 0122](0122-nutrition-rings-and-period-deficit.md) 仅 Mifflin／PAL 不再排除训练净增量；日页圆环与周月年不展示环仍有效
  - [ADR 0128](0128-remove-healthkit-until-redesign.md) 仅「训练日不因课次升高」；不接入 HealthKit 仍有效
- 上游依据：
  - [PRD 061](../prd/061-daily-energy-net-training.md)
  - [日消耗统计：本地公式不含手表](../research/2026-09-08-daily-energy-expenditure-methods.md)
- 后续替代：暂无
- 下游落地：[验收](../acceptance.md)

## 背景

FAO/EFSA/NASEM 发布的是习惯日均需要量。Soma 进展按日历日做账，要把当天训练加进去，又不能
和「静息 × 日常系数」里已经覆盖的那一小时静息算两次。

## 决策

日总计采用日历析因：`静息 × 不含当天训练的活动系数 + Σ 去重增量`。记录层继续保存 Compendium
毛消耗。去重优先用已存 MET：`毛消耗 × (MET − 1) / MET`。没有 MET 时用热量时长从当天静息里
扣掉对应比例；无法去重的记录不进入总消耗。活动系数仍由用户确认或默认 1.4，不编码训练频率。

## 未选择的方案

把训练频率写进更高的习惯 PAL、日总计不再加课次：训练日和休息日看起来一样，不符合进展日历。
日总计直接加记录卡全额：训练时段的静息会收两次。把默认系数改成 1.20：久坐日常的官方下限仍是
1.4，坐班休息日不必再压一档。

## 结果

### 正向影响

- 训练日总消耗高于休息日，且可审查重叠扣了多少。
- 记录卡与日总计职责分开，不改已存热量字段。

### 成本与限制

- 旧记录若缺 MET 和热量时长，只出现在「已记录训练」，不抬总消耗。
- 系数若被用户按「每周练几次」设高，仍可能和增量部分重叠；文案需写明系数不含当天训练。

## 验证

`TrainingEnergyNetIncrement` 的 MET 与时长去重用例；有训练日的进展投影总消耗含净增量；
`make verify`。

## 参考

- [PRD 061](../prd/061-daily-energy-net-training.md)
- FAO/WHO/UNU 2004 表 5.1 析因；Ainsworth Compendium MET
