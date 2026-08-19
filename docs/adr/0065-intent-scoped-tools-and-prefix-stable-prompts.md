# ADR 0065：Tool 按副作用意图暴露，Prompt 使用版本化稳定前缀

- 状态：部分已替代；原生 Tool Calling 与稳定 Prompt 前缀继续有效，按意图预选 Tool 由 ADR 0081 替代
- 日期：2026-08-13
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0050](0050-per-turn-tool-group-exposure-and-parallel-calls.md) 中 mutation 属于常驻 core 工具组的边界
  - [ADR 0059](0059-precise-tools-and-reviewable-meal-items.md) 中 `mutate_user_data` 对每轮模型默认可见的边界
- 上游依据：[PRD 027](../prd/027-reliable-efficient-react-and-in-context-review.md)
- 后续替代：
  - [ADR 0069](0069-layered-agent-prompt-skill-middleware-and-typed-tools.md) 用 Skill 绑定的最小强类型 Tool 集与条件 User Prompt 修订通用分组
  - [ADR 0081](0081-default-full-tool-registration-and-selected-skill-subset.md) 取消按副作用意图预选；未选 Skill 注册完整当前协议 Tool

## 背景

原生 Tool Calling 本身没有问题；低效来自常驻 mutation、重复查询和动态内容出现在 prompt 前部。
这增加 schema prefill、无意义 Tool Call 和跨 step 前缀变化。

## 决策

1. Tool 仍以 OpenAI-compatible `tools` JSON Schema、`tool_choice=auto`、原生 `tool_calls` 和
   `role=tool` 回执工作；模型不能修改 Tool 名称、schema 或执行协议。
2. `core` 只包含 `load_skill`、`query_user_data`、`expand_tool_group`；
   `mutate_user_data` 移入 `records`，仅明确记录、更新或删除意图预选。
3. System Prompt 保持稳定身份、产品真值和工具纪律；不要放当前日期、当前媒体或记录摘要。
4. User Prompt 固定为 `[SOMA CURRENT TURN v1]`，依次放执行约束、可信本地上下文、当前用户输入、
   当前媒体清单。各 section 即使为空也保持顺序。
5. Tool 定义按稳定枚举顺序编码；中途只有模型明确请求 expansion 才扩大集合。后续 step 只在尾部
   追加 assistant/tool 消息，历史视觉内容使用稳定占位。
6. Prompt 明确要求：一般建议可直接回答；仅在缺少回答所需事实时查询；仅在用户明确要求副作用
   时写入；本地摘要已给出的事实不得重复查询。

## 未选择的方案

- 不切换到自定义决策 JSON，不动态生成 Tool，也不把全部业务 Schema 常驻每个请求。

## 结果

### 正向影响

- 客户端只创造 prefix cache 的必要条件，不宣称供应商必然缓存或给予折扣。
- 将写 Tool 移出 core 可能需要一次 `expand_tool_group` 兜底；确定性意图分类与测试必须覆盖常见
  记录语句。

### 成本与限制

- 动态字段留在 user prompt 后部，不能为了“更自然”随意改变 section 标题和顺序。

## 验证

- `AgentReliabilityTests` 验证建议不暴露 mutation、记录意图暴露 records，以及 User Prompt section 顺序。

## 参考

- [Agent Tool 目录](../engineering/agent-tool-catalog.md)
- [默认 Prompt 来源目录](../engineering/prompt-source-catalog.md)
