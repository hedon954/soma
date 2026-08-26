# ADR 0104：文字、图片与视频 ReAct 超时独立配置

- 状态：已采纳
- 日期：2026-08-26
- 维护者：Soma maintainers
- 修订自：[ADR 0103](0103-goal-directed-progress-energy-and-hypertrophy.md)
- 部分替代：[ADR 0000](0000-origin-through-0.0.11.md) 收口的统一自定义超时值
- 上游依据：
  - [PRD 000](../prd/000-origin-through-0.0.11.md)
  - [PRD 046](../prd/046-coach-records-and-goal-directed-progress.md)
- 下游落地：[验收矩阵](../acceptance.md)

## 背景

文字、图片和视频的典型首包与完整推理成本不同。一个统一自定义值会让放宽视频预算时也无意放宽
文字预算，无法表达用户对三类任务的真实边界。

## 决策

1. `ReActAgentPreference` 分别保存文字、图片、视频分钟数，默认 3/5/10，均夹取到 3–60。
2. 三类设置分别冻结到本地 deadline 和版本化远程模型输入；首增量门禁、活动时间累计、内部三次
   退避、步骤上限和人工恢复语义不变。
3. 旧统一 key 只在新 key 尚未写入时作为三类兼容回退；用户保存或恢复默认后移除旧 key。
4. 设置页同区显示三个 Stepper，不提供无限运行或关闭总预算。

## 未选择的方案

- 不继续使用单一自定义值；它不能保留媒体差异。
- 不提供无限预算；步骤上限无法替代网络和慢流的总时限。

## 结果

### 正向影响

三类任务可分别放宽或收紧，默认升级行为仍是 3/5/10。

### 成本与限制

设置项增加到三行；旧统一 key 只作为读取兼容，不再写入。

## 验证

`AgentReliabilityTests` 固定默认 3/5/10、独立 3/17/60、边界夹取和旧值回退；远程输入继续由既有
协议测试验证实际秒数。

## 参考

- [Agent 运行时设置](../../Soma/Views/ReActLoopSettingsSection.swift)
- [ADR 0000](0000-origin-through-0.0.11.md)
