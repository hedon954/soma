# PRD 053：动态能量估算与可解释的进展展示

- 状态：已采纳，实施中
- 日期：2026-09-05
- 修订自：[PRD 049](049-foreground-responsiveness-and-readable-monthly-progress.md)、[PRD 050](050-lightweight-progress-disclosure-and-coach-controls.md) 的能量估算与展示
- 上游依据：[ADR 0107](../adr/0107-foreground-recovery-and-progress-evidence-projection.md)
- 下游落地：[ADR 0114](../adr/0114-progress-periods-and-adaptive-energy.md)、[PRD 054](054-progress-history-and-periods.md)
- 跟踪：[BUG-20](../../.codex/plans/2026-09-02-coach-training-critical-bugfixes.md)、[实施 TODO](../../.codex/plans/2026-09-05-progress-redesign-implementation.md)

## 我们的目标是什么

让进展页清楚回答：**今天记录了多少摄入、一天大约消耗多少、两者相差多少。**

- 展示全天预估总消耗，而不只是静息消耗或“静息 + 训练”。
- 活动系数随个人数据动态更新，不固定套用 1.4 或 1.5。
- 没有记录的累计项显示 0，不因部分数据缺失让整个合计变成横杠。

## 我们调研了什么

1. **静息不等于全天消耗。** Mifflin–St Jeor 估算的是静息消耗；全天消耗还包括日常活动、运动和食物热效应。
   [Mifflin 原研究](https://pubmed.ncbi.nlm.nih.gov/2305711/)、[NASEM 2023](https://www.ncbi.nlm.nih.gov/books/NBK591031/)。
2. **活动系数反映整个生活方式。** 职业、走动和训练都有关，不能仅凭一周训练次数决定。FAO 建议用一个月或更长时间描述习惯活动，但没有规定唯一的生理学观察周期。
   [FAO/WHO/UNU](https://www.fao.org/4/y5686e/y5686e07.htm)。
3. **估算需要持续校准。** 初始估算应结合之后的体重变化调整；但漏记饮食、设备缺测和体重水分波动都会影响判断。
   [NASEM 2023](https://www.ncbi.nlm.nih.gov/books/NBK591020/)。
4. **28 天不是通用标准。** Hall 的研究在特定条件下需要超过 28 天的体重记录来推断摄入变化，并没有证明活动系数必须采用 28 天。
   [Hall 与 Chow，2011](https://pubmed.ncbi.nlm.nih.gov/21562087/)。
5. **设备活动能量不能重复相加。** HealthKit 将活动与静息能量分开；已包含在设备活动里的训练，不能再加一次。
   [Apple HealthKit](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/activeenergyburned)。

## 我们的结论是什么

1. **首页对照已记录摄入与全天预估总消耗；静息与训练消耗放入能量依据。**
   只有本地训练数据时明确叫“已记录训练消耗”。摄入与全天预估的差值只是参考，不代表今天已经形成的真实缺口。

2. **采用“静息估算 × 动态有效活动系数”的方案。**
   优先用覆盖充分的历史设备静息与活动数据更新系数；没有设备数据时，依据用户明确提供的生活方式形成初始参考。
   不能仅靠力量训练次数推断全天活动，也不把设备估算称为真实测量。

3. **先评估最近 28–30 天，不直接锁定 7 天。**
   这是待验证的产品窗口，不是科学定律。只使用已结束且数据可用的日期；不把当天活动按已过时间线性放大。

4. **累计缺失项按 0 参与加法，原始缺失仍保留。**
   例如训练热量为 `120、未知、80`，显示已记录 `200 kcal`，并说明一条未计入。
   漏记不能当成真实零摄入或零活动用于校准；缺少全天估算的必要资料时，提示补充资料，不显示人体消耗为 0。

5. **估算必须可解释，不重复计算。**
   点开指标能看到来源、公式、采用的系数和时间范围；系数已包含的训练不能再次叠加。

6. **先做好记录汇总和活动历史估算，再加入长期校准。**
   摄入与体重校准要等记录完整性和算法验证通过后启用，不能根据几天体重变化自动修改消耗。
