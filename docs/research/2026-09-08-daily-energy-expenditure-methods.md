# 日消耗统计：本地公式，不含手表与 HealthKit

- 状态：已转化。HealthKit 接入已按 [PRD 060](../prd/060-remove-healthkit-until-redesign.md) 删除；日历析因日总计已按 [PRD 061](../prd/061-daily-energy-net-training.md) 落地
- 日期：2026-09-09
- 修订自：
  - [目标导向进展指标调研](2026-08-26-goal-directed-progress-metrics.md) 的「日消耗必须可审查、训练日应高于休息日」
  - [进展历史与图表逻辑重设计](2026-09-05-progress-history-and-chart-design.md) 的「不把未经校验的系数直接叠到当日数上」
- 后续修订：暂无
- 下游落地：
  - [PRD 060](../prd/060-remove-healthkit-until-redesign.md)（仅撤回 HealthKit）
  - [ADR 0128](../adr/0128-remove-healthkit-until-redesign.md)
  - [PRD 061](../prd/061-daily-energy-net-training.md)
  - [ADR 0129](../adr/0129-daily-energy-net-training-increment.md)

当前实现：预估总消耗 = Mifflin 静息 ×（个人活动系数或默认 1.4）+ 当天去重后的训练增量。训练记录仍保存完整 MET 热量。

## 权威报告怎么算（2026-09-09 核对）

问的是两件事：官方能量需要量用什么公式；「经常训练的人，休息日是不是也更高」。下面只引用专家咨询与膳食参考摄入量，不引用商业 TDEE 网站。

### 官方需要量：习惯 PAL × 静息，不是「职业系数 + 当天训练」

FAO/WHO/UNU 2004、EFSA 2013、NASEM 2023 发布的都是**体重稳定时的日均能量需要**，单位是一天的平均数，不是日历上的训练日/休息日。

```text
需要量 ≈ 预测静息 × 习惯 PAL
PAL = 习惯 TEE / 静息
```

- **FAO/WHO/UNU 2004**（[第 5 章](https://www.fao.org/4/y5686e/y5686e07.htm)）：成人需要量用**习惯 TEE 的析因估计**。把一天里睡眠、盥洗、职业、通勤、家务、休闲、运动各自的小时数 × 该活动的 PAR（相对 BMR 的倍率），加总再除以 24，得到 PAL，再乘群体 BMR。1985 年版曾按**职业轻重**分档；2004 明确否定「只看职业」：轻职业但业余剧烈运动的人，以及重体力但其余时间久坐的人，都必须按**生活方式**（职业 + 自主活动）归类。PAL 描述的是**多数日子、约一个月及以上**最常做的事，不是今天有没有去健身房。分档：久坐/轻活动 1.40–1.69，主动/中等 1.70–1.99，剧烈 2.00–2.40。
- **EFSA 2013**（[doi:10.2903/j.efsa.2013.3005](https://doi.org/10.2903/j.efsa.2013.3005)）：群体平均需要量 = Henry (2005) REE × PAL，预设 1.4 / 1.6 / 1.8 / 2.0（低活动、中等、主动、非常主动）。生活方式标签与实测 PAL **关系弱**；同一标签内跨度大。平均需要量针对**群体**，对个体只是粗指示。
- **NASEM 2023 DRI Energy**（[应用章](https://www.ncbi.nlm.nih.gov/books/NBK591020/)）：EER 用双标水测得的 TEE 回归；PALCAT（不活动 / 低活动 / 主动 / 非常主动）是该年龄段实测 PAL 的**四分位**，不是「本周是否达到 150 分钟中高强度」。报告写明：不能根据是否达到美加体力活动指南来判定 PAL 类别。不活动档已包含基础代谢、食物热效应和最低日常生活，大约 PAL 1.4。

官方需要量里，结构化训练已经进了那一个习惯 PAL。FAO 举例：每天约 1 小时中高强度运动，可以把久坐 PAL 1.55 抬到中等 1.75。EFSA 表 5：办公室工作析因 PAL 约 1.5；若要到 1.7，大约再加 0.6 小时 PAR 7 的跑步/骑车。这些小时是写进**典型日**的，不是「休息日系数另算、训练日再加一遍」。

### 析因表可以拆成「职业 + 当天运动」，但那是做账，不是发布需要量

FAO 表 5.1 和 EFSA 表 5 的做法是：

```text
当日 PAL = Σ (该段小时 × 该段 PAR) / 24
当日 TEE = BMR × 当日 PAL
```

「主动生活方式」示例里单独有一行「低强度有氧 1 小时、PAR 4.2」。所以**日历日台账**可以写成：

```text
当日 TEE = BMR × 不含结构化训练的 24h 析因 PAL
         + 当天各段运动的能量
```

这与「职业/家务/通勤系数 + 当天训练」同构。约束：

1. 基线 PAL **不能**再含「每周练几次」；否则训练热量会双计。
2. 若 24h BMR 已经乘过基线 PAL，运动段应加 **净增量** `(PAR − 1) × 小时 × BMR/24`，或 Compendium `(MET − 1) × kg × h`。Soma 记录卡上的总 MET 是毛消耗，含该小时静息。
3. 这是**当天析因**，不是 FAO/EFSA/NASEM 印在参考摄入量表上的那个数。官方表给的是习惯日均。

### 商业 1.2 / 1.375 / 1.55 / 1.725 / 1.9 不是 FAO 表

网上按「每周健身天数」选的 Mifflin 乘数，来自 Harris–Benedict 活动因子的消费改写，**不是** FAO 表 5.3，也不是 EFSA 的 1.4/1.6/1.8/2.0。它们输出**一周摊平的日均 TDEE**。指南口径是：选了含训练频率的乘数后，不要再把当日训练热量加进去。

### 「经常训练的人，休息日是否更高」

权威需要量**不**给「有训练习惯的休息日」单独更高的 PAL。有习惯的人被标成更高的**一个**平均 PAL，休息日和训练日在表上一样高。

生理学上休息日可以略高，但幅度小，且不是把 PAL 从 1.4 改成 1.6：

| 机制 | 权威/文献口径 | 数量级 |
| --- | --- | --- |
| 瘦体重更高 → 静息更高 | EFSA：规律运动可保存或增加 FFM，FFM 是 REE 主因；FAO BMR 主要由性别、体型、成分、年龄决定 | 已进 Mifflin/体重；不是另加活动系数 |
| 职业与 NEAT | EFSA：即使规律运动，**非运动产热通常远大于运动产热**；相近体型两人 NEAT 可差 8 MJ/日（约 1900 kcal） | 应进「不含训练」的生活方式系数，与是否办健身卡无关 |
| 运动后过量氧耗（EPOC） | FAO 测 BMR 要求前一日无剧烈运动；抗阻后恢复期升高有限（Melby 等 *J Appl Physiol* 1993：一次大容量抗阻后约 15 小时多消耗约 100 kcal，多数在 24 小时内回落） | 数十到约百 kcal，不是 +0.2 PAL（静息 1700 时约 +340 kcal/日） |
| 长期适应 | 双标水文献里，自由生活 24h TEE 往往不随「我有训练习惯」等比例上涨；约束 TEE 假说认为长期不完全可加 | 官方需要量仍用测得或习惯 PAL，不用「习惯加成」 |

结论：休息日比完全不训练的人高，主要是**更重/更多瘦体重**和**日常走动更多**，不是「因为这周练过所以休息日系数上调」。把「最近训练量」写进休息日系数，没有 FAO/EFSA/NASEM 公式支持。

### 对 Soma 的含义

两套官方兼容算法，不要混用：

| 用途 | 标准算法 | 若采用则注意 |
| --- | --- | --- |
| 一周该吃多少 / 目标热量 | FAO、EFSA、NASEM：一个习惯 PAL × 静息 | 训练频率进 PAL，日历上训练日与休息日相同；不要再加当日 MET |
| 日历上「今天烧掉多少」 | FAO/EFSA 析因：当天各段时间 × PAR | 基线只要职业与日常 NEAT；当天训练用净增量另加；休息日不再吃训练习惯 |

用户直觉「训练日应高于休息日」对应第二行。用户直觉「有训练习惯的休息日也应更高」在官方表里被第一行摊平；在第二行里只保留体重/成分和职业 NEAT，不保留「本周容量」。

进展按第二行做日历账：系数只描述日常，默认 1.4 仍是久坐日常下限，不改成 1.20。训练日另加净增量。第一套「一周该吃多少」仍可用七个日历日平均得到，不另做习惯 PAL。

## 边界

**用：**

- 身体资料上的 Mifflin–St Jeor 静息
- 用户确认的活动系数；未确认则 1.4
- Soma 已保存训练记录上的 Compendium MET（记录卡写完整热量；日总计只加去重增量）

**不用，且代码已删除：**

- HealthKit / Apple Watch 的 `basalEnergyBurned`、`activeEnergyBurned`
- 设置「健康数据与设备」导入体重与训练
- Keep / COROS 经 Apple 健康的说明入口
- 设备 30 日中位 PAL

手表热量、覆盖率和导入去重以后单独设计，不能把旧读取路径加回。

## 生理约束

```text
当日 TEE = RMR × PAL_base(不含当天训练) + Σ 去重增量
去重增量 = 完整热量 × (MET − 1) / MET
```

1.4 是久坐日常，不是「每周练几次」。记录卡的完整热量含训练时段静息，日总计只加多出来的那截。

## 已落地

- 无 HealthKit 源文件、用途说明与 entitlement
- 进展快照只做本地投影
- 设置根页无健康同步
- 日总计加入去重后的训练增量；默认系数仍是 1.4

## 明确不在范围

- 在本调研里重新设计手表热量
- 体重反推 TDEE
- 删除库里已经存在的导入记录

## 参考

- FAO/WHO/UNU. *Human energy requirements*, 2004, ch. 5. <https://www.fao.org/4/y5686e/y5686e07.htm>
- EFSA NDA Panel. Scientific Opinion on Dietary Reference Values for energy. *EFSA Journal* 2013;11(1):3005. doi:10.2903/j.efsa.2013.3005
- NASEM. *Dietary Reference Intakes for Energy*, 2023, Applications. <https://www.ncbi.nlm.nih.gov/books/NBK591020/>
- Ainsworth BE et al. 2011 Compendium of Physical Activities. *Med Sci Sports Exerc*
- Melby C et al. Effect of acute resistance exercise on postexercise energy expenditure and resting metabolic rate. *J Appl Physiol* 1993
- Mifflin MD et al. *Am J Clin Nutr* 1990
- Soma：`RestingEnergyCalculator`、`AdaptiveEnergyEstimator`、`WorkoutCalorieCalculator`
