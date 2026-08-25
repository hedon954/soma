# ADR 0069：分层 Agent Prompt、Skill Middleware 与强类型 Tool

- 状态：部分已替代；分层 Prompt、Skill Middleware 与强类型 Tool 继续有效，`create_exercise` / `create_workout` 的单条广告 Schema 由 ADR 0078 修订，未选 Skill 的 Turn 信号剪枝由 ADR 0081 替代
- 日期：2026-08-15
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0004](../../0.0.1/adr/0004-progressive-skills-fixed-tool-contract.md) 中只有固定枚举 Skill 且只编辑正文的边界
  - [ADR 0059](../../0.0.4/adr/0059-precise-tools-and-reviewable-meal-items.md) 中用通用查询与通用记录 CRUD 缩减 Tool 的边界
  - [ADR 0065](../../0.0.5/adr/0065-intent-scoped-tools-and-prefix-stable-prompts.md) 中固定 v1 User section 与通用 Tool 分组边界
  - [ADR 0068](0068-versioned-unified-agent-model-input.md) 中 v1 Prompt、Skill 快照和 Tool 协议版本
- 后续替代：
  - [ADR 0078](../../0.0.7/adr/0078-batch-create-exercise-and-workout.md) 将 `create_exercise` / `create_workout` 广告为批量数组，并禁止模型指定新建 `record_id`
  - [ADR 0081](../../0.0.7/adr/0081-default-full-tool-registration-and-selected-skill-subset.md) 取消按当前 Turn 信号剪枝与普通建议空 Tool 集
  - [ADR 0082](../../0.0.7/adr/0082-shortcut-owned-tool-bindings-and-method-only-skills.md) 取消 Skill 声明工具白名单，
    改由输入框快捷按钮持有工具绑定
- 上游依据：[PRD 030](../prd/030-agent-prompt-skill-context-and-tool-v3.md)

## 背景

通用 CRUD 的字段联合与条件必填只存在于描述和运行时校验，Provider 无法稳定约束；Skill 需要
额外 `load_skill` step，快捷语又不能绑定 Skill、上下文或 Tool。可编辑安全策略还会把系统契约
和用户人格混为同一权限层。

## 决策

1. System Prompt 分为固定身份、可编辑人格、固定安全/真实性/授权契约、能力目录和 Skill 目录；
   固定契约不可编辑，Tool 名称不进入 Prompt。
2. Skill Markdown frontmatter 只有 `name`、`description`、`when_to_use`；正文可编辑。内置内容、
   用户 override、自定义 Skill 和快捷绑定由版本化本地 Registry 管理。
3. Tool/上下文绑定只允许 App 白名单。选中快捷 Skill 后 Middleware 首轮直接注入全文与绑定，
   不暴露 `load_skill`；未选 Skill 的任务仍可按目录渐进加载。
4. `query_user_data`、`mutate_user_data` 被单一职责的动作、训练、饮食、身体和计划 Tool 取代。
   每个 Schema 只包含对应操作字段，禁止额外属性，并由设备二次校验。
5. Tool Exposure Middleware 优先使用选中 Skill，其次使用确定性当前 Turn 信号。普通建议无业务
   Tool；通用模糊任务只保留轻量 runtime capability 逃生路径。
6. iOS 生成全部 Skill 快照、Tool 定义和 active set；本地与远程消费同一版本化 Envelope。

## 未选择的方案

- 不继续在描述里表达 `mutate_user_data` 的条件联合；它不能可靠防止跨记录类型夹带字段。
- 不允许 Skill Markdown 声明任意 Tool、URL 或代码。
- 不让快捷按钮只填充一段文字；它必须形成可审查的执行配置快照。

## 结果

### 正向影响

- 常见快捷记录少一次 Skill/Tool 展开步骤，Schema 更易被模型和设备共同验证。
- 用户可以定制方法与入口，但不能改变固定系统和副作用边界。

### 成本与限制

- Tool 数量增加，必须依靠精确暴露而不是全量发送。
- 内置 Skill override、旧自定义 Prompt 和远程注册表需要版本迁移。

## 验证

- Prompt/Skill 快照、Tool active set、严格 Schema、本地/远程 parity 和快捷一次写入测试。

## 参考

- [Agent Tool 目录](../../../engineering/agent-tool-catalog.md)
- [默认 Prompt 来源目录](../../../engineering/prompt-source-catalog.md)
