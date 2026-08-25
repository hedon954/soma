# ADR 0047：确定性上下文包与跨轮工具事实摘要

- 状态：已采纳
- 日期：2026-08-05
- 维护者：Soma maintainers
- 部分替代：[ADR 0024](../../0.0.1/adr/0024-session-context-projection-and-compaction.md) 中「更早对话当前不生成滚动摘要」「structuredContext 仅两行摘要」相关结论
- 后续替代：
  - [ADR 0056](../../0.0.4/adr/0056-trusted-selective-multimodal-context.md) 用可信时间、token 预算和短事实引用收敛上下文
  - [ADR 0070](../../0.0.6/adr/0070-reviewable-rolling-session-compaction.md) 用可审查的滚动摘要替代十轮外确定性意图 digest
- 上游依据：[PRD 022](../prd/022-react-reliability-and-context-awareness.md)

## 背景

[ADR 0024](../../0.0.1/adr/0024-session-context-projection-and-compaction.md) 固定最近十个来回全文，
并明确不做滚动摘要。当时的 structuredContext 只拼两行身体/健身房摘要。结果是模型对
「最近练得怎样」「刚才那条改一下」缺乏本机事实，只能连环调用读工具，既慢又容易漏。

## 决策

1. 用 `AgentContextPackBuilder` 生成有字符预算的确定性上下文包，覆盖近 7/28 天频次、
   肌群组数、最近训练日、当前计划与上次完成度、进行中带练、饮食与体重趋势、本会话近期写入。
2. 缺失字段保持不写；超预算按确定性截断顺序裁剪，不用常见值补齐。
3. 历史投影仍保留最近十轮 user/assistant 全文；额外注入近期成功 tool span 摘要。
4. 十轮以外的更早轮次只保留意图关键词与落库类型 digest，不做 LLM 摘要。
5. `query_user_data` 增加 date/group_by/metric，聚合在本地确定性服务完成。

## 未选择的方案

- LLM 滚动摘要：增加派生状态、更新时机和事实污染风险。
- 发送完整 Session：成本、延迟与隐私暴露无上限。
- 把聚合逻辑交给模型：违反 Deterministic where possible。

## 结果

### 正向影响

- 常见趋势与纠错问题可在更少步骤内完成。
- 上下文仍可审查，且全部由本机规则派生。

### 成本与限制

- 上下文包需要随新业务字段维护截断顺序。
- digest 有损，精确历史仍依赖查询工具。

## 验证

- 单元测试覆盖空库缺失即空、聚合 day 分组、跨轮事实摘要非空路径。
- Trace `contextSnapshot` 可见准备耗时与投影规模。

## 参考

- [PRD 022](../prd/022-react-reliability-and-context-awareness.md)
- [ADR 0024](../../0.0.1/adr/0024-session-context-projection-and-compaction.md)
