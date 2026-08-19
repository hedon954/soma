# ADR 0077：同一 Turn 合并必须身份匹配，原位审查不得替换 Event Cards

- 状态：部分已替代
- 日期：2026-08-18
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0018](0018-provenance-aware-record-merge.md) 中「同一 sourceTurnID 永远更新原记录」、不核对动作或餐次身份的边界
  - [ADR 0064](0064-deterministic-quick-write-and-latest-inline-review.md) 中未写明原位卡与 Event Cards 共存、保存无确认的实现缺口
- 后续替代：[ADR 0079](0079-create-inserts-update-by-id.md) 删除 create 路径上「同一 Turn 按身份合并」；原位审查卡与保存确认仍有效
- 上游依据：
  - [PRD 020](../prd/020-gui-simplification-and-progressive-disclosure.md)
  - [PRD 027](../prd/027-reliable-efficient-react-and-in-context-review.md)
  - [BUG 0023](../bugs/0023-same-turn-multi-exercise-merged-into-one.md)
- 下游落地：
  - [ADR 0078](0078-batch-create-exercise-and-workout.md) 批量写入仍按 `record_refs` 逐条投影原位卡
- 修订自：[ADR 0014](0014-agent-turn-ordered-event-cards.md) 的有序 Event Cards 必须持久可见

## 背景

一条用户消息经常包含一次课的多个动作。Agent 按固定 Tool 为每个动作各写一次是正确遵循。
把「同一 Turn」直接当成「同一条训练记录」，会把硬拉、引体、深蹲收成一条，并让原位卡只
显示错配后的最后动作名。同时，用结果卡替换 Skill/Tool 事件会让用户无法审查 Agent 实际
执行过什么。

## 决策

1. 同一 `sourceTurnID` 只更新**身份匹配**的原记录：
   - 训练：相同 `exerciseID`，或规范化动作名相似度 ≥ 0.8；
   - 饮食：相同餐次且标题相似度 ≥ 0.55；
   - 身体：一次测量仍按同一 Turn 合并。
2. 同一 Turn、不同身份且无纠错语义时必须新增。纠错语义仍可走原有跨记录阈值，但不能仅凭
   Turn ID 吞掉另一个动作。
3. 相同 Tool Call 的重放继续由 `AgentMutationReceipt` 幂等，不靠「Turn 内第一条记录」。
4. 原位审查卡按 `record_refs` 逐条投影：一次 Tool 写入 N 条记录就渲染 N 张卡，与文字、
   Skill、Tool、错误 Event Cards 同时保留。连续成功的 Skill/Tool 默认收成一条可展开过程摘要，
   展开后仍能逐条审查；折叠不等于删除。原位卡渲染在过程与文字之后，避免把教练结论顶出屏幕。
5. 原位保存成功必须把保存控件改为已保存态并给出成功触觉；校验失败保持可再试，不假装成功。

## 未选择的方案

- 继续「同一 Turn 永远更新」：会把一堂课收成一条记录。
- 从模型最终回复反解析多动作：违反 Tool 是唯一写入路径。
- 自动拆分已经错配的历史记录：缺少可恢复的逐组事实，不能猜测。

## 结果

### 正向影响

- 一条消息里的多个动作成为多条可审查训练记录。
- 聊天仍能看到 Agent 实际调用了哪些工具。
- 用户保存后知道本机已经写入。

### 成本与限制

- 同一 Turn 内把动作名从「深蹲」改成完全不相似的名称，若没有纠错语义，会留下两条记录。
- 已错配的旧记录需要用户重新发送或手工补写。

## 验证

- 同一 Turn 不同动作 / 同一动作、不同饮食，有 `record_refs` 时仍保留 Tool Event，以及一次
  批量 `create_workout` 投影出全部原位卡的确定性测试。
- `make verify`。

## 参考

- [PRD 004](../prd/004-soma-current-product.md) 的有序 Event Cards 基线
- [PRD 027](../prd/027-reliable-efficient-react-and-in-context-review.md)
- [ADR 0014](0014-agent-turn-ordered-event-cards.md)
- [ADR 0018](0018-provenance-aware-record-merge.md)
- [BUG 0023](../bugs/0023-same-turn-multi-exercise-merged-into-one.md)
