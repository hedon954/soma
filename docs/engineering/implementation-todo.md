# Soma 训练智能与可靠 Agent 全量 Todo

- 状态：执行中
- 创建日期：2026-07-31
- 完成标准：所有复选项完成，并由代码、测试、运行证据、真机安装和远端提交共同证明
- 关联：
  - [PRD 010](../prd/010-exercise-library-plans-guided-training.md)
  - [PRD 011](../prd/011-durable-agent-jobs-remote-continuity.md)
  - [实施次序](implementation-sequence.md)

本文件是本轮“一次性完成所有任务”的持久跟踪面。复选框只能在证据充分时勾选；已有相近代码
不等于完成，必须对照 PRD、ADR、协议和验收矩阵审计。

## 0. 契约与基线

- [x] 完成 PRD 010/011。
- [x] 完成 ADR 0028—0035。
- [x] 完成训练领域模型与 Agent Job 协议。
- [x] 建立双向文档生命周期规则和自动检查。
- [x] 同步最新 `origin/main` 并解决现有文档编号与实现冲突。
- [x] 审计远端已有连续会话、逐组训练、自适应模型和媒体关联实现。
- [x] 为本轮实现同步 Changelog、验收矩阵、Bug 状态和全部相关文档。

## 1. 本地持久发送与 Agent Job

- [x] 新增持久 `AgentJob` 模型和本地状态机。
- [x] 新增 Outbox 状态与重试元数据。
- [x] Turn、媒体引用、上下文快照和 Job 在同一事务中保存。
- [x] 持久化成功前不清空输入框和附件。
- [x] `ConversationProcessingContext` 构建不依赖 `CoachView`。
- [x] App 启动发现 queued/running/waiting Job。
- [x] 数据空间切换不会领取错误空间 Job。
- [x] 备份、恢复、清除覆盖新增 Job 模型。
- [x] 测试提交失败、立即终止、重复 submit 和跨空间隔离。

## 2. Event Log、投影与本地恢复

- [x] 新增带稳定 sequence 的语义 `AgentEvent`。
- [x] token delta 仅走实时流并合并快照，不逐 token 落库。
- [x] Chat projector 从 Event 生成有序卡片。
- [x] Trace projector 从同一 Event 生成 Span。
- [x] 通知和 Live Activity 使用独立 cursor。
- [x] UI 读取事件不删除日志。
- [x] 建立串行 `AgentJobRunner` 和原子领取。
- [x] 建立可注入 `BackgroundExecutionLease`。
- [x] 到期保存 `waitingForForeground` 并取消 SSE。
- [x] 回前台或重启为同一 Turn 创建新 Attempt。
- [x] 不续接半条 SSE 或半个 Tool Call。
- [x] 成功 mutation 通过 Receipt 跨 Attempt 幂等。
- [x] 自动化覆盖 lease、恢复、取消、终态和 Event 压缩。
- [ ] 真机覆盖 Home、锁屏、切 App、网络切换和系统挂起。

## 3. 动作身份与 Agent Tool

- [x] 新增 `ExerciseDefinition` 和稳定动作 ID。
- [x] `WorkoutEntry` 增加可空 `exerciseID`。
- [x] 新增固定 `list_exercise_names` Tool。
- [x] Tool 只返回当前空间全部 `{id,name}`。
- [x] `record_workout` 支持已有 `exercise_id` 和新建 `exercise_name`。
- [x] `update_workout` 保持动作 ID 引用。
- [x] 失效 ID 返回可恢复错误并要求重新读取列表。
- [x] Agent 提示与 Schema 要求记录前完成动作选择。
- [x] 本地不建立第二套语义投票。
- [x] 实现动作改名、归档、合并和安全撤销。
- [x] 迁移现有动作字符串，不伪造无法确认的身份。
- [x] 备份、恢复、清除和导出覆盖动作及合并记录。
- [x] 测试错别字、漏字、简称、变式、同名并发和跨空间。

## 4. 动作历史与聊天快捷输入

- [x] 新增动作库列表、搜索和空态。
- [x] 新增动作详情与按 ID 汇聚的完整历史。
- [x] 展示最近值、趋势、媒体和个人提示。
- [x] 输入框按本地标准名称显示动作候选。
- [x] 点击动作把标准名称写入草稿。
- [x] 选定动作后显示最近一条训练记录。
- [x] 点击最近值只补入非空组、次、重量和间歇。
- [x] 候选不触发远程请求或业务写入。
- [x] 用户仍需主动发送消息。
- [x] 验证键盘、滚动、VoiceOver、Dynamic Type 和长名称。

## 4.1 静默内置动作内容与图片兜底

- [x] 包内预置 40+ 常见动作的名称、别名、教练提示、肌群和动作模式。
- [x] 包内提供动作示意图与前后人体肌群图，并记录第三方素材授权来源。
- [x] 内置目录不创建 `ExerciseDefinition`，也不进入列表、搜索或 `list_exercise_names`。
- [x] 用户实际形成已知动作后只激活该动作的内置内容。
- [x] 激活采用 fill-only，不覆盖用户编辑的文字、肌群、动作模式或 generated/user 图片；目录
  升级只迁移旧 bundled 引用。
- [x] 动作列表最左侧显示动作示意缩略图。
- [x] 动作详情支持多张动作示意图与通用主要/辅助肌群图。
- [x] 单张动作示意图在详情卡片中水平居中，多张时才使用左对齐横向滚动。
- [x] 目录外动作显示中性占位，不用其他具体动作冒充。
- [x] 支持用户上传动作图与肌群图。
- [x] 标准 Provider 支持独立可配置 image model。
- [x] AI 动作图/肌群图只由用户主动点击生成，不在打开、记录或带练时自动调用。
- [x] 生成请求不自动发送用户照片、视频、训练历史或身体数据。
- [x] generated/user 图片进入合并、备份、恢复、清除、导出引用和媒体回收。
- [x] 自动化覆盖静默激活、fill-only、图片请求协议、合并/撤销与备份恢复。
- [x] 模拟器验证列表缩略图、详情多图、单图居中、前后肌群图、上传和生成失败态。
- [ ] 真机验证列表缩略图、详情多图、前后肌群图、上传和生成失败态。

## 5. 远程 Server 基础

- [x] 建立独立 `Server/` TypeScript 工程。
- [x] 建立 API、Worker、PostgreSQL migration 和测试基础。
- [x] 建立匿名设备 registration challenge。
- [x] 建立设备签名、短期 token、nonce 和重放防护。
- [x] 建立 App Attest 接口与可测试适配器。
- [x] 建立 Job 幂等提交和 `clientJobID` 唯一约束。
- [x] 建立 Event sequence、补拉和 SSE。
- [x] 建立事务 Outbox。
- [x] 建立 Worker lease/epoch、崩溃恢复和终态写入。
- [x] 建立临时媒体上传、digest、大小/type 限制和对象存储适配。
- [x] 禁止服务器根据用户 URL 抓取资源。
- [x] 建立内容 24 小时清理、7 天硬过期和非内容 30 天策略。
- [x] 建立无业务内容日志和清理告警。
- [x] 纯远程虚构任务在 App 终止后完成。

## 6. 双 Backend 与本地 Tool handoff

- [x] 定义 `AgentExecutionBackend`。
- [x] 现有设备 ReAct 适配为 Local backend。
- [x] 实现 Remote backend submit/events/cancel/tool result。
- [x] 设置提供默认关闭的“后台持续处理”。
- [x] 开启前展示数据流、Provider、保留和删除说明。
- [x] 单次任务可以选择仅本机。
- [x] 用户 BYOK 不上传服务器。
- [x] 远程执行只使用 Soma 管理凭据。
- [x] 固定远程 Tool 与设备 Tool 分类。
- [x] 服务端建立持久 `tool_request` 和 `waitingForDevice`。
- [x] 设备重新验证 Tool 名称、Schema、Turn、空间和取消状态。
- [x] Tool Result 按 `toolCallID` 幂等。
- [x] mutation 继续由本地 Receipt 防重。
- [x] Server/Provider/协议错误可解释并可降级。
- [x] 主动清除和关闭远程执行撤销 Job 与设备 token。

## 7. Live Activity、APNs 与通知

- [x] 定义隐私安全 `ActivityAttributes/ContentState`。
- [x] Widget Extension 增加 `ActivityConfiguration`。
- [x] 本地 Job 映射排队、运行、等待前台、完成和失败。
- [x] 不展示健康文本、用户原文、媒体或虚假百分比。
- [x] 一个当前 Job 对应一个 Live Activity。
- [x] 服务端登记和轮换 ActivityKit token。
- [x] 服务端通过 APNs 更新和结束活动。
- [x] 处理推送重复、乱序、丢失、预算和 token 失效。
- [x] 使用 `staleDate` 表达可能过期状态。
- [x] 本地 Event 同步纠正系统表面。
- [x] 完成通知与 Live Activity 去重。
- [x] 点击系统表面深链到对应 Turn。
- [x] 无灵动岛、权限关闭和系统限制正常降级。

## 8. 计划、模板、Session 与 Set

- [x] 审计并复用远端已有有序逐组训练证据。
- [x] 新增 `TrainingProgram`。
- [x] 新增不可变 `WorkoutTemplateVersion`。
- [x] 新增 `TemplateExercise` 与 `firstSetIsWarmup`。
- [x] 新增/完善 `WorkoutSession`。
- [x] 新增 `ExercisePerformance`。
- [x] 新增/完善 `WorkoutSet` 计划值和实际值分层。
- [x] 新增 `RecommendationSnapshot` 与输入指纹。
- [x] 开始训练冻结模板快照。
- [x] 计划编辑不改变已开始或已完成 Session。
- [x] 旧聚合训练不拆成虚构 Set。
- [x] 统计兼容旧记录和新完成 Set 且不重复。
- [x] 新增计划查询、创建、更新和归档 Tool。
- [x] 新增计划 GUI 审查、排序、替换和删除。
- [x] 新增确定性就绪检查。
- [x] “优化本次训练”才调用 AI 并缓存建议。
- [x] 备份、恢复、清除和导出覆盖全部计划模型。

## 9. 程序化带练

- [x] 建立 App 生命周期 `GuidedWorkoutCoordinator`。
- [x] 实现准备、说明、倒计时、执行、确认、休息和完成状态。
- [x] 实现暂停、恢复、跳过、替换、修改实际值和提前结束。
- [x] 每次用户确认组后立即保存恢复点。
- [x] 未确认组在异常退出后不自动完成。
- [x] 休息按持久时间重算。
- [x] 本地语音和震动提示不依赖模型。
- [x] 网络和 Provider 失败不阻止训练。
- [x] 完成时生成本地确定性摘要。
- [x] 可选总结 Turn 只查询 Session，不重复训练事实。
- [x] UI 支持空态、长文本、旋转、前后台和辅助功能。

## 10. 每动作自动录像

- [x] Session 开始时显式启用自动录像。
- [x] 前置摄像头预览和入框提示。
- [x] 麦克风默认关闭。
- [x] `firstSetIsWarmup == false` 录第 1 组。
- [x] `firstSetIsWarmup == true` 录第 2 组。
- [x] 目标组倒计时后自动开始，确认完成时自动停止。
- [x] 每个动作默认一段 active 视频。
- [x] 实现暂停、取消、重录、替换和删除。
- [x] 处理权限拒绝、相机中断、后台、磁盘不足和热压力。
- [x] 相机失败不阻断带练。
- [x] 视频默认留在 `PrivateMedia`，不自动写系统相册。
- [x] 导出、备份、恢复、清除和媒体引用回收覆盖视频。
- [ ] 真机验证实际相机与长训练状态。

## 11. 动作内容、建议与视频复盘

- [x] 新增可编辑动作教练提示。
- [x] 新增主要肌群、辅助肌群和动作模式。
- [x] 使用自有或授权肌群图素材。
- [x] 支持多个用户示范视频。
- [x] 支持 Soma 自有/授权视频与外部链接来源。
- [x] 不抓取、下载或重新分发第三方课程。
- [x] AI 内容按用户请求生成并版本化。
- [x] 打开详情和开始计划不自动请求 AI。
- [x] 训练完成先输出本地摘要。
- [x] 用户选择 Performance 视频后才创建复盘 Job。
- [x] 分析保存证据、局限、输入指纹和时间。
- [x] 反馈绑定具体 Performance，可编辑和删除。
- [x] 单张图或缺失阶段不描述为完整动作。
- [x] 非诊断文案和停止训练安全提示通过验收。

## 12. 全量质量与交付

- [x] 所有新模型有迁移、双空间和数据真值测试。
- [x] 所有固定 Tool 有 Schema、幂等和权限测试。
- [x] 服务器单元、集成、migration、重启和安全测试通过。
- [x] iOS 单元、集成和模拟器 UI 关键路径测试通过。
- [x] `make format` 通过。
- [x] `make check` 通过。
- [x] `make verify` 通过。
- [x] `git diff --check` 通过。
- [x] 模拟器完成浅色/深色、键盘、滚动、长文本和安全区验收。
- [x] 真机完成签名构建、安装、启动并确认主进程运行。
- [ ] 真机完成安装、启动、相机、锁屏、后台、网络切换和 Live Activity 验收。
- [x] 验收矩阵逐项有当前代码或运行证据。
- [x] 工作树审计确认无密钥、真实健康数据、生成工程或构建产物进入 Git。
- [ ] 使用中文 Conventional Commits 提交全部逻辑变更。
- [ ] 推送 `main` 到 `origin/main`。
- [ ] 远端状态确认包含最终提交且工作树干净。
