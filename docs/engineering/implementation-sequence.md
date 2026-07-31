# Soma 训练智能与可靠 Agent 实施次序

- 状态：已执行；保留为依赖与回归顺序
- 日期：2026-07-31
- 关联：
  - [PRD 010](../prd/010-exercise-library-plans-guided-training.md)
  - [PRD 011](../prd/011-durable-agent-jobs-remote-continuity.md)
  - [训练领域模型与运行时协议](training-domain-model.md)
  - [Agent Job 与远程执行协议](agent-job-protocol.md)
  - [全量 Todo](implementation-todo.md)

本计划定义依赖、交付闭环与验证门禁。每一步通过验收后再进入依赖它的下一步；实现过程中若
要改变已采纳边界，先新增双向链接的 PRD/ADR 修订。

## 0. 文档与协议冻结

本阶段由当前文档变更完成：

- PRD 010/011；
- ADR 0028—0035；
- 训练领域模型与 Agent Job 协议；
- 双向文档生命周期规则；
- 目标验收矩阵与 Bug 回归边界。

门禁：所有前后替代关系双向可达，`make check` 通过。

## 1. 本地持久发送与 Agent Job

1. 建立 `AgentJob`、本地状态与 Outbox。
2. Turn、媒体引用、上下文快照和 Job 在清空输入框前原子保存。
3. `ConversationProcessingContext` 构建移出 `CoachView`。
4. App 启动可以发现 queued、running 和 waiting Job。
5. 先保持本地执行行为，不接服务器。

门禁：发送后立即终止 App，用户消息和待执行 Job 仍存在；失败事务不清空输入。

## 2. 本地 Event Log、投影与恢复

1. 建立单调 sequence 的语义 `AgentEvent`。
2. Chat 与 Trace 从同一事件源投影。
3. 高频 token delta 走内存流并合并快照。
4. 建立串行 `AgentJobRunner` 和 `BackgroundExecutionLease`。
5. 后台到期进入 `waitingForForeground`，回前台创建新 Attempt。
6. 保留 `AgentMutationReceipt` 跨 Attempt 幂等。

门禁：Bug 0002 不再永久卡在运行中；恢复不会重复训练、饮食或身体记录。

## 3. 动作身份与 Tool 合同

1. 建立 `ExerciseDefinition` 与可空 `WorkoutEntry.exerciseID`。
2. 实现 `list_exercise_names`，只返回全部 `{id,name}`。
3. 修改 record/update workout Tool 合同。
4. 迁移旧动作名称，无法可靠确认的保持待归一。
5. 实现改名、归档、合并与撤销。
6. 同步备份、恢复、清除与数据空间隔离。

门禁：同义自然表达归入稳定 ID；改名不改变历史；重复 Attempt 不创建重复动作。

## 4. 动作历史与聊天快捷输入

1. 动作列表、搜索和详情。
2. 接入静默包内动作内容；只为已存在动作 fill-only 激活示意图与肌群图。
3. 按 ID 汇聚旧聚合与新训练历史。
4. 输入框本地动作候选。
5. 选动作后展示最近一条训练值。
6. 点击后只补入非空草稿字段。
7. 为目录外动作提供用户上传和显式 AI 图片生成兜底。

门禁：空库不暴露任何内置动作；候选全程不请求网络、不直接写记录；图片生成只由显式点击
触发；用户仍主动发送。

## 5. 远程服务基础

1. 在独立 `Server/` 边界建立 TypeScript API、Worker 与 PostgreSQL schema。
2. 实现匿名设备 challenge、签名和短期 token。
3. 实现 Job 幂等提交、Event sequence、补拉与 SSE。
4. 实现事务 Outbox、Worker lease/epoch 和崩溃恢复。
5. 实现临时媒体上传与 TTL 清理。
6. 先只支持无本地 Tool 的虚构纯分析 Job。

门禁：App Force Quit 后远程 Job 完成；重连后事件一致；服务器日志没有业务内容。

## 6. 双 Backend 与远程 Tool handoff

1. 抽象 `AgentExecutionBackend`。
2. 接入 Local/Remote 两种实现和设置中的明确授权。
3. 固定远程/设备 Tool 分类与 Schema 版本。
4. 实现 `waitingForDevice`、Tool Request/Result 和重复结果幂等。
5. 接入当前固定 Tool，mutation 仍由设备落地。
6. 实现取消、过期、服务故障和协议不兼容降级。

门禁：纯远程任务持续完成；本地 Tool 任务等待设备并只产生一次业务副作用。

## 7. 系统进度、APNs 与 Live Activity

1. 建立隐私安全的 Job ContentState。
2. 在 Widget Extension 增加 ActivityKit。
3. 本地 Job 投影运行、等待前台、完成和失败。
4. 服务端保存短期 Activity token，并通过 APNs 更新/结束。
5. 接入通用完成通知和 Turn 深链。
6. 验证推送丢失、重复、乱序、token 失效和无灵动岛降级。

门禁：系统表面不泄露健康内容、不显示虚假进度，状态最终与 Event Log 收敛。

## 8. 计划、模板、Session 与 Set

1. 建立 Program、TemplateVersion、TemplateExercise。
2. 建立 Session、Performance、Set 与 Recommendation。
3. 开始训练创建不可变计划快照。
4. 统计同时读取旧聚合记录与新实际 Set，不重复。
5. 实现计划 Tool 和 GUI 审查。
6. 实现本地就绪检查与用户主动 AI 优化。

门禁：计划编辑不改变历史；计划/建议值不进入实际容量。

## 9. 程序化带练

1. 建立 `GuidedWorkoutCoordinator` 和持久状态机。
2. 实现倒计时、确认、休息、暂停、跳过、替换和恢复。
3. 每组确认即时保存事实。
4. 接入本地语音、震动与完成摘要。
5. 完成后可创建总结 Turn，但不重复训练事实。

门禁：断网、模型失败和页面切换不影响完成训练；异常退出不伪造完成组。

## 10. 每动作一组录像

1. Session 显式开关与前置摄像头预览。
2. 按 `firstSetIsWarmup` 选择第 1 或第 2 组。
3. 状态机控制自动开始和停止。
4. 实现暂停、取消、重录、替换和删除。
5. 处理权限、中断、后台、磁盘不足和热压力。
6. 同步导出、备份、恢复、清除和媒体回收。

门禁：每动作默认一段；相机失败不阻断训练；未授权素材不离开设备。

## 11. 动作内容与训练后复盘

1. 用户笔记、肌群元数据、多视频和来源字段。
2. AI 内容按需生成、缓存、版本化与恢复。
3. 本地关键阶段抽取。
4. 用户选择视频后创建分析 Job。
5. 反馈绑定 Performance，并展示证据和局限。
6. 先覆盖离线复盘，再评估有限实时计数和 Watch 输入。

门禁：无授权第三方内容不入库；单张图不被描述为完整动作；反馈可编辑删除且非诊断。

## 每步共同门禁

- 先补确定性测试，再实现行为。
- SwiftData 变更覆盖旧数据迁移、双空间、备份恢复和清除。
- 新远程数据流覆盖发送内容、授权、留存、删除和失败状态。
- UI 覆盖 VoiceOver、Dynamic Type、长中文、空态、浅色/深色和安全区。
- 代码或基础设施交付前运行 `make verify`；服务器增加独立 test/lint/migration 门禁。
