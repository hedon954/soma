# ADR 0028：动作使用稳定 ID，大模型基于完整名称列表完成语义归一

- 状态：已采纳
- 日期：2026-07-31
- 维护者：Soma maintainers
- 部分替代：无
- 后续替代：
  - [ADR 0059](../../0.0.4/adr/0059-precise-tools-and-reviewable-meal-items.md) 用搜索、分页和字段投影替代每轮完整名称列表；稳定动作 ID 保持不变
  - [ADR 0071](../../0.0.6/adr/0071-integer-business-identities-and-explicit-relations.md) 将动作身份表示迁移为 Int64，并建立明确关系
- 上游依据：[动作库、训练计划、带练与视频复盘调研](../../../research/2026-07-31-exercise-library-plans-guided-training.md)
- 下游落地：[训练领域模型与运行时协议](../../../engineering/training-domain-model.md)
- 关联：
  - [PRD 010](../prd/010-exercise-library-plans-guided-training.md)
  - [ADR 0035](0035-silent-bundled-exercise-content-and-on-demand-images.md)

## 背景

当前训练记录只保存动作字符串。自然语言中的错别字、漏字、简称和同义表达会切碎历史，而
器械、角度、单双侧或动作模式不同的动作又不能仅因名称相近而合并。

Soma 的输入天然由大模型理解。再建立本地模糊匹配、向量检索与大模型投票会形成第二套语义
事实，并在冲突时无法解释谁拥有最终决定权。

## 决策

1. 新增当前数据空间内唯一的 `ExerciseDefinition.id`，所有新训练、计划、媒体和分析引用 ID。
2. `canonicalName` 是可编辑的个人标准名称，不是全球统一动作本体。
3. 新增固定 Tool `list_exercise_names`，无参数，返回当前数据空间全部动作：

   ```json
   {
     "exercises": [
       { "id": "UUID", "name": "杠铃前蹲" }
     ]
   }
   ```

4. Tool 不返回训练历史、组次重量、媒体、内部状态或相似度，也不执行搜索。
5. Agent 在每次创建训练或计划动作前读取列表，并负责语义判断：
   - 真正同义、错别字、漏字和简称复用已有 ID；
   - 器械、角度、单双侧或动作模式实质不同则选择其他 ID 或创建新动作；
   - 没有合适动作时生成清晰标准名称。
6. `record_workout` 复用动作时要求 `exercise_id`；创建动作时要求 `exercise_name`。
7. 本地层只负责 ID 存在性、当前空间名称唯一性、事务引用完整性和跨 Attempt 幂等，不建立
   另一套语义判定。
8. ID 不存在时返回可恢复错误，Agent 必须重新调用 `list_exercise_names`，不能按旧名称猜测。
9. 用户可以改名、归档、合并和撤销最近一次合并。合并事务迁移所有引用并保存合并日志。
10. 原始用户说法继续保存在 Turn 和训练原文中，不被标准名称覆盖。

## 未选择的方案

- 仅按字符串或本地模糊距离去重：无法可靠理解中文简称与动作变式。
- 本地规则与大模型共同投票：产生两个语义权威，冲突行为不可预测。
- 只返回名称不返回 ID：模型无法稳定引用，改名后历史再次割裂。
- 向 Tool 传入查询并只返回 Top-K：错误召回会隐藏正确动作，模型看不到完整个人词表。
- 建立不可编辑的全球动作库作为唯一事实：无法适应用户个人命名和器械差异。

## 结果

### 正向影响

- 同一动作历史不依赖运行时名称比较。
- `list_exercise_names` 同时满足语义选择和稳定写入引用。
- 用户可以纠正动作身份而不逐条修改历史训练。
- 输入框本地候选与发送后的 Agent 归一可以共享同一动作事实。

### 成本与限制

- 完整名称列表会占用上下文；出现实际规模问题前不引入隐藏候选的 Top-K。
- 大模型仍可能选错动作，因此合并、撤销和可审查性是必要产品能力。
- 现有记录只能依据已有字符串进行一次迁移建议，不能伪造确定性语义。

## 验证

- Tool Schema 测试固定返回 `id` 与 `name`，并拒绝额外敏感字段。
- 测试空列表、失效 ID、同名并发创建、跨数据空间隔离和重复 Attempt。
- 使用虚构中文错别字、漏字、简称和变式集合验证 Agent 行为。
- 动作改名后历史、计划、媒体和分析仍指向同一 ID。
- 合并事务完整迁移引用，撤销后恢复原引用且统计不重复。

## 参考

- [PRD 010](../prd/010-exercise-library-plans-guided-training.md)
- [ADR 0004](0004-progressive-skills-fixed-tool-contract.md)
- [ADR 0016](0016-conversation-turn-attempt-and-footprint-projection.md)
