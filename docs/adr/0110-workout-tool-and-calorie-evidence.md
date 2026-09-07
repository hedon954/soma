# ADR 0110：训练 Tool 与热量共用逐组证据

- 状态：已采纳，已实施；待真机交互验收
- 日期：2026-09-02
- 维护者：Soma maintainers
- 部分替代：无
- 后续替代：[PRD 058](../prd/058-feedback-duration-and-editable-calories.md) 仅补充预计消耗可被用户改写，公式仍是默认填充
- 上游依据：[PRD 052](../prd/052-coach-training-and-lifecycle-reliability.md)

## 背景

旧训练 Tool 无法完整表达左右 effort、逻辑组与逐组休息，模型即使理解自然语言也无法可靠落盘；
普通训练与带练的热量入口又各自依赖不完整字段，结果经常为空。

## 决策

- `search_exercises`、动作新建/更新和训练新建/更新采用 Schema v4。动作携带 `target_kind` 与
  `laterality`；逐组 evidence 携带 `logical_set_index`、`side`、`target_kind`、值和
  `rest_seconds`。App、Server、签名与校验器使用同一闭合契约。
- v2/v3 只恢复旧持久任务；v3 保持严格未知字段和范围校验，但不再向模型广告。
- 普通训练与带练调用同一个确定性热量计算器：实测总时长优先，否则按逐 effort 的实测时长或
  每次 4 秒，加上明确记录的休息。使用发生时间前最近一次有效体重，并保存 MET、时长和推算标记。
- 显式训练 evidence 优先于动作定义；只有字段确实缺失时才使用动作库 fallback。

## 未选择的方案

- 不依赖 Prompt 猜侧别，也不把“左右各”压成一个 `.none` effort。
- 不新增另一套训练持久字段；继续使用 `WorkoutSetEvidence` 和现有热量派生字段。
- 不在缺体重或不完整工作证据时显示 `0 kcal`。

## 结果

训练侧别和热量由可审查事实决定；代价是协议升级需要同时维护旧 Job 恢复校验和 App/Server 对照测试。

## 验证

- Schema 闭合/冲突、左右 paired effort、异构组、历史体重、无体重、自重、编辑重算和带练投影测试。
- `make check`、`make verify` 与真机 Agent 交互验收。
