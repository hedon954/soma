# LLM 提示词来源

每行对应一种实际请求。打开 System 或 User 文件可以顺着读到该角色的完整消息。System 随 App 版本固定。User 文件用占位符接收请求数据和本机上下文。

| LLM 场景 | System | User | 调用入口 |
| --- | --- | --- | --- |
| 教练对话，本机直连和远程执行共用 | [System](../../Soma/Resources/Prompts/coach_system_prompt.md) | [User](../../Soma/Resources/Prompts/coach_user_prompt.md) | `ReActAgentPrompt`、`AgentModelInputBuilder` |
| 会话滚动压缩 | [System](../../Soma/Resources/Prompts/conversation_summary_system_prompt.md) | [User](../../Soma/Resources/Prompts/conversation_summary_user_prompt.md) | `ConversationCompactionMiddleware`、`ConversationSummarySource` |
| 快捷按钮工具推荐 | [System](../../Soma/Resources/Prompts/shortcut_tool_recommendation_system_prompt.md) | [User](../../Soma/Resources/Prompts/shortcut_tool_recommendation_user_prompt.md) | `AgentToolRecommendationService` |
| 训练课程优化 | [System](../../Soma/Resources/Prompts/training_optimization_system_prompt.md) | [User](../../Soma/Resources/Prompts/training_optimization_user_prompt.md) | `TrainingIntelligenceService.optimize` |
| 动作说明生成 | [System](../../Soma/Resources/Prompts/exercise_content_system_prompt.md) | [User](../../Soma/Resources/Prompts/exercise_content_user_prompt.md) | `TrainingIntelligenceService.generateContent` |
| 训练视频复盘 | [System](../../Soma/Resources/Prompts/performance_review_system_prompt.md) | [User](../../Soma/Resources/Prompts/performance_review_user_prompt.md) | `TrainingIntelligenceService.performanceReviewPrompt`、`AgentPromptConfiguration.capture` |

## 图片请求和追加消息

- [动作示意图](../../Soma/Resources/Prompts/exercise_illustration_prompt.md) 对应图像生成 API 的单个 `prompt` 字段。
- [最终答复恢复](../../Soma/Resources/Prompts/coach_final_answer_user_message.md) 在模型只返回推理时追加为同一次任务的 User 消息。
- [远程视频降级](../../Server/src/prompts/video-fallback.md) 在 Worker 从完整视频切换到关键帧时追加到对应 User 消息。Server 构建将这份资源复制到 `dist/src/prompts`。
- [默认教练人格](../../Soma/Resources/Prompts/coach_default_persona.md) 供设置页预览与恢复，作为 User 模板的上下文值。

## 内置教练 Skills

普通教练轮在 User 消息中附上可用 Skill 的简介和适用场景，模型按需加载正文。用户从快捷按钮选中 Skill 时，其正文直接进入当轮 User 消息。

- [健身房分析](../../Soma/Resources/Prompts/Skills/gym_analysis.md)
- [用户健身课程制定](../../Soma/Resources/Prompts/Skills/training_plan.md)
- [动作分析](../../Soma/Resources/Prompts/Skills/movement_analysis.md)
- [记录饮食](../../Soma/Resources/Prompts/Skills/nutrition_analysis.md)
- [体态分析](../../Soma/Resources/Prompts/Skills/posture_analysis.md)
- [运动趋势分析](../../Soma/Resources/Prompts/Skills/trend_analysis.md)
- [运动量分析](../../Soma/Resources/Prompts/Skills/training_volume_analysis.md)
- [运动热量估算](../../Soma/Resources/Prompts/Skills/calorie_estimation.md)
- [训练记录](../../Soma/Resources/Prompts/Skills/workout_logging.md)

## 维护规则

- 新增文本模型场景时，同时提交 `xxx_system_prompt.md` 与 `xxx_user_prompt.md`。System 文件保存完整的固定角色和任务规则，直接作为首条模型消息。User 文件用 `{{snake_case}}` 接收动态数据。iOS 模板随 App 打包并在首次使用时读取、缓存。
- 工具名、说明、参数和错误指引随工具定义与执行代码维护。原生工具说明由 App 放进 API 的 `tools` 元信息，远程 Worker 使用 App 提交的定义。Swift Schema 位于 `AgentToolJSONSchema.swift`、`AgentUserQuestionsSchema.swift`、`AgentEnergyContext.swift`。详见 [Agent Tool 目录](agent-tool-catalog.md)。
- 按钮预填和界面提示随 UI 或功能代码维护。历史记录、可信时间、媒体数量等动态事实由代码格式化后注入 User。
- 任务沿用发送时冻结的 System、人格、Skills 和工具定义。已有检查点重放已保存的模型消息。不同快捷按钮可以使用不同的工具集合，供应商缓存命中由实际请求和供应商决定。
- 新增或迁移模型场景时更新本表。运行 `make check` 校验配对、静态 System、占位符和目录覆盖，并运行 `make verify` 验证正常入口。
