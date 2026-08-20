# Agent Tool 目录

本文件维护当前代码实际支持的 Agent Tool、暴露策略和协议边界。它只做导航与审计，不复制
完整 JSON Schema；可执行事实以源码和测试为准。

## 事实来源

- 名称、描述、严格参数 Schema：`Soma/Services/ReActAgent.swift`。
- 分组与 Loop 开始时的暴露：`Soma/Services/AgentToolExposurePolicy.swift`。
- 快捷按钮的工具白名单：`Soma/Services/AgentInputShortcut.swift`。
- 设备执行：`Soma/Services/ConversationRecorderTypedTools.swift` 及各领域扩展。
- 公共结果与本地二次校验：`AgentToolResultV2.swift`、`ConversationRecorderToolV2.swift`。
- 本地/远程统一输入：`AgentModelInput.swift`；远程注册表：`Server/src/tool-registry.ts`。
- 回归：`SomaTests/AgentPromptMigrationRefactorTests.swift`、`AgentReliabilityTests.swift`、
  `AgentBatchCreateToolTests.swift`、`Server/test/`。

## 暴露策略

运行时只解码当前协议 32 个名称。每次请求把当轮允许的集合放进 API `tools` 参数；System
Prompt 不声明 Tool 名称或 Schema。判断发生在 ReAct Loop 开始时，整轮固定。

- 未选快捷按钮：注册当前协议全部 32 个 Tool，含 `load_skill`。Skill 目录完整可见。不做关键词或本机状态剪枝。
- 选中快捷按钮：只暴露该按钮 `toolNames` 与当前协议的交集；按钮绑定 Skill 时首轮直载完整
  Markdown 与专属上下文。ADR 0082 之后曝光边界由按钮持有，Skill 不再声明工具。
- 分组（`AgentToolGroup`）只是设置页里勾选工具的分类，不是运行时单位。
- 已经预加载的事实足够时不得重复查询。
- 未知 Tool 名称在保存快捷按钮与运行时都被丢弃，解码失败不能执行。
- 每次模型调用都把本轮工具名写进 Trace model span 与诊断日志（ADR 0083）。

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
- `create_workout` 必须接收已经存在的 `exercise_id` 数组项。动作不存在时先
  `search_exercises`，确认无语义等价项后一次 `create_exercise(exercise_names)`，再一次
  `create_workout(workouts)`。新建训练记录不要传 `record_id`。
- 计划的每个动作也必须绑定动作库 `exercise_id`。
- 训练、饮食、身体 create/update 都支持可选 `occurred_at`。它是带时区 ISO-8601 时间；
  省略时使用 Job 从原始用户 Turn 冻结的 `defaultOccurredAt`，重试、排队和跨午夜不会漂移。
  `defaultOccurredAt` 保留发送时刻的钟点，不是业务日零点；用户没有明确说时间就应省略。
- list/get/create/update/delete 彼此独立；get/update/delete 必须传对应领域的精确 Int64 ID。
- create 每次都新增独立记录，同一轮可多次调用；纠正、补图或改已有记录必须先 list/get 再 update。
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

## 更新规则

- 新增、删除、重命名 Tool 或改变 Schema/输出时，同一提交更新 iOS 注册表、Server
  注册表、统一 Envelope、本文和确定性测试。
- Tool 和 Tool 权限是 App 固定安全边界；用户可编辑 Prompt、Skill 或快捷按钮只能在当前协议内
  收窄，不能动态新增任意工具。
- 旧 Server 不得静默接受新 Envelope 后降级；协议不兼容时提示更新或切换本地执行。
