# PRD 060：撤回 Apple 健康接入，待单独设计后再做

- 状态：已采纳
- 日期：2026-09-09
- 版本：0.0.22
- 修订自：
  - [PRD 000](000-origin-through-0.0.11.md) 的 Apple 健康导入、设备历史活动系数、Keep/COROS 经健康读取
  - [PRD 059](059-coach-ids-progress-and-required-zeros.md) 仅进展估算的设备能量来源；训练 MET 不累加仍有效
- 上游依据：[日消耗统计：本地公式不含手表](../research/2026-09-08-daily-energy-expenditure-methods.md) 的「当前不读手表与 HealthKit」
- 下游落地：
  - [ADR 0128](../adr/0128-remove-healthkit-until-redesign.md)
  - [验收](../acceptance.md)
- 后续修订：暂无

## 背景

进展总消耗和设置里的体重/训练同步都挂在 Apple 健康上，但手表热量、覆盖率、与 Soma
课次去重都还没有单独设计。继续留一条半成品接入会让日消耗和导入记录看起来像已经接好。

## 用户结果

设置不再出现「健康数据与设备」。App 不请求健康权限，不读体重、训练或能量样本。体重和训练
只来自 Soma 记录与身体资料。进展预估总消耗在资料齐全时用 Mifflin 静息 × 个人活动系数或默认
1.4。缺资料时不显示总消耗为 0。

已由健康导入、仍留在库里的训练或体重记录继续当普通 Soma 记录，不自动删除。

## 产品规则

- 当前产品不接入 HealthKit、Apple Watch、Keep 或 COROS。
- 全天消耗 = 有效静息 × 活动系数；系数优先本人确认的生活方式，再默认参考 1.4（不写入个人设置）。
- 不读取设备基础/活动能量，也不用设备历史校准系数。
- 已记录训练 kcal 仍只作对照，不加入预估总消耗，直到日消耗公式的后续 PRD 授权。

## 数据与隐私

不再请求 `HealthKit` 授权，Info.plist 不声明健康用途，工程不带健康 entitlement。不新增远程
数据流。测试只用虚构记录。`ExternalSyncCursor` 与记录上的 `externalSource` 字段保留，供以后
重新设计导入时使用，本需求不删模型。

## 明确不在范围

- 重新设计手表热量、HealthKit 覆盖率、样本去重或设置同步页
- 把训练 MET 加进预估总消耗
- 体重趋势反推 TDEE
- 删除用户库里已经存在的导入记录

## 验收

设置根页没有健康同步入口；工程与 Info.plist 不含 HealthKit；进展快照不调用健康能量读取；
`make verify`。
