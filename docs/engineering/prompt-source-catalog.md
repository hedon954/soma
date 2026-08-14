# 默认 Prompt 来源目录

本文件只维护 Soma 当前 Prompt/Skill/动态上下文的 **默认源码位置与组装入口**，不复制原文。
这样默认文本修改只发生在一个可执行事实位置，目录不会产生过期副本。

| Prompt / 上下文 | 默认源码位置 | 组装或调用入口 | 是否可编辑 |
| --- | --- | --- | --- |
| ReAct 角色与安全策略 | `Soma/Services/ReActAgent.swift` → `ReActPromptSection.defaultText` | `ReActAgentPrompt.system(defaults:)` | 角色、策略可在高级设置按节编辑/恢复 |
| Skill 目录提示 | `Soma/Services/ReActAgent.swift` → `AgentSkill.catalogPrompt(defaults:)` | `ReActAgentPrompt.system(defaults:)` | 目录由 Skill 当前值生成 |
| 各健身 Skill 默认文本 | `Soma/Services/ReActAgent.swift` → `AgentSkill.defaultText` | `AIService.loadSkill` / `load_skill` | 每个 Skill 可独立编辑/恢复 |
| Tool 名称、描述与参数 | `Soma/Services/ReActAgent.swift` → `AgentToolName.toolDescription/toolParameters` | `AgentToolName.chatTool` | 不可编辑，系统固定 |
| 可信 Turn/Loop 时间上下文 | `Soma/Models/AgentTurnContext.swift` → `TrustedTurnContext.promptText` | `AgentTurnContextBuilder.build`、Job 首次 claim 冻结 `loopStartedAt` | 不可编辑；只持久化时间戳和 IANA 时区，format 时生成日期与 offset |
| 确定性业务上下文包 | `Soma/Services/AgentContextPackBuilder.swift` | `ConversationProcessingContextFactory.make` | 不可编辑，本机事实派生 |
| 最近会话、事实引用与媒体选择 | `Soma/Services/AgentTurnContextBuilder.swift`、`ConversationContextProjection.swift` | `ConversationProcessingService.runAttempt` | 不可编辑，确定性投影 |
| 位置、健身房和天气 Turn 上下文 | `Soma/Services/ConversationProcessingService.swift` → `turnContext`；`WeatherContextProvider.swift` | `composePersistentContext` | 不可编辑，按授权临时生成 |
| 版本化当前 Turn User Prompt | `Soma/Services/ReActAgent.swift` → `ReActAgentPrompt.user`、`historicalUser` | `AIService.runAgent` | 不可编辑；固定 v1 section 顺序，动态输入与媒体位于后部 |
| 本地 Agent system/user/history 消息 | `Soma/Services/AppServices.swift` → `agentInitialMessages` 及相邻 helper | `AIService.runAgent` | 不可编辑；system 中可编辑部分来自上方 ReAct 节 |
| 中断恢复的压缩观察提示 | `Soma/Services/AppServices.swift` → `compactedCheckpointPrompt` | `AIService.runAgent` | 不可编辑，只包含已持久化短观察 |
| 远程 Agent system/user 消息 | `Server/src/provider.ts` → `OpenAICompatibleManagedProvider.run`、`userMessage` | 远程 Worker provider step | 不可编辑，Server 固定 |
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
