# ADR 0078：批量创建动作与训练记录，模型不指定记录 ID

- 状态：部分已替代
- 日期：2026-08-18
- 维护者：Soma maintainers
- 部分替代：[ADR 0069](../../0.0.6/adr/0069-layered-agent-prompt-skill-middleware-and-typed-tools.md) 中 `create_exercise` 单名称、`create_workout` 单条对象的广告 Schema
- 后续替代：[ADR 0079](0079-create-inserts-update-by-id.md) 删除「整批重试靠同一 Turn 同一动作身份合并」
- 上游依据：
  - [PRD 030](../../0.0.6/prd/030-agent-prompt-skill-context-and-tool-v3.md) 的强类型 Tool、Int64 业务身份与固定写入授权
  - [BUG 0023](../../../bugs/0023-same-turn-multi-exercise-merged-into-one.md) 的一条消息多动作写入路径
  - [ADR 0077](0077-same-turn-identity-merge-and-additive-inline-review.md) 的原位审查卡与 Event Cards 共存
- 修订自：[ADR 0071](../../0.0.6/adr/0071-integer-business-identities-and-explicit-relations.md) 的本机单调 Int64 分配，模型不发明业务 ID

## 背景

用户常用一条消息描述整堂训练。旧广告 Schema 要求模型为每个新动作、每条训练记录各调用一次
Tool，增加步数、失败面和合并压力。训练 `record_id` 已由本机 `BusinessIDAllocator` 分配，模型
再填写只会猜错或夹带未声明字段。

## 决策

1. 新请求只广告 schema 3：`create_exercise` 必填 `exercise_names`（1–20），`create_workout`
   必填 `workouts`（1–20）。每条训练必须带已有 `exercise_id`，可选 `occurred_at` 与逐组事实。
2. 广告 Schema 不含 `record_id`。新训练记录 ID 只由本机分配；更新/删除仍用精确 `record_id`。
3. `create_workout` 不得用动作名隐式建动作。流程仍是 `search_exercises` → 必要时一次
   `create_exercise` → 一次 `create_workout`。
4. 旧 schema 2 单对象形状只用于 Checkpoint / 远程 Job 恢复；执行器在 `workouts` 为空时仍接受
   顶层 `exercise_id`。整次成功调用由 `AgentMutationReceipt` 去重。
5. 已存在的标准名在批量创建中复用原 `exercise_id`，不报错、不复制动作。

## 未选择的方案

- 新工具名 `create_workouts`：增加暴露面，恢复链更复杂。
- 让 `create_workout` 接受动作名并隐式创建：违反 ADR 0071 的明确关系。
- 要求模型指定 `record_id`：与本机分配器重复，且无法在写入前知道 ID。

## 结果

### 正向影响

- 一堂课通常一次写 Tool 即可落多条可审查训练记录。
- 模型不再猜测新建记录 ID。
- 聊天按 `record_refs` 逐条投影原位审查卡：一次批量写入仍保留 N 张编辑卡，并与折叠的
  Event Cards 共存（[ADR 0077](0077-same-turn-identity-merge-and-additive-inline-review.md)）。

### 成本与限制

- 远程注册表与设备 Schema 必须同步升到 3，并保留 schema 2 恢复路径。
- 单次上限 20 条；更大课表拆成多次调用。

## 验证

- `SomaTests/AgentBatchCreateToolTests.swift`、schema 2 恢复校验、iOS/Server 注册表门禁。
- `make check`、`make verify`。

## 参考

- [Agent Tool 目录](../../../engineering/agent-tool-catalog.md)
- [训练领域模型与运行时协议](../../../engineering/training-domain-model.md)
