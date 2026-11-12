# ADR 0151：总消耗把 Soma 训练消耗作为独立加项

- 状态：已采纳并实现，待模拟器验收
- 日期：2026-11-12
- 版本：未发布
- 维护者：Soma maintainers
- 部分替代：[ADR 0147](0147-residual-energy-coefficient.md)（存在日活动读数时不再把训练排除在总量之外，也不再把训练只作为日活动能量的拆分项）、[ADR 0145](0145-adaptive-energy-system.md)（当前总消耗再加入训练列表消耗）、[ADR 0144](0144-healthkit-daily-activity.md)（训练列表消耗作为独立加项进入总量）
- 后续替代：暂无
- 上游依据：[PRD 081](../prd/081-training-energy-in-total.md)
- 下游落地：[验收](../acceptance.md)、[BUG 0068](../bugs/0068-health-activity-cancels-lifestyle-baseline.md)

## 背景

ADR 0147 规定：预估总消耗 = 当日静息 × 残差系数 + 所选日活动能量。若能证明训练能量已包含在该日活动读数中，明细可拆成「训练活动消耗」和「其余活动消耗」，两项之和等于日活动读数，训练不得再加。无法拆开时，活动消耗保持整份读数。没有日活动读数时，才把去重后的已知训练净能量计入总量。

这使进展日页训练列表上的估算消耗（用户可见的约 xx kcal）在已有活动消耗时不进入总消耗弹层。用户明确要求训练消耗与活动消耗一样直接加入，而不是继续沿用「防重复故排除」的旧边界。

## 决策

用户可见的预估总消耗、推荐/剩余摄入、实际差额、日周月年进展和教练上下文都使用：

```text
当日静息 × 残差系数 + 所选日活动能量 + Soma 已记录训练消耗
```

展开后，明细必须加总为：

```text
静息 + 基准额外消耗 + 活动消耗 + 训练消耗
```

其中基准额外消耗仍是 静息 ×（残差系数 − 1）。系数仍只通过 `ResidualEnergyCoefficient.current()` 取得。

「Soma 已记录训练消耗」与进展页训练列表使用同一汇总口径：

- 只计入 `WorkoutEntry` / 进展记录中 `kind == .workout` 且不是日常活动的条目。
- 数值取列表展示的 `estimatedCalories`，包括本地 MET 毛消耗和用户明确提供的整数估算；不在加入总量前改写成 `netEnergy`。
- 按记录身份去重，同一条只加一次。
- 无此类记录时为 0。
- `nil`、非有限、小于 0、或达到 100000 的单条估算不计入、不编成 0；其余合法值仍相加。

活动消耗仍只解释所选日活动能量：有读数就用整份读数，没有读数显示未记录而不是 0，显式 0 有效。不再把训练填进活动项，也不再把活动拆成「训练活动消耗 / 其余活动消耗」。

HealthKit 授权的写入集合为空，Soma 不把训练或活动能量写回 Apple 健康。因此训练列表里的 Soma 估算本身不会进入日活动读数。但日活动所读的 `activeEnergyBurned` 仍可能包含 Apple Watch 或其他 App 对同一场身体活动的计量；现有训练关联不能可靠覆盖所有情况。本决策不猜测扣减，也不把需求改成活动与训练二选一。产品说明必须保留重复计量的可能，不得声称已去重。不得为查重而修改授权或读取用户个人健康库。

增删改训练记录后，总量与明细因共享上述计算而更新，不在视图里另写一套加法。

`DailyEnergyTotal.Components` 的自定义解码必须接受历史与当前 `EnergyInputCoding` 写出的真实线格式。Swift `Codable` 把 `selected` / `recordedTraining` 等关联值写成 `{"_0": n}` 或无标签数组；只按手写纯 Double 猜测旧档会在 `decodeIfPresent(Double)` 上触发 `typeMismatch`。该错误会被进展加载映射成「返回或保存的内容与当前版本不兼容」，使日页整页无法读取。旧的 `recordedTraining` 仍迁为活动未记录 + 独立训练加项，`disaggregated` 仍合并为整份活动能量；当前写出的 `selected` / `absent` 与 `trainingKilocalories` 必须能往返。此兼容解码不改变「直接加入」的公式。

## 未选择的方案

- 继续在有日活动读数时排除训练：这正是用户要求改掉的行为。
- 为可能重叠而从活动或训练中猜测扣减，或让两者二选一：没有可靠关联时会少计或违背「直接加入」。
- 加入前把 MET 毛消耗换成净活动能量：会与训练列表展示的数字不一致。
- 把整份日活动能量改成只含非训练部分：同样是未经用户同意的扣减。

## 结果

### 正向影响

- 总消耗与训练列表的可见估算一致，明细四项可以加总核对。
- 推荐摄入、差额和周期图与日页共用同一公式。

### 成本与限制

- 若手表或其他 App 已把同一场训练计入日活动能量，总量可能重复计量这部分。本决策记录该风险，不假装已消除。
- 列表口径若是 MET 毛消耗，训练时段内的静息也会出现在「每日静息」里，存在很小的口径重叠；为与列表数字一致而接受。

## 验证

`DailyEnergyTotalTests`、`DailyEnergyTotalLegacyDecodingTests`、`DailyActivityEnergyTests`、`ProgressEnergyBreakdownTests` 与相关投影测试覆盖四项加总、列表汇总、无训练为 0、空/非法值、增删改后的同一计算、日/周期，以及用 `EnergyInputCoding` 生成的历史/当前 `presentedTotal` 线格式解码。`make verify` 通过后，用模拟器合成数据目视日页弹层、训练列表、浅色/深色、大字号，以及带旧格式校准评审时日页仍可读取。

## 参考

- `Soma/Services/Health/DailyEnergyTotal.swift`
- `Soma/Services/Settings/ProgressEnergyBreakdown.swift`
- [ADR 0147](0147-residual-energy-coefficient.md)
