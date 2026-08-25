# ADR 0000：0.0.9 及更早收口（压缩起点）

- 状态：压缩起点；0.0.9 及更早滑出窗口后仍有效的架构收口
- 日期：2026-08-25
- 维护者：Soma maintainers
- 覆盖版本：0.0.1–0.0.9
- 部分替代：无
- 修订自：无。更早原文在 `docs/archive/`，仅供考古，默认不要读取
- 后续替代：
  - [ADR 0091](0091-action-level-planned-rest.md)（窗口内最旧活 ADR，0.0.10）
  - [ADR 0092](0092-react-internal-retry-and-user-controlled-recovery.md)
  - [ADR 0093](0093-bounded-per-reply-multimodal-feedback-context.md)
  - [ADR 0094](0094-user-first-versioned-bundled-action-art.md)
  - [ADR 0095](0095-metrickit-confirmed-crash-reports.md)
  - [ADR 0096](0096-source-backed-model-multimodal-capabilities.md)
  - [ADR 0097](0097-current-baseline-performance-budget-and-cache-invalidation.md)
  - [ADR 0098](0098-user-configurable-react-active-runtime-timeout.md)
- 上游依据：[PRD 000](../prd/000-origin-through-0.0.9.md)

本文是活 ADR 链的起点。只记录 0.0.9 收口时仍然约束实现的决策，不保留沿途已被替代的方案史。
0.0.10 起的修订见后续活 ADR。

## 背景

Soma 从个人 AI 健身工具收敛为聊天优先、本地优先的私人身体智能。0.0.1 到 0.0.9 的原文已经
按版本进入 `docs/archive/`。活窗口的 Agent 只需本收口加上最近三个营销版本的增量，否则会把
已被替代的过渡决策重新当作当前边界。

## 决策

### 产品与仓库

1. 无账户、本地优先；演示与个人 SwiftData 容器隔离，关闭 CloudKit。
2. 聊天是非结构化事实默认创建路径；训练计划 GUI 与带练确认是已授权的结构化例外，必须共用
   同一数据与验证边界。
3. `CLAUDE.md` 是工程契约；`project.yml` 是 Xcode 工程事实来源；`make check` 快速静态，
   `make verify` 含模拟器。文档修订使用双向生命周期索引。
4. 当前只打开 `SomaDataSchema`，不维护历史 VersionedSchema 链；不兼容变更必须新 ADR 并明确
   回填或重建。PostgreSQL 只允许向前 migration。

### 数据真值

5. 缺失值为空；AI 观察、用户事实和本地派生可区分。训练使用有序逐组次数与重量，容量由完整
   有效组派生。
6. 外部健康导入先归一化，按数据空间/来源/数据流维护 cursor，外部 ID 去重，来源删除需同步。
7. 业务身份为本机分配的 Int64；训练关系显式绑定动作库。Session 业务日与记录 `occurred_at`
   分离。
8. 计划、动作内容与热量结果只保留当前状态；已开始训练由 Session 处方快照保护。
9. 侧别与按次数/按时长归 `ExerciseDefinition`。独立逻辑组保存类型、目标、重量与备注；
   **计划组间歇与换侧间歇在本收口仍写入每条 `TemplateSetPrescription`**（0.0.10 起改到动作，
   见 ADR 0091）。实际休息证据仍逐组保存。
10. 总糖可空；升糖速度与依据成对保存，编辑菜品后失效。

### Agent 运行时

11. 原生流式 Tool Calling；Skills 可编辑，Tool 协议固定。一条远程 Attempt 一条 Trace，
    Event 流式更新 UI。thinking 不展示、不持久化、不执行。
12. 持久 Job、语义 Event Log 与独立投影。本地 step 检查点同气泡续跑且不递增 attemptNumber。
13. 规范化幂等签名与 pending 账本。create 每次新增，update 按 ID 纠正。
14. 未选快捷按钮注册当前协议全部 Tool；选中后只暴露按钮白名单。Skill 不持有工具权限。
15. 设备生成版本化模型输入；本机与远程同源。远程可选，匿名设备身份，本机 Tool handoff，
    Live Activity 只投影隐私安全状态。
16. LLM 失效时消息落盘暂存，恢复后 FIFO 补偿。明确欠费仅用户释放。
17. 活动执行预算与业务时间解耦；等待不计时。本收口固定文字/图片/视频 3/5/10 分钟
    （0.0.12 改为可配置，见 ADR 0098）。首增量 20/40/60 秒。每个模型步骤最多一次有界重试
    （0.0.11 改为三次 1/2/4 秒并禁止 Loop 外自动重试，见 ADR 0092）。
18. 十轮外滚动压缩可审查。可信时间、选择性媒体、按能力直传视频，失败后抽帧并诚实降级。
    多模态能力在本收口仍可按平台/模型名保守标注（0.0.11 改为必须有目录来源，见 ADR 0096）。

### 带练、媒体与界面

19. 确定性带练状态机；按需相机、有界 activation、部分录像证据。预览宿主所有权不得在开组时
    拆掉正在录像的 session。紧凑/放大预览与历史缩略 aspect fill。
20. 有序混合媒体为一等数据。原位审查卡不得替换 Event Cards；卡跟在产生它的步骤之后。
    饮食为菜品清单加派生汇总。
21. 语义双主题；无损有序训练证据编辑。训练是一级 Tab。免费签名 Widget 保持静态快速记录。
22. 应用内反馈经认证边界投递；个人阶段 QQ SMTP → 固定 Gmail，只发送用户填写内容与所选附件。
    本机诊断日志可静默上报；启动哨兵异常结束在本收口仍可作为崩溃证据
    （0.0.11 改为仅 MetricKit 崩溃，见 ADR 0095）。
23. 静默内置动作内容与按需插画；专属离线图至少 100（0.0.11 起 239 且用户图优先，见 ADR 0094）。
    肌群受力图程序化渲染，不把辅助肌群重分类为主要。

## 未选择的方案

- 不为非结构化事实重建传统新增表单。
- 不把服务器当作身体业务数据库。
- 不维护计划业务版本链；已开始 Session 用快照隔离。
- 不打开历史 SwiftData VersionedSchema 作为常规启动路径。
- 不提供无限 ReAct 运行或关闭活动执行预算。

## 结果

### 正向影响

- Agent 先读本收口，再读三个活版本增量，即可得到当前产品与架构边界。
- 0.0.9 及更早的过渡方案不再占用活上下文。

### 成本与限制

- 考古必须打开 `docs/archive/`；默认不要读。
- 下次版本滑出窗口时，必须把本收口与滑出版本**合并**成新收口，而不是只搬家。

## 验证

- 活 PRD/ADR README 以本文件为链起点，0.0.10 文档的修订自/部分替代指向本文件。
- `scripts/check-document-lifecycle-links.rb` 验证活文档互链；归档原文不要求与活文档互链。
