# ReAct Agent

Soma 的远程模式采用 OpenAI-compatible 原生 Tool Calling。网络与 SSE 解析由 `SwiftOpenAI 4.5.0` 提供，App 只负责编排 ReAct 循环、执行本地工具和记录事件，不维护自定义 Chat Completions 客户端。

## 运行方式

每次用户发送消息、图片或视频后，Agent 最多执行 8 轮：

1. App 把系统提示词、用户输入和媒体作为 `messages` 发送，并通过 API 的 `tools` 字段注册固定 JSON Schema。
2. 模型可以先输出自然语言，也可以返回一个或多个 `tool_calls`；不要求模型输出自定义决策 JSON。
3. App 在本机执行工具，把确定性结果以 `role: tool` 和对应 `tool_call_id` 写回消息历史。
4. 模型继续说话或调用工具，直到产生不含工具调用的最终回复。

每轮模型调用都使用流式接口。文本增量和 Span 生命周期会立刻作为 Event 发送给 UI；模型返回的 `reasoning_content` 当前不展示、不持久化，也不参与工具执行。

图片和视频关键帧只在用户主动发送并启用远程 Agent 时进入请求。SwiftData 数据库、原始媒体和工具执行始终留在设备上。

## 渐进式 Skills

系统提示词只披露八项 Skill 的 ID、名称和摘要。Agent 判断任务匹配后调用 `load_skill`，按需读取当前生效的完整 Markdown 指令：

- 健身房分析
- 用户健身计划制定
- 动作分析
- 饮食分析
- 体态分析
- 运动趋势分析
- 运动量分析
- 运动热量估算

Skill 文本可以在开发者设置中修改和预览。`load_skill` 是本地只读工具，加载过程形成独立 Skill Span。

## 本地工具

- `load_skill`：按需读取一项专业 Skill。
- `query_user_data`：查询概览、训练、饮食、身体或健身房记录。
- `record_workout`：记录动作及用户明确提供或可靠识别的训练字段。
- `record_meal`：记录餐次、食物、大卡与宏量营养。
- `record_body`：记录体重、体脂、腰围、体型图片和中性观察。
- `update_gym`：创建或更新健身房、照片及器械解析结果。
- `switch_gym`：切换已存在的当前健身房。

工具名称、描述和参数 Schema 由 Runtime 固定，通过 API 原生注册，不拼接进系统提示词，也不允许用户修改。工具不会向模型暴露数据库句柄、API Key 或本地文件路径。

## 数据真实性与安全

- 相同写入工具在同一次 Trace 内只执行一次。
- 未提供的重量、间歇、时长、评分等字段保持为空，不自动补默认值。
- 工具错误作为 `role: tool` 结果返回，让模型解释或修正，不静默写入异常数据。
- Agent 没有删除、账户、云同步或任意代码执行工具。
- 已成功写入的数据不会因为后续最终回复失败而回滚。
- 未配置远程服务时，演示空间可使用本地演示解析；个人空间只提取明确数字，不写入演示估算。
- 多模态能力能预判时在上传前提醒；无法预判时把供应商错误以用户可理解的方式展示。

## Trace、Span 与 Event

每条用户消息对应一条完整 Trace。成功、失败和取消都会落盘。执行中的每一次状态变化都是 Event：

- `model`：模型调用开始、流式文本增量、完成或错误、Token 用量。
- `skill`：Skill 加载开始、完成或失败，以及是否使用自定义文本。
- `tool`：工具入参、执行结果、写入类型和去重状态。
- `output`：最终回复、失败或取消。

UI 收到 Event 后立即更新当前回复和执行状态；持久化层按 Span ID 更新同一条记录，不为每个 token 新建数据库对象。日志不会保存 API Key、Authorization 头或媒体 Base64。

## 关键实现

- Tool Schema、提示词与 Skill：`Soma/Services/ReActAgent.swift`
- 流式 ReAct 编排与供应商适配：`Soma/Services/AppServices.swift`
- 本地工具执行：`Soma/Services/ConversationRecorder.swift`
- 流式聊天 UI：`Soma/Views/CoachView.swift`
- Trace 数据结构：`Soma/Models/Models.swift`
