# Agent Tool 目录

- 后续修订：[ADR 0141](../adr/0141-coach-training-schedule-draft.md)（增加不落库的 `propose_training_schedule`）
- 后续修订：[ADR 0000](../adr/0000-origin-through-0.0.11.md)（固定提问工具与曝光例外）
- 后续修订：[ADR 0145](../adr/0145-adaptive-energy-system.md)（明确生活/完整性事实与训练热量口径）

本文件维护当前代码实际支持的 Agent Tool、暴露策略和协议边界。它只做导航与审计，不复制
完整 JSON Schema；可执行事实以源码和测试为准。

## 事实来源

- 名称、描述、严格参数 Schema：`Soma/Services/Conversation/AgentToolName.swift`、
  `Soma/Services/Conversation/AgentToolJSONSchema.swift`。
- 分组与 Loop 开始时的暴露：`Soma/Services/Conversation/AgentToolExposurePolicy.swift`。
- 快捷按钮的工具白名单：`Soma/Services/Settings/AgentInputShortcut.swift`。
- 设备执行：`Soma/Services/Conversation/ConversationRecorderTypedTools.swift` 及各领域扩展。
- 公共结果与本地二次校验：`AgentToolResultV2.swift`、`ConversationRecorderToolV2.swift`。
- 本地/远程统一输入：`AgentModelInput.swift`；远程注册表：`Server/src/tool-registry.ts`。
- 回归：`SomaTests/AgentPromptMigrationRefactorTests.swift`、`AgentReliabilityTests.swift`、
  `AgentBatchCreateToolTests.swift`、`Server/test/`。

## 暴露策略

运行时只解码当前协议 35 个名称。每次请求把当轮允许的集合放进 API `tools` 参数；System
Prompt 不声明 Tool 名称或 Schema。判断发生在 ReAct Loop 开始时，整轮固定。

- 未选快捷按钮：注册当前协议全部 34 个 Tool，含 `load_skill` 与 `ask_user_questions`。Skill 目录完整可见。不做关键词或本机状态剪枝。
- 选中快捷按钮：只暴露该按钮 `toolNames` 与当前协议的交集；按钮绑定 Skill 时首轮直载完整
  Markdown 与专属上下文。ADR 0082 之后曝光边界由按钮持有，Skill 不再声明工具。
- `ask_user_questions` 始终可用；按钮绑定的确定性操作仍须在当前业务工具曝光范围内。
- 分组（`AgentToolGroup`）只是设置页里勾选工具的分类，不是运行时单位。
- 已经预加载的事实足够时不得重复查询。
- 未知 Tool 名称在保存快捷按钮与运行时都被丢弃，解码失败不能执行。
- 每次模型调用都把本轮工具名写进 Trace model span 与诊断日志（ADR 0083）。

## 当前 34 个 Tool

| 组 | Tool | 用途 |
| --- | --- | --- |
| core | `load_skill` | 未预选 Skill 时按 ID 读取当前生效 Markdown |
| core | `ask_user_questions` | 提问后结束本轮；未设置 selection 时点按即发送。带 selection 时单选或多选，每题自填后一次发送 |
| exercises | `search_exercises`、`create_exercise`、`update_exercise`、`archive_exercise`、`merge_exercises` | 动作搜索、创建、修正、归档和合并 |
| workouts | `list_workouts`、`get_workout`、`create_workout`、`update_workout`、`delete_workout` | 训练记录单一职责 CRUD |
| meals | `list_meals`、`get_meal`、`create_meal`、`update_meal`、`delete_meal` | 饮食记录单一职责 CRUD |
| body | `list_body_entries`、`get_body_entry`、`create_body_entry`、`update_body`、`delete_body_entry` | 身体与体态记录单一职责 CRUD |
| body | `record_energy_context` | 明确工作、通勤、家务与逐日饮食/训练/携带完整性；未知保持未知，不返回健康推导 |
| plans | `list_programs`、`get_program`、`create_program`、`update_program`、`archive_program`、`delete_program`、`start_program`、`propose_training_schedule` | 课程读取、创建、直接更新当前处方、归档、删除和带练启动；计划草稿支持动作逐组参数、课程和嵌套计划，只校验不落库 |
| gym | `update_gym`、`switch_gym` | 健身房与器械维护、当前场馆切换 |
| review | `record_performance_analysis` | 保存绑定 Performance 的视频复盘 |
| feedback | `submit_feedback` | 仅在当前 Turn 明确授权时提交产品反馈 |

## 输入契约

- `ask_user_questions` Schema v1 接收 1–3 个问题，每题最多 6 个选项。可选 `selection` 为 `single` 或 `multiple`；设置后 `allows_custom_input` 必须为 true，选项不能绑定 action，点按只改变选中。`text` 是用户口吻的完整句子；
  可选 `action` 绑定当前已开放工具及完整 `arguments_json`，`allows_custom_input` 控制自由输入。
  提问不执行绑定操作；用户点击后重新校验并执行，不需要模型续跑。递归提问、Skill 加载、反馈外发和媒体复盘不能绑定。
- 业务 `record_id`、`exercise_id`、`program_id`、`schedule_id`、计划动作 ID 均为正 `Int64`；UUID 只留给
  Session、Turn、Job、Trace、Event、媒体、外部来源和旧备份映射。
- 训练域当前为 Schema v4：`search_exercises` 返回动作 ID、`target_kind` 与 `laterality`；动作
  不存在时先搜索，确认无语义等价项后一次 `create_exercise(exercises)`，每项显式提供名称、目标
  类型和侧别，再一次 `create_workout(workouts)`。新建训练记录不要传 `record_id`。
- 计划的每个动作也必须绑定动作库 `exercise_id`。用户要求把当日原始训练总结为计划时，
  `create_program` 同时传唯一、同日的 `source_workout_record_ids`；设备组装一次完成 Session，原始
  `WorkoutEntry` 仍是事实本体。
- 训练、饮食、身体 create/update 都支持可选 `occurred_at`。它是带时区 ISO-8601 时间；
- 饮食 create/update 不接受总糖；`glycemic_speed` 只接受 `slow|moderate|fast`，并必须与非空
  `glycemic_assessment` 成对出现。该评估描述餐食组成，不代表个体血糖峰值或诊断；修改菜品会
  清除旧评估。餐次只有用户原文明确说出时才覆盖，否则设备按 `occurred_at` 本地时钟推断。
  省略时使用 Job 从原始用户 Turn 冻结的 `defaultOccurredAt`，重试、排队和跨午夜不会漂移。
  `defaultOccurredAt` 保留发送时刻的钟点，不是业务日零点；用户没有明确说时间就应省略。
- list/get/create/update/delete 彼此独立；get/update/delete 必须传对应领域的精确 Int64 ID。
- `create_workout`/`update_workout` 显式提供本次 `target_kind` 与 `laterality`；每条
  `set_entries` 包含 `logical_set_index`、`side`、`target_kind`、对应的 `reps` 或
  `duration_seconds`、可选外部重量和 `rest_seconds`。左右各做必须把同一逻辑组拆成 left/right
  efforts；`.none` 与左右 effort 冲突返回可重试字段错误。本次 evidence 优先于动作库 fallback。
- 新模型调用只广告当前 Schema；create 的 v2/v3 和其他 Tool 明确声明的旧版本仅用于恢复已持久
  Job，仍执行闭合字段、类型、范围与关系校验。
- 训练提供可选 `calories_scope: active|gross|unknown`，只根据明确证据保存口径；`metGross` 仅由本地公式写入。
  `record_energy_context` Schema v1 只接收明确生活事实及最多 31 日日期范围的完整性确认；修改/删除通过能量依据的原生审查页。
  “完善生活信息”发送固定教练请求并清除先前快捷限制，不改变自定义快捷按钮的持久白名单；健康依据不进入 Tool 结果或上下文。
- create 每次都新增独立记录，同一轮可多次调用；纠正、补图或改已有记录必须先 list/get 再 update。
- 每个对象 Schema 都设置 `additionalProperties: false`；兼容 Provider 时发送 `strict: true`，
  设备仍执行本地未知字段、类型、ID、关系和授权校验。
- integer/number 的说明明确要求 JSON 数字。设备只按当轮 Schema 把无单位非负十进制字符串或简单
  分数字符串转换为数字；integer 换算后仍须为整数，带单位或含混文本不转换。
- 删除、外发与高影响操作继续要求当前用户消息明确授权。

## 结果与错误

Tool 结果使用紧凑 envelope：

```text
ok, code, message, data?, record_refs?, page?, error?
```

- `record_refs` 返回业务类型和 Int64 ID，供 UI 与后续 Turn 稳定引用。
- 错误提供稳定的 `code/field/expected/retryable`，并以 `role: tool` 返回模型修正。
- 已知 Tool 的参数校验失败使用 `invalid_tool_arguments`，保留原 `tool_call_id` 并进入检查点；模型在
  既有步数预算内生成新参数。未知 Tool、安全拒绝和 Schema 版本冲突不降级为可重试错误。
- 幂等签名包含解析后的业务 ID 和最终 `occurred_at`；成功写入在重试时不会重复发生。
- 原始参数、UUID 锚点和 Schema 版本只进入开发者 Trace，不进入普通聊天文案。

## 更新规则

- 新增、删除、重命名 Tool 或改变 Schema/输出时，同一提交更新 iOS 注册表、Server
  注册表、统一 Envelope、本文和确定性测试。
- Tool 和 Tool 权限是 App 固定安全边界；用户可编辑 Prompt、Skill 或快捷按钮只能在当前协议内
  收窄，不能动态新增任意工具。
- 旧 Server 不得静默接受新 Envelope 后降级；协议不兼容时提示更新或切换本地执行。
