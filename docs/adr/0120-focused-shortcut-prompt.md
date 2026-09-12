# ADR 0120：选中快捷按钮后收窄提示词与工具

- 状态：已采纳
- 日期：2026-09-07
- 维护者：Soma maintainers
- 上游依据：[PRD 057](../prd/057-coach-focus-progress-rings-and-library-clarity.md)
- 部分替代：[ADR 0000](0000-origin-through-0.0.11.md) 第 15 条仅补充「选中后仍披露全量 Skill 目录」的隐含口径；工具白名单本身不变
- 后续修订：[ADR 0136](0136-agent-user-questions.md)（提问工具始终可用，业务工具仍按快捷按钮收窄）

- 后续替代：[ADR 0137](0137-agent-context-management.md)（冻结实际配置；保留快捷聚焦与工具权限）

## 背景

快捷按钮已经收窄 API `tools`，但 System 仍注入全部 Skill 目录和能力清单，用户轮再附一份完整
Skill。模型仍可能改去加载其他方法，轮次和误选都没有真正下降。

## 决策

- 未选快捷按钮：System 仍披露身份、契约、能力目录和全部 Skill 元数据；模型按需 `load_skill`。
- 选中快捷按钮：System 只保留固定身份、可编辑人格和安全／真实性契约。能力目录与 Skill 目录省略。
  选中 Skill 全文只出现在当前用户轮。信封 `skills` 只含这一份。默认白名单去掉 `load_skill`。
- 上下文包按 Skill 收口：记录饮食保留当日餐食与必要身体信息；训练记录保留当日训练、当前场馆与
  体重；近期分析保留近 7／28 天摘要。权威本地时间和对话历史不删。
- 固定契约不可省略。自定义快捷按钮未绑 Skill 时，只收窄工具，不假装已注入方法。

## 未选择的方案

- 连契约一并省略：安全与「缺失即空」会被用户提示覆盖。
- 继续注入目录但加一句「不要用其他 Skill」：实测仍增加选择面。
- 为每个按钮手写第二套 System：与单一协议信封冲突。

## 结果

### 正向影响

- 明确任务时减少无关方法、无关工具和无关摘要，降低轮次与误选。

### 成本与限制

- 用户中途改口到按钮范围外的任务，需要取消选择或再发一轮。这是刻意的聚焦，不是缺陷。

## 验证

`AgentInputShortcutTests`、`AgentPromptCustomizationTests` 覆盖默认标题、白名单和「选中后 System
不含目录」。`make verify`。

## 参考

- [PRD 057](../prd/057-coach-focus-progress-rings-and-library-clarity.md)
- [ReAct 协议](../react-agent.md)
