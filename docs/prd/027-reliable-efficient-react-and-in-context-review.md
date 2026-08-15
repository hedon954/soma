# PRD 027：可靠高效 ReAct 与原位审查闭环

- 状态：已实施，部分修订；真机交互与 Gmail 自动化验收待维护者确认
- 日期：2026-08-13
- 后续修订：
  - [PRD 028](028-retry-active-runtime-budget.md) 将整轮墙钟预算拆为可暂停的实际执行预算，并允许用户显式重试开启新窗口
  - [PRD 029](029-unified-local-remote-agent-model-input.md) 将稳定 Prompt、按意图 Tool 和并行语义统一到本地/远程 Backend
  - [PRD 030](030-agent-prompt-skill-context-and-tool-v3.md) 以条件上下文、Skill 直载和强类型 Tool 进一步缩短执行路径
- 修订自：
  - [PRD 004](004-soma-current-product.md) 的当前教练、进展、设置、计划与 Agent 失败重试基线
  - [PRD 010](010-exercise-library-plans-guided-training.md) 的计划处方可发现性、快捷训练记录与内置动作图覆盖
  - [PRD 020](020-gui-simplification-and-progressive-disclosure.md) 的进展、设置、聊天结果卡和空会话呈现
  - [PRD 021](021-llm-staging-explicit-configuration-and-input-suggestions.md) 的失效暂存与自动补偿语义
  - [PRD 022](022-react-reliability-and-context-awareness.md) 的 ReAct 检查点、Tool 暴露与上下文稳定性
  - [PRD 023](023-in-app-multimodal-feedback.md) 的设置页反馈入口
  - [PRD 025](025-trusted-context-direct-video-and-reviewable-meals.md) 的可信时间、超时与记录审查边界
- 下游落地：
  - [ADR 0062](../adr/0062-user-resumed-llm-interruption-barrier.md)
  - [ADR 0063](../adr/0063-step-resume-fixed-loop-time-and-deadline-hierarchy.md)
  - [ADR 0064](../adr/0064-deterministic-quick-write-and-latest-inline-review.md)
  - [ADR 0065](../adr/0065-intent-scoped-tools-and-prefix-stable-prompts.md)
  - [ADR 0066](../adr/0066-bundled-action-illustration-coverage.md)
- 上游依据：
  - [BUG 0015](../bugs/0015-billing-retry-loop-and-queue-order.md)
  - [BUG 0016](../bugs/0016-batched-tool-retry-repeats-completed-work.md)

## 背景

真实训练与欠费场景暴露出一组相关问题：额度耗尽后 App 每次前台都会重复失败；失败重试会重跑
整个 Loop、复制失败样式并刷新时间；结构化快捷输入仍绕经模型；Agent 写完记录后不能在聊天中纠错；
模型每步拿到过多 Tool；计划处方、当前健身房、反馈与新会话快捷入口不够直接；动作目录虽超过
两百个，专属动作图覆盖仍不足。

这些问题共同损害 Soma 的核心闭环：自然表达之后的执行必须可靠、节制、可审查，并且不能让
模型或界面把已经确认的结构化事实重新变成模糊文本。

## 用户结果

### 1. 欠费是人工恢复屏障

1. 明确的额度耗尽、账单或付款失败进入 `waitingForUser`，重新打开 App、回到前台和定时器都不
   自动重试。
2. 屏障后的新消息继续落盘并按 FIFO 暂存；屏障存在时不得越过旧消息执行，避免回复错序。
3. “暂存管理”展示当前数据空间的完整待处理列表，按发送时间给出内容摘要、状态与附件数量。
   用户可以左滑删除任意一条、清空全部，或一次性按 FIFO 顺序重试全部；删除队首后后续仍按
   顺序恢复。
4. 暂存管理中的「LLM 配置」与设置 Tab 读取同一个 `AIService` 事实源，不得以默认空值创建
   第二份配置草稿。
5. 普通网络波动、通用限流或服务端故障继续遵守可恢复暂存策略，不与明确欠费混为一类。

### 2. 重试失败 step，而不是重跑 Loop

1. 每个 LLM invoke 或 Tool Call 视为一个 step；成功 step 在检查点中保留，重试从首个未完成
   step 继续。
2. 重试复用同一 AI 气泡，移除旧失败态和半截文本；同一失败 step 被新状态覆盖，不堆叠失败卡。
3. Tool 副作用仍以幂等账本保护；已成功写入不得因为后续 LLM 失败而伪装成未发生。

### 3. 一次 Loop 只有一个可信时间基准

1. Loop 第一次被 claim 时冻结 `loopStartedAt`，后续 step、自动恢复和用户重试均复用该时间。
2. 持久层只保存 UTC 时间戳和 IANA 时区标识；日期、星期、UTC offset 与展示字符串在投影或
   format 时按用户时区生成。
3. 跨午夜的 Loop 不因后续 step 的墙钟变化把同一轮业务事实分到不同自然日。
4. 确定性快捷记录不属于旧 Loop，保存时间实时读取 `.now`。

### 4. 超时采用首处理与整轮两层预算

| 当前 Turn 媒体 | 第一次 LLM 首增量 | 整个 ReAct Loop |
| --- | ---: | ---: |
| 纯文字 | 20 秒 | 3 分钟 |
| 图片或关键帧 | 40 秒 | 5 分钟 |
| 直接视频 | 60 秒 | 10 分钟 |

- 首增量门禁只应用于 Loop 的第一次模型处理；后续 step 不设置单 step 首增量、idle 或总时限。
- 整轮预算最初从冻结的 `loopStartedAt` 计算且重试不重置；该边界已由 [PRD 028](028-retry-active-runtime-budget.md) 修订。
- 超时必须取消底层请求并产生可解释 Event，不能用固定 sleep 修复竞态。

### 5. 结构化快捷训练直接保存

1. 最近训练建议同时携带稳定动作 ID 和逐组事实，不依赖显示文字反解析。
2. 用户选择建议后，若只去除首尾空白且内容未变化、没有附件，发送直接走确定性训练写入；
   不要求 API Key，也不调用 LLM。
3. 用户修改任意内容或添加媒体后退回正常 Agent 路径，不能猜测其结构化意图。
4. 直存仍创建 User Message、Job、Trace、Tool Span、Assistant Event 与结果卡，保持发送、执行和
   展示解耦。

### 6. 最新 AI 回复提供原位记录审查

1. Agent 创建或更新训练、饮食、身体、健身房记录后，在同一 AI 回复内渲染原位可编辑卡片。
2. 卡片直接编辑和保存；删除使用确认，不再弹出独立编辑页面。
3. 只有当前 Session 最新一条 AI 回复里的卡片可编辑；发送新消息后旧卡片转为只读摘要，完整
   编辑继续在记录页完成。
4. 每次保存或删除向来源 AI Message 写入有界的“用户最新修订”块；下一轮上下文投影把它紧邻
   原回复提供给模型。不得改写历史 tool_call_id、Tool observation 或用户原文。
5. 卡片按稳定 record ID 读取当前 SwiftData 事实；模型文本不是卡片事实来源。

### 7. 训练计划与一级页面减摩擦

- 计划动作行直接展示并允许修改组数、次数、重量与间歇，不再把重量和间歇藏进“更多处方”。
- 进展首屏以完整卡片展示当前健身房、器械数量或说明；点卡片进入健身房列表。
- 反馈能力以“反馈”标题直接嵌入设置页最底部，不再经过“关于”或二级页面；说明文字和输入卡
  在 Dynamic Type 与安全区下保持独立间距，不被卡片或列表边界遮挡。
- 新 Session 根据当前健身房、最近动作和时段提供最多三个确定性快捷语；用户可在本机新增、
  删除最多六个自定义快捷语。

### 8. Tool 与 Prompt 的成本约束

1. OpenAI-compatible 原生 Tool Calling 保持不变：App 把固定 JSON Schema 置于 `tools`，模型以
   `tool_calls` 返回，设备确定性执行并以 `role: tool` 回传结果。
2. `core` 只保留读技能、读数据和展开能力；写记录移入 `records`，只有明确记录／修改意图才
   预选。建议类问题不得默认暴露 mutation。
3. System Prompt 只保存稳定身份、产品契约和 Tool 使用原则；User Prompt 使用固定版本与固定
   section 顺序：执行约束、可信本地上下文、当前输入、当前媒体清单。
4. 稳定 System、Tool 顺序和 User section 前缀置前；当前文本、动态媒体与按需扩展置后。后续
   step 复用同一上下文，只追加 assistant/tool 尾部，以提高 prefix KV cache 命中机会。

### 9. 动作图覆盖

1. 启动时继续保持静默目录，不把内置动作批量写入用户动作库。
2. 内置目录至少 100 个常见动作拥有专属动作图；资源声明必须由测试逐个验证存在。
3. 真机已有动作优先核对；本次读取仅确认动作名称与覆盖，不保存个人训练、媒体或健康数据。
4. 无专属图的长尾动作继续使用明确占位，不进行隐式远程生成。

### 10. Gmail 反馈到 Draft PR

维护者配置 Codex 桌面自动化每 3 小时读取一次新的 Soma 反馈邮件。每封反馈必须去重，并在隔离 worktree
从最新 `main` 建分支，依次完成隐私清洗、问题分析、必要 PRD/ADR、实现、测试、Changelog、
提交、推送和 Draft PR。自动化不得合并、发布、真机安装、携带真实身体数据或泄露邮件凭据；
不明确或高风险需求只产出分析与 Draft PR，不自行扩大产品范围。

详细运行边界见[反馈到 PR 自动化](../engineering/feedback-to-pr-automation.md)。

## 验收边界

- 欠费状态跨重启不请求模型；队列完整列表、单删、全清、按顺序重试全部、共享 LLM 配置和
  FIFO 有确定性测试。
- step 续跑、同气泡覆盖、冻结时间与跨午夜通过测试；序列化中不再出现格式化日期字段。
- 精确快捷建议在空 API Key 下创建训练记录，且 Trace 显示本地 Tool、记录时间为实时发送时间。
- 最新卡片可以保存／删除，旧卡片锁定；下一轮上下文包含有界修订块。
- 通用建议不暴露 `mutate_user_data`，记录意图才暴露；Prompt section 顺序有快照式测试。
- 专属动作图条目不少于 100，所有声明资源能在 App Bundle 找到。
- `make verify` 通过；模拟器检查浅色／深色、长文本、滚动和安全区。反馈邮件自动化与真机交互
  分别报告为独立验收，不用本地 build 冒充。

## 非目标

- 不让服务器直接写身体业务数据，不改变本地 SwiftData 为事实来源。
- 不承诺供应商侧一定命中 KV cache；这里只保证客户端可控的稳定前缀条件。
- 不让旧 AI 回复长期可编辑，也不把聊天变成第二套完整记录管理页面。
- 不由自动化合并 PR、创建 Release 或向外部分发含个人阶段反馈凭据的构建。
