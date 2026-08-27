# BUG 0044：Tool 参数类型漂移中断 ReAct

- 状态：已修复，待真机交互验收
- 发现日期：2026-08-28
- 影响范围：教练中涉及记录纠正的本地与远程 Tool 调用
- 上游依据：维护者真机反馈
- 下游落地：
  - [PRD 051](../prd/051-self-healing-tool-arguments-and-wide-progress-disclosure.md)
  - [ADR 0109](../adr/0109-schema-guided-tool-argument-recovery.md)

## 症状

用户用自然语言修正一条记录的份量后，兼容模型把数值字段返回为字符串，聊天直接显示“格式不正确”
的执行失败；模型没有机会自行修正。

## 根因

Tool Schema 没有明确告诉模型 JSON 数字与自然语言分数的转换方式。更关键的是，流式 Tool 参数在
写入 `assistant.tool_calls` 之前就被 `JSONDecoder` 严格解码；类型错误直接抛出 Loop，既没有对应
`tool_call_id` 的错误结果，也没有下一模型步骤。

## 修复

- Schema 数字说明明确 JSON integer/number 和分数转小数。
- 本地与远程按 Schema 递归归一化安全数字字符串，并继续执行严格范围与业务校验。
- 已知 Tool 的参数错误保存为可重试 Tool 结果和检查点；模型下一步可更正，安全协议错误仍终止。

## 回归门禁

- 自动化测试：本地嵌套数字/分数归一化、带单位拒绝、`role: tool` 自纠；远程 Worker 错误回送与重排队。
- 手工验收：用虚构饮食记录执行“三分之一份”纠正，不直接出现格式失败，最终只写入一次更新。
- 仍无法自动化的风险：具体 Provider 是否首次严格遵循 Schema 只能在真实模型调用中观察。

## 验证

`make check`、`make verify` 已通过；模拟器已检查浅色、深色与 XXXL 字号。真机份量纠正交互仍待
维护者使用真实 Provider 验收。
