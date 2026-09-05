# ADR 0103：目标导向的能量与增肌进展快照

- 状态：已采纳
- 日期：2026-08-26
- 维护者：Soma maintainers
- 修订自：[ADR 0102](0102-source-workout-plan-execution-materialization.md)
- 部分替代：[ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 的通用训练概览首屏
- 后续替代：
  - [ADR 0104](0104-independent-react-timeouts-by-media.md)
  - [ADR 0107](../../0.0.18/adr/0107-foreground-recovery-and-progress-evidence-projection.md)（部分替代集中指标说明与仅显示截至当前消耗的边界）
- 上游依据：
  - [PRD 046](../prd/046-coach-records-and-goal-directed-progress.md)
  - [目标导向进展指标调研](../../../research/2026-08-26-goal-directed-progress-metrics.md)
- 下游落地：[验收矩阵](../../../acceptance.md)

## 背景

通用训练概览没有回答减脂用户的能量收支，也没有回答增肌用户的训练量与肌群覆盖。现有饮食、
训练、身体记录和 HealthKit 已能在本机提供更直接且可解释的指标。

## 决策

1. `FitnessGoal` 收敛为增肌、减脂、增肌减脂；进展首卡按目标选择能量、增肌或两者。
2. 当日摄入汇总有热量事实的饮食。活动和静息消耗优先 HealthKit；读取不到时，活动使用 Soma 训练
   的净 MET 活动量 `(MET-1)×kg×小时`，静息使用 Mifflin–St Jeor 并按今日已过比例折算。
3. 增肌快照展示近 7 天训练日、可计算容量与主要肌群工作组覆盖。只统计 `primaryMuscles`，热身组
   排除，辅助肌群不重分类；当前不建立无个体依据的好坏阈值。
4. 每组估算均有信息入口说明数据来源、公式与缺失条件。未知保持空，不用 `0` 冒充。

## 未选择的方案

- 不用单一“训练次数”卡服务所有目标；信息与目标不匹配。
- 不把辅助肌群累计为主要肌群，也不设置无个体依据的达标色。
- 不用模型计算热量；来源、公式和缺失条件必须确定。

## 结果

### 正向影响

同一进展页能回答“今天能量收支如何”和“本周增肌刺激覆盖如何”。

### 成本与限制

未授权 HealthKit 或资料不完整时只能使用有界本地回退或显示未知；不是医疗或减重处方。

## 验证

纯公式单元测试、HealthKit 授权
边界、目标切换与浅深主题模拟器验收共同验证；本 ADR 不替代 Release 真机性能量化。

## 参考

- [目标导向进展指标调研](../../../research/2026-08-26-goal-directed-progress-metrics.md)
- [Apple HealthKit](https://developer.apple.com/documentation/healthkit)
