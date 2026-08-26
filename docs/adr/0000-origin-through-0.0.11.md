# ADR 0000：0.0.12 及更早收口（压缩起点）

- 状态：压缩起点；0.0.12 及更早滑出窗口后仍有效的架构收口
- 日期：2026-08-26
- 维护者：Soma maintainers
- 覆盖版本：0.0.1–0.0.12
- 部分替代：无
- 修订自：无。更早原文在 `docs/archive/`，仅供考古，默认不要读取
- 后续替代：
  - [ADR 0099](0099-behavior-preserving-modernization-and-three-version-docs.md)（窗口内最旧活 ADR，0.0.13）
  - [ADR 0100](0100-bounded-snapshots-continuous-stream-rendering-and-query-first-data-access.md)
  - [ADR 0101](0101-record-truth-and-agent-profile-context.md)
  - [ADR 0102](0102-source-workout-plan-execution-materialization.md)
  - [ADR 0103](0103-goal-directed-progress-energy-and-hypertrophy.md)
  - [ADR 0104](0104-independent-react-timeouts-by-media.md)
  - [ADR 0105](0105-root-aware-tab-reselection.md)（部分替代 Tab 再选决策）
- 上游依据：[PRD 000](../prd/000-origin-through-0.0.11.md)
- 下游落地：
  - [训练领域模型与运行时协议](../engineering/training-domain-model.md)
  - [数据库结构与 ER 图](../engineering/database-schema.md)
  - [全 App 性能审计报告](../engineering/performance-audit-2026-08-24.md)
  - [性能优化经验教训（2026-08-26）](../engineering/performance-optimization-lessons-2026-08-26.md)
  - [验收矩阵](../acceptance.md)

本文是活 ADR 链的起点。只记录 0.0.12 收口时仍然约束实现的决策，不保留沿途已被替代的方案史。
0.0.13 起的修订见后续活 ADR。

## 背景

Soma 从个人 AI 健身工具收敛为聊天优先、本地优先的私人身体智能。0.0.1 到 0.0.12 的原文已经
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
   `DataMigrationMarker.schemaVersion = 6` 命中后必须立即返回；根页面可交互前只做打开容器、当前
   marker 与中断一致性门禁，演示填充、媒体去重和孤儿回收在首帧后幂等执行。

### 数据真值

5. 缺失值为空；AI 观察、用户事实和本地派生可区分。训练使用有序逐组次数与重量，容量由完整
   有效组派生。
6. 外部健康导入先归一化，按数据空间/来源/数据流维护 cursor，外部 ID 去重，来源删除需同步。
7. 业务身份为本机分配的 Int64；训练关系显式绑定动作库。Session 业务日与记录 `occurred_at`
   分离。
8. 计划、动作内容与热量结果只保留当前状态；已开始训练由 Session 处方快照保护。
9. 侧别与按次数/按时长归 `ExerciseDefinition`。独立逻辑组保存类型、目标、重量与备注；计划组间歇
   与左右换侧间歇归 `TemplateExercise`，开始 Session 时才编译到 `WorkoutSet`，最后一组不生成
   组间歇。实际休息证据仍逐组保存。
10. 不保存图片无法稳定识别的总糖；升糖速度与依据成对保存，编辑菜品后失效。

### Agent 运行时

11. 原生流式 Tool Calling；Skills 可编辑，Tool 协议固定。一条远程 Attempt 一条 Trace，
    Event 流式更新 UI。thinking 不展示、不持久化、不执行。
12. 持久 Job、语义 Event Log 与独立投影。本地 step 检查点同气泡续跑且不递增 attemptNumber。
13. 规范化幂等签名与 pending 账本。create 每次新增，update 按 ID 纠正。
14. 未选快捷按钮注册当前协议全部 Tool；选中后只暴露按钮白名单。Skill 不持有工具权限。
15. 设备生成版本化模型输入；本机与远程同源。远程可选，匿名设备身份，本机 Tool handoff，
    Live Activity 只投影隐私安全状态。
16. LLM 失效时消息落盘暂存，恢复后 FIFO 补偿。明确欠费仅用户释放。
17. 活动执行预算与业务时间解耦；等待不计时。文字、图片、视频总预算分别保存在本机设置中，
    默认 3/5/10 分钟且限制为 3–60 分钟；本地 deadline 与远程版本化输入冻结同一值。首增量
    20/40/60 秒。尚无可见增量的瞬态模型步骤最多
    三次 1/2/4 秒退避；错误越过 Loop 后统一进入人工屏障，启动、前台、网络、配置和计时器不得释放。
18. 十轮外滚动压缩可审查。可信时间、选择性媒体、按能力直传视频，失败后抽帧并诚实降级。
    provider、地址和模型名都不是多模态证据；只接受模型目录明确字段或远程部署显式开关，未知时
    允许真实请求验证。视频能力不能从图片能力推导。

### 带练、媒体与界面

19. 确定性带练状态机；按需相机、有界 activation、部分录像证据。预览宿主所有权不得在开组时
    拆掉正在录像的 session。紧凑/放大预览与历史缩略 aspect fill。
20. 有序混合媒体为一等数据。原位审查卡不得替换 Event Cards；卡跟在产生它的步骤之后。
    饮食为菜品清单加派生汇总。
21. 语义双主题；无损有序训练证据编辑。训练是一级 Tab。进展的近 7 天、连续性和容量使用单张
    分段卡，最近活动有界显示并提供历史入口；全产品 Switch 使用系统外形与统一开启状态色。
    免费签名 Widget 保持静态快速记录。Session 倒序分页读取最近 10 条及更早哨兵，向上到顶后
    追加并保持视觉位置；短内容顶部对齐，超过一屏时首次贴底。
22. 应用内反馈经认证边界投递；每条 AI 回复可在原位提交文字、媒体和评分。只在发送时按消息 ID
    定向组装当前 Turn 的有界脱敏 Job/Trace 摘要，禁止全聊天或完整 Trace 扫描。只有 MetricKit
    `MXCrashDiagnostic` 能成立自动崩溃报告；启动哨兵只补上下文，不独立判定崩溃。
23. 静默内置动作内容与按需插画；显示优先级固定为 `user > bundled > generated > fallback`，
    专属离线图至少 239，升级只维护 bundled 引用，不覆盖用户图。肌群受力图程序化渲染，不把
    辅助肌群重分类为主要。
24. 根页面和详情查询使用稳定排序、谓词、`fetchLimit` 与 `fetchCount`，大量聚合在后台生成
    不可变快照；图片缓存按文件身份与目标像素定键并有 48 MB 成本上限。
25. 120 Hz Release 真机目标为 warm 常用交互 p95 小于 100 ms、冷页首个有效内容 p95 小于
    200 ms、滚动 hitch 小于 1%；缺少真机 trace 时不得宣称量化达标。

## 未选择的方案

- 不为非结构化事实重建传统新增表单。
- 不把服务器当作身体业务数据库。
- 不维护计划业务版本链；已开始 Session 用快照隔离。
- 不打开历史 SwiftData VersionedSchema 作为常规启动路径。
- 不提供无限 ReAct 运行或关闭活动执行预算。

## 结果

### 正向影响

- Agent 先读本收口，再读三个活版本增量，即可得到当前产品与架构边界。
- 0.0.12 及更早的过渡方案不再占用活上下文。

### 成本与限制

- 考古必须打开 `docs/archive/`；默认不要读。
- 下次版本滑出窗口时，必须把本收口与滑出版本**合并**成新收口，而不是只搬家。

## 验证

- 活 PRD/ADR README 以本文件为链起点，0.0.13 文档的修订自/部分替代指向本文件。
- `scripts/check-document-lifecycle-links.rb` 验证活文档互链；归档原文不要求与活文档互链。
