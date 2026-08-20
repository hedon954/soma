# ReAct Agent

本文描述当前持久 Job、本地 ReAct 与可选远程 Backend 运行时。产品范围
见 [PRD 003](prd/003-streaming-react-agent.md)、
[PRD 011](prd/011-durable-agent-jobs-remote-continuity.md) 和
[PRD 022](prd/022-react-reliability-and-context-awareness.md) 和
[PRD 025](prd/025-trusted-context-direct-video-and-reviewable-meals.md)、
[PRD 030](prd/030-agent-prompt-skill-context-and-tool-v3.md)，详细协议见
[Agent Job 与远程执行协议](engineering/agent-job-protocol.md)。

## 当前运行时

Soma 的聊天采用 OpenAI-compatible 原生 Tool Calling。本地 Backend 的网络与 SSE 解析由
`SwiftOpenAI 4.5.0` 提供；可选远程 Backend 由 `Server/` 的持久 Worker 编排。两种模式的
业务 Tool 都在设备执行，结果进入同一 Turn、Job、Event 与 Trace 投影。

## 运行方式

每次用户发送消息、图片或视频后，Agent 最多执行可配置步数的循环（默认 100，高级设置可改）：

1. App 把系统提示词、用户输入和媒体作为 `messages` 发送，并通过 API 的 `tools` 字段注册固定 JSON Schema。
2. 模型可以先输出自然语言，也可以返回一个或多个 `tool_calls`；不要求模型输出自定义决策 JSON。
3. App 在本机执行工具，把确定性结果以 `role: tool` 和对应 `tool_call_id` 写回消息历史。
4. 模型继续说话或调用工具，直到产生不含工具调用的最终回复。

每轮模型调用都使用流式接口。文本增量和 Span 生命周期会立刻作为 Event 发送给 UI；模型返回的 `reasoning_content` 当前不展示、不持久化，也不参与工具执行。

请求真正发出后启用首增量门禁：文字 8 秒、图片/关键帧 10 秒、直传视频 20 秒。首个非空文字
或 Tool delta 才算响应，headers、heartbeat 与 reasoning 不算；首增量前失败最多自动重试一次，
收到首增量后使用 30 秒流空闲和 180 秒单步骤总时限。超时会取消底层请求；直传视频的唯一
重试改为按需关键帧，并在聊天与 Trace 明示实际模式。

图片和视频只在用户主动发送时按模型能力进入请求。SwiftData 数据库和业务 Tool 始终留在
设备上；本地模式标准档没有 API Key 时，消息仍然落盘并进入暂存，首次遇到时同时打开「LLM 配置」，
恢复后按发送顺序自动补偿消费（见 [ADR 0045](adr/0045-llm-outage-staging-and-compensating-drain.md)）。用户明确启用
远程持续模式后，当前图片或媒体能力注册允许的规范化视频可作为短期任务素材上传；用户 BYOK
不上传。直传和关键帧模式不会在同一个 Provider 请求里重复发送。

## 渐进式 Skills

系统提示词只披露 Skill 的 `name`、`description` 和 `when_to_use`。内置 Skill 使用带这三个
frontmatter 字段的 Markdown，支持本地 override 和用户自定义：

- 健身房分析
- 用户健身计划制定
- 动作分析
- 饮食分析
- 体态分析
- 运动趋势分析
- 运动量分析
- 运动热量估算

未选快捷按钮时，Agent 可调用本地只读 `load_skill` 按需加载，过程形成独立 Skill Span。
用户在输入框上方单选一个快捷按钮后，若该按钮绑定 Skill，首轮直接注入完整 Markdown 与专属上下文，
省去一次加载调用。设置页支持内置 override、自定义 Skill、Markdown 预览与恢复；Skill 只描述专业
方法，工具权限由快捷按钮持有，固定 Tool 协议不能被扩权。

## 输入框快捷按钮

快捷按钮是可完整增删改的本机实体：名称、图标、绑定 Skill（可为空）、工具白名单、是否显示与排序，
以 JSON 存 UserDefaults，不进入 SwiftData。默认可见三个：饮食分析、训练记录、近期分析；聊天输入区
最多显示六个。工具默认全选，可按分组删减，也可让小模型推荐一份清单与理由后一键采纳。详见
[ADR 0082](adr/0082-shortcut-owned-tool-bindings-and-method-only-skills.md)。

## 本地工具

当前协议使用 32 个单一职责 Tool：动作 5 个，训练、饮食、身体各 5 个，计划 7 个，另有
`load_skill`、健身房 2 个、复盘和反馈各 1 个。未选快捷按钮时，本轮把这 32 个全部放入 API
`tools` 参数；选中按钮时只放入该按钮工具白名单与当前协议的交集。未知名称解码失败。
每次调用的工具名同时写入 Trace model span 与本机诊断日志。

训练、饮食和身体记录都有独立 list/get/create/update/delete；动作独立搜索、创建、更新、
归档和合并。所有业务 ID 是 Int64，`create_workout` 必须绑定有效 `exercise_id`，计划动作也必须
绑定动作库。完整当前清单和出入参见
[Agent Tool 目录](engineering/agent-tool-catalog.md)。

工具名称、描述和参数 Schema 由 Runtime 固定，通过 API 原生注册，不拼接进系统提示词，也不允许用户修改。工具不会向模型暴露数据库句柄、API Key 或本地文件路径。

## 数据真实性与安全

- 同一 Turn 的相同成功写入通过包含最终 `occurred_at` 和业务 ID 的规范化签名只执行一次；失败回执不挡同键重试。
- 新媒体默认创建新记录；纠错必须绑定查询得到的稳定 `record_id`。同一 ReAct Loop 的多次
  create 都新增独立记录，不能把创建当更新。
- 未提供的重量、间歇、时长、评分等字段保持为空，不自动补默认值。
- 工具错误作为 `role: tool` 结果返回，让模型解释或修正，不静默写入异常数据。
- Tool 错误包含稳定 `code/field/expected/retryable`；对象 Schema 关闭额外字段并继续执行本地二次校验。
- 删除工具只处理用户明确指定的单条业务记录；Agent 仍没有账户、云同步或任意代码执行工具。
- 已成功写入的数据不会因为后续最终回复失败而回滚。
- 标准档未配置 API Key 时仍原子落盘 Turn 与 Job 并进入暂存，恢复后补偿消费。
- 多模态能力能预判时在上传前提醒；无法预判时把供应商错误以用户可理解的方式展示。

## Trace、Span 与 Event

每次远程 Attempt 对应一条完整 Trace；同一用户 Turn 可以因失败重试拥有多个 Attempt。
成功、失败和取消都会落盘。执行中的每一次状态变化都是 Event：

- `model`：模型调用开始、流式文本增量、完成或错误、Token 用量。
- `skill`：Skill 加载开始、完成或失败，以及是否使用自定义文本。
- `tool`：工具入参、执行结果、写入类型和去重状态。
- `output`：最终回复、失败或取消。

UI 收到 Event 后先经过确定性 reducer，再更新一次 Turn 内的有序 Event Cards：

- 同一 Item ID 的文字 delta 合并到同一张文字卡；
- Skill/Tool 按 Span ID 更新同一张操作卡；
- 操作卡之后的新文字创建新卡，不能回填到此前文字；
- 失败保留已经完成的卡片，并追加错误卡；
- 重新进入聊天时按持久化顺序完整重放。

聊天卡片与开发者 Trace 是同一事件流的两种投影：聊天强调发生了什么，Trace 保留完整参数、输出、耗时和 Token。日志不会保存 API Key、Authorization 头或媒体 Base64。

Event 投影必须在主 actor 执行。流式 chunk 回调保持 `@MainActor`，文字增量在内存合批后再写入
SwiftData；DEBUG 下投影入口断言主 actor 隔离（见
[BUG 0024](bugs/0024-streaming-cross-actor-swiftdata-crash.md)）。

除 Trace 之外还有一条本机滚动诊断日志，记录生命周期、每次模型调用的工具清单、Tool 结果、Turn 终态
与录像阶段，用于崩溃后复盘；边界与上报规则见
[ADR 0083](adr/0083-local-diagnostics-log-and-silent-crash-reporting.md)。

## 关键实现

- 分层 Prompt：`Soma/Services/ReActAgentPrompt.swift`
- Tool Schema：`Soma/Services/ReActAgent.swift`
- Skill 注册表：`Soma/Services/AgentSkillRegistry.swift`
- 快捷按钮与工具曝光：`Soma/Services/AgentInputShortcut.swift`、
  `Soma/Services/AgentToolExposurePolicy.swift`
- 诊断日志与崩溃上报：`Soma/Services/DiagnosticsLogStore.swift`、
  `Soma/Services/CrashDiagnosticsCoordinator.swift`
- 会话滚动压缩：`Soma/Services/ConversationCompactionMiddleware.swift`
- 流式 ReAct 编排与供应商适配：`Soma/Services/AppServices.swift`
- 本地工具执行：`Soma/Services/ConversationRecorder.swift`
- 流式聊天 UI：`Soma/Views/CoachView.swift`
- Event Card UI：`Soma/Views/AgentTurnTranscript.swift`
- Turn Item 与 reducer：`Soma/Models/AgentTurnItem.swift`、`Soma/Models/Models.swift`
- Trace 数据结构：`Soma/Models/Models.swift`
- 持久 Job、Event 与投影：`Soma/Models/AgentJob.swift`、
  `Soma/Services/ConversationProcessingService.swift`
- 可选远程 Backend：`Soma/Services/RemoteAgentClient.swift`、`Server/`
- 动作与训练计划：`Soma/Models/ExerciseDefinition.swift`、
  `Soma/Models/TrainingPlan.swift`

## 持久运行时

### 持久 Job

一次发送必须先原子保存 Turn、媒体引用、上下文快照和 `AgentJob`。App 根层的
`AgentJobRunner` 领取任务并追加带 sequence 的语义 `AgentEvent`；Chat、Trace、
Live Activity 和通知是独立投影。token delta 继续实时显示，但不逐 token 写入 SwiftData。

本地执行获得有限后台时间（约 45 秒租约）。每个 ReAct step 边界落检查点；到期前 Job 进入
`waitingForForeground`。有有效检查点时恢复复用同一条 CoachMessage、从下一步继续，且不递增
`attemptNumber`；丢弃未完成 step 的半截文本，不续接半条 SSE。无检查点或用户手动重试才开新
Attempt。成功 mutation 由规范化签名的 `AgentMutationReceipt`（pending → committed）去重；
跨 Turn 业务键命中返回疑似重复而不静默合并。

每轮请求只暴露 Loop 开始时确定的 Tool 集，整轮固定。未选 Skill 时是当前协议全部工具；选中快捷 Skill 时只注册该 Skill 绑定的子集。
供应商侧允许并行 `tool_calls`，本机仍顺序执行。`AgentContextPackBuilder` 提供确定性上下文包；
历史始终保留最近十个完整 user-assistant 对。从第十一对开始，Loop 前用“已有摘要 + 新移出
窗口的完整对”重新生成完整替代摘要，小模型优先、标准模型回退、确定性 digest 兜底；Loop 内
不再次压缩，压缩会形成可展开 Chat 事件卡。
当前媒体优先，历史媒体只在明确回指或比较时选择最多一到两个匹配 Turn。

### 可选远程 Backend

`AgentExecutionBackend` 提供 Local 和 Remote 两种实现。远程模式使用匿名设备身份把 Job
幂等提交到 Soma Server，服务器保存 Event Log 并在 App 被挂起后继续纯远程步骤。

服务器不能访问本地 SwiftData 或 Keychain。遇到设备 Tool 时追加 `tool_request` 并进入
`waitingForDevice`；设备恢复后验证固定 Schema、执行 Tool 并幂等返回 `tool_result`。
训练、饮食、身体和健身房记录仍以设备为事实来源。

### 训练固定 Tool

训练动作身份已经使用：

- `search_exercises` 按名称返回 `{exercise_id,name}`，已有上下文足够时不得重复搜索；
- 只有无语义等价项时一次调用 `create_exercise(exercise_names)`，再把返回的 Int64 ID 交给一次
  `create_workout(workouts)`；不要指定新建 `record_id`；
- `create_program` 与 `create_program_version` 的每个动作都必须绑定有效动作 ID；
- `list_programs` / `get_program` 提供精确读取，`start_program` 仅创建本地不可变 Session 并路由
  到带练。逐组事实、倒计时和相机控制不暴露给模型，由本地确定性运行时保存。

Session 保存 `businessDate` 与 IANA 时区。Job 创建时冻结原始 Turn 时间、有效业务日期和
`defaultOccurredAt`；训练、饮食、身体 create/update 可显式传带时区 `occurred_at`，省略时复用
该稳定默认值。因此排队、跨午夜与失败重试仍记录真实原始时间。自然语言日期只覆盖当前 Turn，
只有日期芯片会修改 Session 的默认业务日期。

工具合同见 [训练领域模型与运行时协议](engineering/training-domain-model.md)。
