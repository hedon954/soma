# ADR 0000：0.0.21 及更早收口（压缩起点）

- 状态：压缩起点；0.0.21 及更早滑出窗口后仍有效的架构收口
- 日期：2026-09-12
- 维护者：Soma maintainers
- 覆盖版本：0.0.1–0.0.21
- 部分替代：无
- 修订自：无。更早原文在 `docs/archive/`，仅供考古，默认不要读取
- 后续替代：
  - [ADR 0137](0137-agent-context-management.md)（上下文窗口、稳定消息与配置快照）
  - [ADR 0136](0136-agent-user-questions.md)（固定提问组件、始终曝光提问工具与确定性回答）
  - [ADR 0135](0135-agent-workout-calories.md)（仅训练工具优先采用用户明确提供的热量；省略时仍按 MET 计算）
  - [ADR 0134](0134-session-history-page-cache.md)（仅会话目录分页与缓存）
  - [ADR 0119](0119-full-video-and-append-only-dictation.md)（仅视频、语音或分享明细相关部分）
  - [ADR 0120](0120-focused-shortcut-prompt.md)（选中快捷按钮后不再注入全量 Skill 目录；工具白名单规则不变）
  - [ADR 0122](0122-nutrition-rings-and-period-deficit.md)（日页营养圆环与推荐摄入；Mifflin／PAL 估算不变）
  - [ADR 0123](0123-exercise-movement-kinds.md)（动作库分类由三轴收敛为身体部位及封闭动作类型；餐次配色不变）
  - [ADR 0124](0124-smtp-feedback-failure-taxonomy.md)（反馈失败分类与 IPv4 优先，仍用本机 QQ SMTP）
  - [ADR 0125](0125-eager-loaded-coach-messages.md)（已加载页即时排版与常驻缓存；尾随与双击回尾仍有效）
  - [PRD 058](../prd/058-feedback-duration-and-editable-calories.md)（仅补充预计消耗可被用户改写，公式仍是默认填充）
  - [ADR 0126](0126-workout-share-pro-max-canvas.md)（仅分享导出画布改为 Pro Max 纸面）
  - [ADR 0127](0127-agent-workout-weight-and-rest-zero.md)（仅 Agent 训练重量与组间间歇未说明时写 0）
  - [ADR 0128](0128-remove-healthkit-until-redesign.md)（撤回 Apple 健康导入与设备历史活动系数）
  - [ADR 0129](0129-daily-energy-net-training-increment.md)（仅日总计加入去重后的训练增量）
- 上游依据：[PRD 000](../prd/000-origin-through-0.0.11.md)
- 下游落地：
  - [训练领域模型与运行时协议](../engineering/training-domain-model.md)
  - [数据库结构与 ER 图](../engineering/database-schema.md)
  - [全 App 性能审计报告](../engineering/performance-audit-2026-08-24.md)
  - [性能优化经验教训（2026-08-26）](../engineering/performance-optimization-lessons-2026-08-26.md)
  - [验收矩阵](../acceptance.md)

本文是活 ADR 链的起点。只记录 0.0.21 收口时仍然约束实现的决策，不保留沿途已被替代的方案史。
0.0.22 起的修订见后续活 ADR。

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
   `make verify` 含模拟器。文档修订使用双向生命周期索引；活文档固定为压缩起点加最近三个营销
   版本，发布时归档滑出原文并把仍有效状态合并进起点。
4. 当前只打开 `SomaDataSchema`，不维护历史 VersionedSchema 链；不兼容变更必须新 ADR 并明确
   回填或重建。PostgreSQL 只允许向前 migration。
   `DataMigrationMarker.schemaVersion = 6` 命中后必须立即返回；根页面可交互前只做打开容器、当前
   marker 与中断一致性门禁，演示填充、媒体去重和孤儿回收在首帧后幂等执行。
   服务按 Conversation/Training/Media/Settings 现有能力拆分，不引入 DDD application/use-case/
   repository/entity 层、平行 DTO 或新的 `AppServices` 上帝对象。

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
10. 不保存图片无法稳定识别的总糖；升糖速度与依据成对保存，编辑菜品后失效。餐次先尊重用户
    明确表达，否则由本地 `occurred_at` 时刻确定；模型不能用孤立参数覆盖设备可确定事实。摄入
    分项显示餐次文字与固定双主题配色；未知热量和真实零值分开呈现，明细不重复汇总。
11. 基于当日原始训练生成计划时，同时物化一次已完成 Session。原始训练通过关系连接而不复制；
    删除 Session 只解除关系，不删除原始记录。

### Agent 运行时

12. 原生流式 Tool Calling；Skills 可编辑，Tool 协议固定。一条远程 Attempt 一条 Trace，
    Event 流式更新 UI。thinking 不展示、不持久化、不执行。数字参数按注册 Schema 归一化无单位
    数字与简单分数；仍不合法的值以 retryable `role: tool` 返回，同一 Loop 内由模型修正。
13. 持久 Job、语义 Event Log 与独立投影。本地 step 检查点同气泡续跑且不递增 attemptNumber。
14. 规范化幂等签名与 pending 账本。create 每次新增，update 按 ID 纠正。
15. 未选快捷按钮注册当前协议全部 Tool；选中后只暴露按钮白名单。Skill 不持有工具权限。
16. 设备生成版本化模型输入；本机与远程同源。远程可选，匿名设备身份，本机 Tool handoff，
    Live Activity 只投影隐私安全状态。
17. LLM 失效时消息落盘暂存，恢复后 FIFO 补偿。明确欠费仅用户释放。
18. 活动执行预算与业务时间解耦；等待不计时。文字、图片、视频总预算分别保存在本机设置中，
    默认 3/5/10 分钟且限制为 3–60 分钟；本地 deadline 与远程版本化输入冻结同一值。首增量
    20/40/60 秒。尚无可见增量的瞬态模型步骤最多
    三次 1/2/4 秒退避；错误越过 Loop 后统一进入人工屏障，启动、前台、网络、配置和计时器不得释放。
19. Agent 身体上下文使用称呼、性别、动态年龄、身高、最新有效体重及日期、目标和限制；不保存
    独立参考体重，缺少最新体重时保持未知。
20. 最近 30 个完整来回之外或历史文本估算超过 30,000 tokens 时滚动压缩可审查。可信时间、选择性媒体、按能力直传视频，失败后抽帧并诚实降级。
    provider、地址和模型名都不是多模态证据；只接受模型目录明确字段或远程部署显式开关，未知时
    允许真实请求验证。视频能力不能从图片能力推导。
21. 一次 AI 回复始终是一条 `CoachMessage`；入队事务预绑定响应身份，等待、失败与人工重试复用
    同一气泡。流式正文用单一 TextKit 文本面只追加已确认后缀，内部块不是展示结构。无换行尾部必须
    有界，投影 pump 合并主线程积压；完成态 Markdown 在后台准备不可变属性文本，流式期间始终跟随
    当前消息 ID 的真实底部。Session 默认标题由 `startedAt` 与业务时区格式化为 `MM月dd日 - 周X`。

### 带练、媒体与界面

22. 确定性带练状态机；按需相机、有界 activation、部分录像证据。预览宿主所有权不得在开组时
    拆掉正在录像的 session。紧凑/放大预览与历史缩略 aspect fill。
23. 有序混合媒体为一等数据。原位审查卡不得替换 Event Cards；卡跟在产生它的步骤之后。
    饮食为菜品清单加派生汇总。
24. 语义双主题；无损有序训练证据编辑。训练是一级 Tab，辅助肌群不重分类，不建立无个体依据的
    达标阈值。进展按日、周、月、年投影：日看当天记录，周看训练频率，月看容量与体重变化，年看
    按月积累。记录在 ModelActor 内按有界时间窗投影成不可变 DTO，View 不逐次查询或聚合模型。
    全天消耗 = 有效静息 × 活动系数 + 当天去重后的训练增量；系数优先个人设置，再默认参考 1.4
    （不写入个人设置，不含当天结构化训练）。不读取设备基础/活动能量。累计缺项按 0 加总并保留未知数。能量依据用紧凑数值列表，摄入与总消耗可
    点开彩色分项浮层。单项指标可审查来源与公式。训练分享固定白纸黑字与橙黄色主视觉，使用窄体
    大号容量、可审查的合并组次和独立于 App 双主题的图像；原生分享弹层继续适配双主题。
    全产品 Switch 保持系统外形与统一状态色，免费签名 Widget 保持静态入口。Session 倒序分页读取
    最近 30 条及更早哨兵，向上到顶后追加并保持视觉位置；短内容顶部对齐，打开 Session 停在最后
    一条末尾。单次再选教练 no-op，系统双击回尾。
25. 应用内反馈经认证边界投递；每条 AI 回复可在原位提交文字、媒体和评分。只在发送时按消息 ID
    定向组装当前 Turn 的有界脱敏 Job/Trace 摘要，禁止全聊天或完整 Trace 扫描。只有 MetricKit
    `MXCrashDiagnostic` 能成立自动崩溃报告；启动哨兵只补上下文，不独立判定崩溃。
26. 静默内置动作内容与按需插画；显示优先级固定为 `user > bundled > generated > fallback`，
    专属离线图至少 239，升级只维护 bundled 引用，不覆盖用户图。肌群受力图程序化渲染，不把
    辅助肌群重分类为主要。动作库保留身体部位及主要肌群，并把既有模式确定性投影为封闭动作类型；
    名称搜索与分类路径取交集，未知保持未标注，不猜测器械或难度，也不改写元数据。
27. 异步页面快照使用显式 load phase、单调 revision 和 `ModelContainer` 边界失效；失败可重试，刷新失败
    保留旧值，只有当前 request key 可提交。根页面和详情查询使用稳定排序、谓词、`fetchLimit`
    与 `fetchCount`；Job 领取保持 FIFO，业务去重只查可能命中的身份或窗口，不整表读入。
    iOS 17 不添加 `#Index` 也不直改 SwiftData SQLite；物理索引、版本化 schema 与回滚必须单独决策。
    PostgreSQL 索引只通过只向前 migration 增减，不为每列无差别建索引。图片缓存有 48 MB 成本上限。
28. 120 Hz Release 真机目标为 warm 常用交互 p95 小于 100 ms、冷页首个有效内容 p95 小于
    200 ms、滚动 hitch 小于 1%；缺少真机 trace 时不得宣称量化达标。
29. 四个 Tab 保持原生 SwiftUI `TabView`、持久根子树和独立导航栈。窄范围 UIKit 触摸桥只识别
    原生 `UITabBar` 上已选项的再次点按；教练与任一根页为 no-op，训练、进展、设置仅在非根页
    重置各自栈。根状态由 `@MainActor` 的轻量状态对象维护，不触发教练树重建。
30. 饮食汇总同时保留完整精确总计与已知小计；相同单位份数变更按比例更新当前估算。训练记录的
    `targetKind` 由动作定义投影。用户中断复用可见失败的持久状态、同气泡人工恢复与 FIFO 屏障，
    已成功 Tool 不回滚。设置与消息元信息只保留用户可理解的紧凑入口。

31. 回前台不重选可见 Session。Scene active 后先画出缓存首帧，再恢复可能挂起的 FIFO 队首 Job；
    远程撤销和网络等待在首帧之后可取消执行。快捷相机由根层状态机独占 `fullScreenCover`。
    带练异步边界只传稳定 ID，不跨 Context 持有 `@Model`。发送前继续执行跨日门禁。
32. Composer 的发送键在处理中复用为暂停，不增加第二个进行中停止入口。Trace 与反馈各保留独立
    44 pt 槽位并相向对齐。`MealEntry.recommendedEatingOrder` 与 Tool、幂等签名、查询、编辑、备份
    和导出共用同一字段；菜品变化后与升糖评估一起失效。字符串空默认值兼容旧库，便携格式 4 的
    可选字段兼容旧备份；不新增远程业务事实来源。
33. 训练 Tool 使用 Schema v4：目标类型、侧别、逻辑组、effort 与逐组间歇。普通训练与带练共用
    同一热量计算器；真实时长优先，否则每次约 4 秒加已记录间歇并标推算。缺体重或不完整证据时
    保持未知，不显示 `0 kcal`。

34. 发布使用与本地验证一致的 Xcode 工具链；编译成本过高的表达式拆成明确中间值。必须先完成同工具链质量门禁，再发布标签。

## 未选择的方案

- 不为非结构化事实重建传统新增表单。
- 不把服务器当作身体业务数据库。
- 不维护计划业务版本链；已开始 Session 用快照隔离。
- 不打开历史 SwiftData VersionedSchema 作为常规启动路径。
- 不提供无限 ReAct 运行或关闭活动执行预算。

## 结果

### 正向影响

- Agent 先读本收口，再读三个活版本增量，即可得到当前产品与架构边界。
- 0.0.21 及更早的过渡方案不再占用活上下文。

### 成本与限制

- 考古必须打开 `docs/archive/`；默认不要读。
- 下次版本滑出窗口时，必须把本收口与滑出版本**合并**成新收口，而不是只搬家。

## 验证

- 活 PRD/ADR README 以本文件为链起点，0.0.22 文档的修订自/部分替代指向本文件。
- `scripts/check-document-lifecycle-links.rb` 验证活文档互链；归档原文不要求与活文档互链。
