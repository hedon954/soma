# ADR 0049：规范化幂等键与业务级重复识别

- 状态：已采纳
- 日期：2026-08-05
- 维护者：Soma maintainers
- 部分替代：[ADR 0018](0018-provenance-aware-record-merge.md) 中「仅靠纠错语义/共享媒体做跨 Turn 合并，缺少显式疑似重复反馈」的缺口
- 后续修订：[ADR 0079](0079-create-inserts-update-by-id.md) 删除 create 路径上的纠错词合并；跨 Turn 疑似重复反馈与回执幂等仍有效
- 上游依据：[PRD 022](../prd/022-react-reliability-and-context-awareness.md)

## 背景

Turn 级 `AgentMutationReceipt` 用完整 tool call JSON 作签名。`exercise` 与
`exercise_name`、缺省与显式 null 等字面差异会绕过回执。失败路径不写回执，重试可重复写。
跨 Turn 重复描述则依赖 RecordMergePolicy 的纠错关键词，五分钟内无纠错语义会留下两条记录。

## 决策

1. `AgentToolCall.signature` 改为规范化语义键：trim、同义字段归一、数值精度归一、
   nil≡缺省；`set_entries` 保持顺序（ADR 0023）。
2. Receipt 增加 `pending | committed | failed`；只有 committed 才重放；failed 不挡重试。
3. `record_*` 增加业务键（日期桶 + exerciseID/标题 + 组次指纹）。跨 Turn 命中时返回
   「疑似重复 + 既有 ID」，**不静默合并**。
4. 计划创建用内容指纹识别同名同内容；`start_guided_workout` 复用同计划未完成 Session。
5. 循环内相同只读调用复用上次结果并告知模型已查过。

## 未选择的方案

- 静默跨轮合并所有相似记录：违反 Truth over completeness，也掩盖用户意图。
- 仅保留字面 JSON 签名：无法挡住常见同义参数差异。
- 全局（跨 Turn）MutationReceipt：会错误阻止合法的重复记录意图。

## 结果

### 正向影响

- 同 Turn 重试与并行 tool_calls 更安全。
- 跨 Turn 重复得到可审查提示，而不是悄悄多写。

### 成本与限制

- 业务键是启发式；真正需要两条相似记录时，模型需说明差异后再写。
- 旧 Receipt 无 status 字段时按 committed 兼容。

## 验证

- 签名等价类测试；failed receipt 不挡重试；跨 Turn 疑似重复只保留一条。

## 参考

- [PRD 022](../prd/022-react-reliability-and-context-awareness.md)
- [ADR 0018](0018-provenance-aware-record-merge.md)
- [ADR 0023](0023-ordered-workout-set-evidence.md)
