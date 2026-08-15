# 默认 Prompt 来源目录

本文件只维护 Soma 当前 Prompt/Skill/动态上下文的 **默认源码位置与组装入口**，不复制原文。
这样默认文本修改只发生在一个可执行事实位置，目录不会产生过期副本。

| Prompt / 上下文 | 默认源码位置 | 组装或调用入口 | 是否可编辑 |
| --- | --- | --- | --- |
| ReAct 固定身份、安全、真实性与授权契约 | `Soma/Services/ReActAgentPrompt.swift` → `ReActAgentPrompt.system` | `AgentModelInputBuilder.build` | 不可编辑；设置页只读预览 |
| ReAct 人格 | `Soma/Services/ReActAgentPrompt.swift` → `ReActPromptSection.persona` | `ReActAgentPrompt.system(defaults:)` | 可编辑、可恢复；旧角色自定义迁移到此处 |
| Skill 元数据目录 | `Soma/Services/AgentSkillRegistry.swift` → `AgentSkillRegistry.descriptors` | `ReActAgentPrompt.system(skillDescriptors:)` | 内置目录可 override，支持自定义 Skill；只注入 `name/description/when_to_use` |
| 选中 Skill 完整文本 | `Soma/Services/AgentSkillRegistry.swift` | `AgentModelInputBuilder.build` → `ReActAgentPrompt.user` | 用户预选后首轮直载；权限只能取 App 白名单交集 |
| 各健身 Skill 默认 Markdown | `Soma/Services/AgentSkillRegistry.swift` → `AgentSkillRegistry.builtInMarkdown` | `AIService.loadSkill` / `load_skill` | 支持内置 override、自定义、预览与恢复 |
| Tool 名称、描述与参数 | `Soma/Services/ReActAgent.swift` → `AgentToolName.toolDescription/toolParameters` | `AgentToolName.chatTool` | 不可编辑，系统固定 |
| Session businessDate 与可信 Turn/Loop 时间 | `Soma/Models/AgentTurnContext.swift` → `TrustedTurnContext.promptText` | `AgentTurnContextBuilder.build`、Job 创建时冻结 `effectiveBusinessDate/defaultOccurredAt`、首次 claim 冻结 `loopStartedAt` | 不可编辑；自然语言日期只影响当前 Turn，日期芯片才持久修改 Session |
| 确定性业务上下文包 | `Soma/Services/AgentContextPackBuilder.swift` | `ConversationProcessingContextFactory.make` | 不可编辑，本机事实派生 |
| 最近十对原生历史、滚动摘要与媒体选择 | `Soma/Services/ConversationCompactionMiddleware.swift`、`AgentTurnContextBuilder.swift`、`ConversationContextProjection.swift` | 每次 ReAct Loop 前压缩；Loop 内不压缩 | 不可编辑；小模型优先、标准模型回退、确定性 digest 兜底；压缩生成 Chat 事件卡 |
| 位置、健身房和天气 Turn 上下文 | `Soma/Services/ConversationProcessingService.swift` → `turnContext`；`WeatherContextProvider.swift` | `composePersistentContext` | 不可编辑，按授权临时生成 |
| 版本化当前 Turn User Prompt | `Soma/Services/ReActAgentPrompt.swift` → `ReActAgentPrompt.user`、`historicalUser` | `AgentModelInputBuilder.build` | 不可编辑；固定 v2 section 顺序，空事实块完全省略，动态输入与媒体位于后部 |
| 本地/远程 Agent system/user/history 消息与媒体 ID | `Soma/Services/AgentModelInput.swift` → `AgentModelInputBuilder` | `AIService.prepareAgentRun`、`ConversationProcessingService.prepareRemoteSubmission` | 不可编辑；两种 Backend 消费同一版本化 Envelope |
| 中断恢复的检查点观察 | `Soma/Services/AppServices.swift` → `compactedCheckpointPrompt` | `AIService.runAgent` | 不可编辑，只包含已持久化短观察；与会话滚动摘要是不同机制 |
| 训练计划优化提示 | `Soma/Services/TrainingIntelligenceService.swift` → `TrainingIntelligenceService.optimize` 内 `prompt` | `AIService.runAgent` | 不可编辑，由计划与真实历史生成 |
| 动作说明生成提示 | `Soma/Services/TrainingIntelligenceService.swift` → `TrainingIntelligenceService.generateContent` 内 `prompt` | `AIService.runAgent` | 不可编辑，要求固定 JSON 输出 |
| 计划训练视频复盘提示 | `Soma/Services/TrainingIntelligenceService.swift` → `TrainingIntelligenceService.performanceReviewPrompt` | `ConversationProcessingService.submit` | 不可编辑，绑定 Performance ID 与输入指纹 |
| 训练动作插图生成提示 | `Soma/Services/TrainingIntelligenceService.swift` → `ExerciseImageGenerationService.prompt` | `AIService.generateImage` | 不可编辑，按动作事实生成 |

## 更新规则

- 新增任何发送给模型的 system、developer、user 模板、Skill 默认文本或图片生成提示时，必须在
  同一提交加入本目录并指向唯一源码符号。
- Prompt 原文不得复制到本文、README、PRD 或 ADR；产品行为写入 PRD，长期边界写入 ADR。
- Tool Schema、可信时间、安全限制和隐私门禁不能由用户 Prompt 覆盖。
- 动态上下文必须标明事实来源；真实媒体、密钥和完整私有 Trace 不得进入默认文本或测试夹具。
- System Prompt、Tool 顺序和 User Prompt section 标题是 prefix cache 稳定性边界；动态内容优先后置，
  不得只为文案变化随意改序。客户端不据此宣称供应商一定命中缓存。
