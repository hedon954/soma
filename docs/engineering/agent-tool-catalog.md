# Agent Tool 目录

本文件维护当前代码实际支持的 Agent Tool、暴露策略和协议边界。它只做导航与审计，不复制
完整 JSON Schema；可执行事实以源码和测试为准。

## 事实来源

- 名称、描述、严格参数 Schema：`Soma/Services/ReActAgent.swift`。
- 分组与首轮最小暴露：`Soma/Services/AgentToolExposurePolicy.swift`。
- Skill 权限白名单：`Soma/Services/AgentSkillRegistry.swift`。
- 设备执行：`Soma/Services/ConversationRecorderTypedTools.swift` 及各领域扩展。
- 公共结果与本地二次校验：`AgentToolResultV2.swift`、`ConversationRecorderToolV2.swift`。
- 本地/远程统一输入：`AgentModelInput.swift`；远程注册表：`Server/src/tool-registry.ts`。
- 回归：`SomaTests/AgentPromptMigrationRefactorTests.swift`、`AgentReliabilityTests.swift`、
  `Server/test/`。

## 暴露策略

运行时共能解码 48 个名称，其中 32 个属于当前协议。每次请求只把当轮允许的子集放进 API
`tools` 参数；System Prompt 不声明 Tool 名称或 Schema。

- 通用建议：零 Tool。
- 未预选 Skill：App 根据当前输入确定性选择必要领域组；非空时附加 `load_skill`。
- 预选 Skill：直接注入完整 Skill Markdown、专属上下文，并只暴露该 Skill 声明且通过 App
  白名单的 Tool 组。
- 已经预加载的事实足够时不得重复查询。
- 恢复历史 Checkpoint 时可继续执行已持久化的兼容名称，但不会向新模型暴露。

## 当前 32 个 Tool

| 组 | Tool | 用途 |
| --- | --- | --- |
| core | `load_skill` | 未预选 Skill 时按 ID 读取当前生效 Markdown |
| exercises | `search_exercises`、`create_exercise`、`update_exercise`、`archive_exercise`、`merge_exercises` | 动作搜索、创建、修正、归档和合并 |
| workouts | `list_workouts`、`get_workout`、`create_workout`、`update_workout`、`delete_workout` | 训练记录单一职责 CRUD |
| meals | `list_meals`、`get_meal`、`create_meal`、`update_meal`、`delete_meal` | 饮食记录单一职责 CRUD |
| body | `list_body_entries`、`get_body_entry`、`create_body_entry`、`update_body`、`delete_body_entry` | 身体与体态记录单一职责 CRUD |
| plans | `list_programs`、`get_program`、`create_program`、`create_program_version`、`archive_program`、`delete_program`、`start_program` | 计划读取、创建、不可变新版本、归档、删除和带练启动 |
| gym | `update_gym`、`switch_gym` | 健身房与器械维护、当前场馆切换 |
| review | `record_performance_analysis` | 保存绑定 Performance 的视频复盘 |
| feedback | `submit_feedback` | 仅在当前 Turn 明确授权时提交产品反馈 |

## 输入契约

- 业务 `record_id`、`exercise_id`、`program_id`、计划动作 ID 均为正 `Int64`；UUID 只留给
  Session、Turn、Job、Trace、Event、媒体、外部来源和旧备份映射。
- `create_workout` 必须接收已经存在的 `exercise_id`。动作不存在时先
  `search_exercises`，确认无语义等价项后 `create_exercise`，再创建训练记录。
- 计划的每个动作也必须绑定动作库 `exercise_id`。
- 训练、饮食、身体 create/update 都支持可选 `occurred_at`。它是带时区 ISO-8601 时间；
  省略时使用 Job 从原始用户 Turn 冻结的 `defaultOccurredAt`，重试、排队和跨午夜不会漂移。
- list/get/create/update/delete 彼此独立；get/update/delete 必须传对应领域的精确 Int64 ID。
- 每个对象 Schema 都设置 `additionalProperties: false`；兼容 Provider 时发送 `strict: true`，
  设备仍执行本地未知字段、类型、ID、关系和授权校验。
- 删除、外发与高影响操作继续要求当前用户消息明确授权。

## 结果与错误

Tool 结果使用紧凑 envelope：

```text
ok, code, message, data?, record_refs?, page?, error?
```

- `record_refs` 返回业务类型和 Int64 ID，供 UI 与后续 Turn 稳定引用。
- 错误提供稳定的 `code/field/expected/retryable`，并以 `role: tool` 返回模型修正。
- 幂等签名包含解析后的业务 ID 和最终 `occurred_at`；成功写入在重试时不会重复发生。
- 原始参数、UUID 锚点和 Schema 版本只进入开发者 Trace，不进入普通聊天文案。

## 隐藏兼容名称

以下 16 个名称只用于历史 Job、备份或 Checkpoint 解码，不再进入新请求：

`query_user_data`、`mutate_user_data`、`list_exercise_names`、`list_training_programs`、
`get_training_program`、`record_workout`、`record_meal`、`record_body`、`delete_record`、
`create_training_program`、`create_workout_template_version`、`update_workout_template`、
`archive_training_program`、`delete_training_program`、`start_guided_workout`、
`expand_tool_group`。

`update_workout`、`update_meal`、`update_body` 名称继续属于当前单一职责协议，不是隐藏别名。

## 更新规则

- 新增、删除、重命名、隐藏 Tool 或改变 Schema/输出时，同一提交更新 iOS 注册表、Server
  注册表、统一 Envelope、本文和确定性测试。
- Tool 和 Tool 权限是 App 固定安全边界；用户可编辑 Prompt 或 Skill 只能在白名单内收窄，
  不能动态新增任意工具。
- 旧 Server 不得静默接受新 Envelope 后降级；协议不兼容时提示更新或切换本地执行。
