# Agent Tool 目录

本文件维护 **当前代码实际支持** 的 Agent Tool、暴露状态、Schema 版本与实现入口。它是导航和
审计目录，不复制完整 JSON Schema；参数的可执行事实始终以源码与测试为准。

## 事实来源

- 名称、模型侧描述与参数 Schema：`Soma/Services/ReActAgent.swift` 中的 `AgentToolName`、
  `toolDescription`、`toolParameters`。
- 分组与每轮暴露策略：`Soma/Services/AgentToolExposurePolicy.swift`。
- 设备执行与结果：`Soma/Services/ConversationRecorder.swift`、
  `ConversationRecorderToolV2.swift` 及其领域扩展；公共结果见 `AgentToolResultV2.swift`。
- 本地 ReAct 调度：`Soma/Services/AppServices.swift`。
- 远程固定注册表：`Server/src/tool-registry.ts`。
- 远程协议：`Soma/Services/RemoteAgentClient.swift`、`Server/src/api.ts`、
  `docs/engineering/agent-job-protocol.md`。
- Schema 与行为回归：`SomaTests/AgentReliabilityTests.swift`、`Server/test/`。

## 当前发布状态

PRD 025 / ADR 0059 的 Tool v2 已落地。“v2 暴露”列是新请求唯一可见集合；v1 名称只用于
历史 Job、备份和持久化 Tool Call 兼容，不再发送给新模型。

当前运行时共注册 24 个可执行名称：13 个会按组暴露给新模型，11 个只在恢复历史调用时使用。

| Tool | 组 | 类型 | v2 暴露 | 兼容状态 |
| --- | --- | --- | --- | --- |
| `load_skill` | core | 读取 | 是 | 保留 |
| `query_user_data` | core | 读取 | 是，Schema v2 | v1 参数继续解码 |
| `mutate_user_data` | records | 写入 | 是，Schema v2 | 仅明确记录／修改／删除意图预选 |
| `expand_tool_group` | core | 运行时 | 是 | 保留 |
| `create_training_program` | plans | 写入 | 是 | 保留 |
| `create_workout_template_version` | plans | 写入 | 是 | 保留 |
| `archive_training_program` | plans | 写入 | 是 | 保留 |
| `delete_training_program` | plans | 删除 | 是 | 保留显式意图门禁 |
| `start_guided_workout` | plans | 写入/路由 | 是 | 保留 |
| `update_gym` | gym | 写入 | 是 | 保留 |
| `switch_gym` | gym | 写入 | 是 | 保留 |
| `record_performance_analysis` | review | 写入 | 是 | 保留 |
| `submit_feedback` | feedback | 外发 | 是 | 保留当前 Turn 显式意图门禁 |
| `list_exercise_names` | core | 读取 | 否 | 并入 `query_user_data(scope=exercises)` |
| `list_training_programs` | plans | 读取 | 否 | 并入 `query_user_data(scope=programs)` |
| `get_training_program` | plans | 读取 | 否 | 并入精确 program 查询 |
| `record_workout` | core | 写入 | 否 | 并入 `mutate_user_data` |
| `record_meal` | core | 写入 | 否 | 并入 `mutate_user_data` |
| `record_body` | core | 写入 | 否 | 并入 `mutate_user_data` |
| `update_workout` | core | 写入 | 否 | 并入 `mutate_user_data` |
| `update_meal` | core | 写入 | 否 | 并入 `mutate_user_data` |
| `update_body` | core | 写入 | 否 | 并入 `mutate_user_data` |
| `delete_record` | core | 删除 | 否 | 并入 `mutate_user_data`，保留显式意图门禁 |
| `update_workout_template` | plans | 写入 | 否 | 隐藏别名，执行 `create_workout_template_version` |

## 13 个当前可见 Tool 的输入

| Tool | 必填输入 | 按需输入 | 结果重点 |
| --- | --- | --- | --- |
| `load_skill` | `skill_id` | — | Skill 内容；仅按需加载 |
| `query_user_data` | `scope` | `record_id`、`exercise_id`、`program_id`、`session_id`、`query`、`date_from`、`date_to`、`sort`、`limit`、`cursor`、`projection`、`fields`、`group_by`、`metric` | `data.items` 与 `page.next_cursor`；默认 3、最大 10；`detail` 必须精确 ID；动作查询必须有搜索词或 ID |
| `mutate_user_data` | `operation`、`record_type` | `record_id`、与记录类型唯一对应的 `payload` | 稳定 `record_refs`；create/update 需要 payload，update/delete 需要 ID，delete 不接受 payload |
| `expand_tool_group` | `tool_group` | — | 只可展开 records/plans/gym/review/feedback |
| `create_training_program` | `program_name`、`template_name`、`template_exercises` | `goal`、`schedule_hint` | 新计划与首个不可变模板 |
| `create_workout_template_version` | `program_id`、`template_name`、`template_exercises` | `schedule_hint` | 新的不可变模板版本 |
| `archive_training_program` | `program_id` | — | 归档回执 |
| `delete_training_program` | `program_id` | — | 永久删除回执；需当前消息明确授权 |
| `start_guided_workout` | `program_id` | `auto_recording_policy` | 新 Session 与带练路由 |
| `update_gym` | — | `gym_name`、`summary`、`media_source`、`equipment` | 场馆与器械更新回执 |
| `switch_gym` | `gym_name` | — | 当前健身房切换回执 |
| `record_performance_analysis` | `performance_id`、`input_fingerprint`、`evidence`、`limitations`、`feedback` | — | 视频复盘保存回执 |
| `submit_feedback` | — | — | 外发结果；只允许当前 Turn 明确产品反馈意图 |

`mutate_user_data.payload` 只允许三类字段：训练的动作/有序组/间歇/时长/评价，饮食的餐次/
标题/可空总营养/有序 `items`/说明，以及身体的体重/体脂/腰围/体态与安全说明。运行时会同时
校验 operation、record_type、record_id 和 payload 组合，不能跨类型夹带字段。

## 11 个隐藏兼容名称

这些名称不会进入新模型的 Tool Schema，只用于解码并执行历史 Job、备份或已持久化 Tool Call。
执行结果仍统一编码为下方 Tool v2 envelope，写入类结果继续返回稳定 `record_refs`。

| 隐藏 Tool | 兼容输入 | 当前输出/去向 |
| --- | --- | --- |
| `list_exercise_names` | 无 | 分页能力迁移到 `query_user_data(scope=exercises, query=...)`；旧调用返回兼容查询结果 |
| `list_training_programs` | 无 | 兼容计划摘要；新调用使用 `query_user_data(scope=programs)` |
| `get_training_program` | `program_id` | 兼容计划详情；新调用使用精确 program detail 查询 |
| `record_workout` | 动作 ID/名称、逐组次数与重量、间歇、时长、评分、强度、反馈 | 训练 `record_refs` 与短回执；新调用使用 `mutate_user_data(create, workout)` |
| `record_meal` | 标题、餐次、可空总营养、说明 | 饮食 `record_refs` 与 typed data；新调用使用 `mutate_user_data(create, meal)` |
| `record_body` | 体重、体脂、腰围、体态和安全说明 | 身体记录 `record_refs`；新调用使用 `mutate_user_data(create, body)` |
| `update_workout` | `record_id` 与训练字段 | 更新后的训练引用；新调用使用 `mutate_user_data(update, workout)` |
| `update_meal` | `record_id` 与饮食字段 | 更新后的饮食引用与 typed data；新调用使用 `mutate_user_data(update, meal)` |
| `update_body` | `record_id` 与身体字段 | 更新后的身体记录引用；新调用使用 `mutate_user_data(update, body)` |
| `delete_record` | `record_type`、`record_id` | 删除短回执；仍要求当前用户消息明确授权 |
| `update_workout_template` | 与 `create_workout_template_version` 相同 | 创建不可变的新模板版本，不原地覆盖 |

## Tool v2 公共结果

新 Tool 结果统一为紧凑 envelope：

```text
ok, code, message, data?, record_refs?, page?
```

- `data` 只包含请求投影；不得默认返回完整业务库。
- `record_refs` 提供 UI 与后续 Turn 可稳定引用的类型和 ID。
- `page` 只包含分页所需的 cursor 信息。
- 用户可见卡片读取 typed result；原始 JSON、UUID 和 Schema 版本只进入开发者执行日志。

## 更新规则

- 新增、删除、重命名、隐藏 Tool 或改变 Schema/输出时，必须同一提交更新本目录、iOS 注册表、
  Server 注册表、协议文档和确定性测试。
- Tool 是系统安全边界；不得从用户可编辑 Prompt 或 Skill 动态新增。
- 删除、外发、远程数据和业务写入继续遵循当前 PRD/ADR 的显式授权与幂等规则。
