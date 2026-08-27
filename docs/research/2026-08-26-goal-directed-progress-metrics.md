# 减脂与增肌目标导向进展指标调研

- 状态：已转化
- 日期：2026-08-26
- 下游落地：
  - [PRD 046](../archive/0.0.15/prd/046-coach-records-and-goal-directed-progress.md)
  - [ADR 0103](../archive/0.0.15/adr/0103-goal-directed-progress-energy-and-hypertrophy.md)

## 问题

进展页不应先决定画什么图，再寻找解释。首屏指标必须回答用户当前目标最直接的问题，并且让用户
能审查数值来自 Apple 健康、Soma 记录还是公式估算。

## 减脂与增肌减脂

减脂的首要反馈是能量收支，而不是孤立的训练次数：

```text
今日总消耗 = 静息消耗 + 活动消耗
今日能量结余 = 饮食摄入 - 今日总消耗
```

- 饮食摄入只汇总 Soma 当日有热量事实的饮食记录；缺失项不补值。
- 活动消耗优先读取 HealthKit `activeEnergyBurned`。Soma 本地训练若回退 MET 估算，应从保存的
  总消耗中扣除同时间静息部分，即使用 `(MET - 1) × 体重kg × 小时` 作为活动消耗。
- 静息消耗优先读取 HealthKit `basalEnergyBurned`；否则用 Mifflin–St Jeor：
  - 男：`10W + 6.25H - 5A + 5`
  - 女：`10W + 6.25H - 5A - 161`
  - `W` 为最新体重记录 kg，`H` 为身高 cm，`A` 为动态年龄。
- 公式给出每日静息能量，今日卡片按已过去的当天比例折算；缺少体重、身高、生日或支持的生理
  性别时保持未知，不猜测。

## 增肌与增肌减脂

ACSM 2026 立场文件强调：覆盖主要肌群、每周至少两次阻力训练、高努力程度，以及更高每肌群周
训练量与肌肥大的关联。因此 Soma 首屏采用可由现有事实可靠计算、又能引导计划审查的三项：

1. 近 7 天训练天数；
2. 近 7 天可计算训练容量；
3. 近 7 天主要肌群有效工作组覆盖。

覆盖只使用动作库的 `primaryMuscles` 和非热身工作组；辅助肌群不升级为主要肌群。当前不把组数
染成“达标/不达标”，因为个体训练史、动作选择、努力程度和目标肌群会改变阈值。后续自定义指标
可在这个确定性快照上插件式扩展。

## 参考

- Apple HealthKit：[`activeEnergyBurned`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/activeenergyburned)
- Apple HealthKit：[`basalEnergyBurned`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/basalenergyburned)
- Mifflin MD 等，1990：[`A new predictive equation for resting energy expenditure in healthy individuals`](https://pubmed.ncbi.nlm.nih.gov/2305711/)
- ACSM，2026：[`Resistance Training Prescription for Muscle Function, Hypertrophy, and Physical Performance in Healthy Adults`](https://pubmed.ncbi.nlm.nih.gov/41843416/)
