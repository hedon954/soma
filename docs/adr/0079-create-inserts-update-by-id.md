# ADR 0079：创建始终新增，纠正只走更新工具

- 状态：已采纳
- 日期：2026-08-18
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0018](0018-provenance-aware-record-merge.md) 中「每次业务写入先做候选匹配再决定新增或更新」、以及用纠错词/同一 Turn 在 **create** 路径上静默合并的边界
  - [ADR 0077](0077-same-turn-identity-merge-and-additive-inline-review.md) 中「同一 Turn 按动作/餐次身份合并」；原位审查卡与保存确认仍有效
  - [ADR 0078](0078-batch-create-exercise-and-workout.md) 中「整批重试靠同一 Turn 同一动作身份合并」
- 后续替代：暂无
- 上游依据：
  - [PRD 004](../prd/004-soma-current-product.md) 的当前产品基线
  - [PRD 030](../prd/030-agent-prompt-skill-context-and-tool-v3.md) 的强类型 create/update Tool
  - [PRD 006](../prd/006-footprints-location-and-retry.md) 的纠错应走更新工具
  - [PRD 027](../prd/027-reliable-efficient-react-and-in-context-review.md) 的原位审查
  - [BUG 0023](../bugs/0023-same-turn-multi-exercise-merged-into-one.md) 的一条消息多条写入
- 修订自：[ADR 0049](0049-normalized-idempotency-and-business-dedup.md) 的 Tool 回执幂等与跨 Turn 疑似重复反馈（不静默合并）

## 背景

一条用户消息、一次 ReAct Loop 里，模型可以在同一次响应发出多个 Tool Call，也可以分多步
连续写入。把同一 `sourceTurnID`、相似标题或纠错词当成「还是那一条记录」，会把多餐、多次
测量或同一动作的两段训练收成一条。身份匹配只是把错误检测做得更细，没有取消这条错误路径。

纠正、补图和改已有事实已经有 `update_*` 与稳定 `record_id`。创建路径再猜一次，属于重复逻辑。

## 决策

1. 训练、饮食、身体的 **create / record** 每次调用都插入新记录。同一 Loop、同一 LLM 响应
   的多个 Tool Call，或后续步骤的多次调用，都允许落下多条可审查记录。
2. 修改已有记录只走 **update**，必须使用查询得到的稳定 `record_id`；更新时仍合并本次新媒体。
3. 删除 create 路径上的同一 Turn、身份相似和纠错词候选匹配。不再根据「已经写过一餐/一个
   动作/一次身体测量」把新的 create 吞掉。
4. 相同 Tool Call 重放仍由 `AgentMutationReceipt` 幂等。跨 Turn 的业务键疑似重复仍按
   ADR 0049 返回既有 ID、不静默改写；饮食按 ADR 0059 不走该业务键。
5. Prompt 与 Tool 描述必须写清：新事实用创建，纠正/补图/改已有记录用更新，不能对调。

## 未选择的方案

- 同一 Turn 按身份合并：仍会吞掉同动作两段训练、相似餐名或同一次 Loop 里的第二次测量。
- 保留 create 上的纠错词安全网：模型该调用更新时仍会被创建路径悄悄改写。
- 永远禁止同一 Loop 写多条：与一堂课、两餐、多次测量的真实表达冲突。

## 结果

### 正向影响

- 一次对话里的多条训练、饮食、身体记录各自可审查。
- 创建和更新的职责不再混在执行器里。

### 成本与限制

- 模型误用创建表达纠正时会留下重复记录，用户需删除或再发更新。
- `create_workout` 部分失败后整包重试可能对已成功项再插入；整次调用成功仍由回执去重。

## 验证

- `RecordMutationTests`：同一 Turn 重复 create 训练、饮食、身体均保持独立记录。
- `make check`、`make verify`。

## 参考

- [ADR 0018](0018-provenance-aware-record-merge.md)
- [ADR 0049](0049-normalized-idempotency-and-business-dedup.md)
- [ADR 0077](0077-same-turn-identity-merge-and-additive-inline-review.md)
- [Agent Tool 目录](../engineering/agent-tool-catalog.md)
