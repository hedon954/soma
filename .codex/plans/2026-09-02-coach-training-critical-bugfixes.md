# 教练与训练严重 Bug 修复跟踪

- 状态：带练崩溃已通过用户复验；第四轮教练消息增量渲染、思考隔离、进展能量和语音覆盖修复已完成自动化验证，待提交、推送与 iPhone 14 Pro Max 安装
- 建立日期：2026-09-02
- 范围：教练消息生命周期、训练 Tool 真值、训练记录展示、带练恢复、语音输入、会话命名、快捷相机、前台恢复性能、模型 Extra Config、思考事件与进展页能量口径
- 验证规则：每项先补回归测试，完成后记录局部测试、`make check`、`make verify` 与适用的真机证据

## TODO

- [x] BUG-01：相同训练组的快捷引用压缩为一段，异构组按连续同值分段。
  证据：`ExerciseLibraryTests.testQuickFillUsesLatestRecordedCapacityWithoutInventingValues`、`testQuickFillCompressesUnevenRunsWithoutGroupNumbersOrFinalRest`、`testQuickFillSplitsAdjacentRunsWhenRestOrSideChanges`。
- [x] BUG-02：Tool Schema v4 完整表达动作目标、侧别与逐组 evidence，并保持本地/远程等价。
  证据：App/Server Schema 均为 v4；`AgentBatchCreateToolTests.testExerciseAndWorkoutToolsAdvertiseSchemaFour`、`testSchemaFourRequiresExplicitPairedEffortsForBothLaterality`、`testBothLateralityPersistsPairedEffortsAndBackfillsExercise`，Server 33 项通过。
- [ ] BUG-03：Job 入队时预建同一回复并立即投影已接收状态。
  第二轮修复：`CoachMessage.text` 只保存 AI 正文；已接收、模型执行与等待原因使用稳定 Activity Item 原位流转，彻底删除普通正文样式的临时状态。`AgentStageFeedbackUITests.testReceivedAndModelRunningUseTheSameActivityCard` 已通过；待真机网络/FIFO 阻塞验收。
- [ ] BUG-04：训练卡单行紧凑布局、动作名优先和 0 kg 自重语义。
  第二轮修复：聊天卡关闭组编辑器内部按钮；底部同一行左侧“添加一组”、右侧“约 N kcal”；动作名缩小为 subheadline，并与目标、侧别、保存、删除保持同一中心线；数据行重排为 `20 秒｜自重｜3 组｜间歇 30 秒` 四个明确分组。浅/深色、长名称、左右侧别、底部同行与按钮 44pt 的 Simulator UI 回归已通过；待 Dynamic Type 与真机视觉验收。
- [ ] BUG-05：终态失败重试复用同一回复并清除陈旧失败；元信息可见间距等距。
  第二轮修复：时间、日志、反馈去掉额外补偿并改用独立 44pt 触达区内的紧凑可见图标；覆盖用户复测中的“时间与按钮重合”和“仍相距过远”两个边界；失败 Tool/Skill 在最终回复成功后仍保留，人工重试只清理待重跑失败步骤。元信息几何 UI 回归及 `AgentJobTests.testManualRetryRemovesFailureProjectionInPlace` 已通过；待真机人工重试验收。
- [x] BUG-06：Trusted Context 使用唯一、明确的本地时间与时区。
  证据：`AgentV2Tests.testTrustedTimeFreezesLoopStartAndFormatsAtPromptTime`、`testTrustedTimeKeepsNonWholeHourOffsetAndDaylightSaving`、`AgentJobTests.testLoopStartTimeIsFrozenAcrossManualRetry`。
- [ ] BUG-07：带练 SwiftData 生命周期防护、可恢复错误与未完成 Session 左滑删除。
  第二轮根因：三份 0.0.18 (22) 报告已用 UUID 完全匹配的 Release dSYM 符号化；相同 `SIGABRT` 均由 `GuidedWorkoutView.swift:182` 的多层 relationship 查询进入 CoreData `NSSQLGenerator`。第二轮已把带练画面改为 `GuidedWorkoutScreenSnapshot`，按 `sessionID → performanceID → workoutSetID` 单层标量查询并仅渲染 DTO；动作替换、阶段操作与记录投影也只跨异步边界传稳定 ID。用户已确认带练不再崩溃；未完成训练卡还必须保证底部内容不被裁切，左滑操作使用无文字的通用红色垃圾桶按钮。仍需完成十轮生命周期复验及导出新崩溃日志，才能关闭。
- [ ] BUG-08：流式滚动使用单一尾随状态机，禁止滚入空白区域。
  第四轮确认原架构问题：声明式 `scrollPosition`、多处竞争性 `scrollTo`、根视图订阅逐批 token，以及把“布局暂时离底”误判为“用户主动上滑”共同造成清屏与卡顿。现改为稳定消息行 + 单一尾随协调器；发送只追加用户/回复消息，流式只在叶子 TextKit 1 中追加增量并以 5Hz 合并滚动。键盘和新消息布局不得关闭尾随，只有真实拖动手势才暂停。`CoachMessageAutoScrollGateTests`、长流 Tab/主动上滑 UI 及“发送后定位新尾部、不清屏”UI 回归通过；仍需 Release 真机长会话、键盘和零 token 场景验收。
- [x] BUG-09：首次进入定位最后 AI 回复尾部；教练 Tab 仅双击回底。
  证据：`CoachTabBehaviorUITests` 4 项全部通过，包括首次/返回定位、单击 no-op、双击回到底部。
- [x] BUG-10：Session 默认使用 `MM月dd日 - 周X`，删除模型命名链并迁移存量标题。
  证据：模型命名服务与协调器已删除；`ConversationSessionTitleTests` 覆盖业务时区、跨日、手动重命名不改排序和兼容字段。
- [ ] BUG-11：语音停顿提交片段，后续识别只追加不覆盖。
  第三轮进一步定位：系统在静默期还会补标点或回退同一段 partial；旧实现把“文字变化”误作“声学活动”，不断移动 0.85 秒边界。现在只有 `SFTranscriptionSegment` 结束时间真正前进才刷新静默计时，无新声学证据的短 partial 也不得缩短可见文字。`CoachComposerStateTests` 14 项通过，新增同声学时间文本修订与可见文字不倒退回归；必须以中文真机连续 partial、两次停顿及停止再开始复验后才能关闭。
- [x] BUG-12：普通/带练统一按证据计算热量，按发生时间取体重并展示计算依据。
  证据：`WorkoutCalorieCalculatorTests` 覆盖真实/推算时长、异构组、逐组间歇、无事实保持 nil、训练前最近体重；投影、Tool 更新、卡片编辑和迁移均走统一回填入口。
- [ ] BUG-13：桌面、锁屏和 App Shortcut 统一经深链进入单一快捷拍照状态机；根层独占展示权，取消、失败、锁屏和重复投递都必须完整收口。
  代码完成：`CapturePresentationCoordinator`、根层 `fullScreenCover`、Scene 非 active 等待、重复交付幂等和进入后台取消；5 项状态机单测通过。仍需真实桌面/锁屏组件、相机权限和连续 10 次 Release 真机验收。
- [ ] BUG-14：前台恢复使用可取消 generation 协调器和当前 Session 不可变渲染快照；首帧后恢复 Job，网络与备份不得阻塞首个可交互区间。
  代码完成：首帧 gate、generation 取消、独立候选读取 Context、稳定 ID 回主 Context、备份取消、当前 Session 限额 DTO 缓存和 signpost 已接入；`ForegroundRecoveryCoordinatorTests`、`CoachMessageAutoScrollGateTests` 通过。仍缺规定的 Release 真机 5+5 次 Trace、内存警告复测与 warm p95 `<100ms` 数据。
- [ ] BUG-15：计划执行复盘复用动作训练记录。
  第二轮修复：复盘按 Session 和 `sourcePerformanceID` 读取对应 `WorkoutEntry`，复用进展页 `ProgressRecentActivityRow` 与 `ProgressRecentActivity.workout` 映射，展示压缩组次、容量和时间并进入同一训练详情；缺失投影按删除抑制事实决定显示“训练记录已删除”或幂等修复。共享映射单测及复盘 UI 回归已通过，待真机复盘验收。
- [ ] BUG-16：训练详情受力图默认展开。
  第二轮修复：删除受力图展开状态和 `DisclosureGroup`，正反面图与来源说明进入页面即显示，全屏放大保留。Simulator UI 已确认初始存在且无展开按钮；待浅色、Dynamic Type 与真机验收。
- [ ] BUG-17：Agent、Tool、Skill 全阶段反馈。
  第二轮修复：Item/Span 增加兼容可选的 `operationID` 与阶段；本地、Server、远程重连及设备执行统一投影 queued/modelRunning/preparing/running/waitingForDevice/completed/failed/cancelled，同一 operation 只更新一张卡。Server reasoning/Tool Event、App reducer 与逐态 UI fixture 均已通过；待真实慢 Tool、Skill 与等待设备验收。

- [ ] BUG-18：模型 Extra Config 可见、可编辑并真实进入请求。
  对齐 LumenPDF：按规范化 Base URL 保存 JSON；内置厂商按各自协议预填关闭推理参数；空白保存恢复默认，`{}` 明确不附加字段；拒绝非对象及 `messages`、`stream`、`stream_options` 保留键；编辑器支持等宽 JSON、语法着色、行号、当前行、撤销/重做、格式化和智能缩进。生产请求仍输出普通文本/原生 Tool Calling，只在 HTTP 请求 JSON 组装时深度合并 Extra Config。9 项 App 单测和 Server 默认/校验测试已通过，包含生产请求体合并且 `messages` 仍为普通文本；待真机设置页和真实厂商请求验收。

- [ ] BUG-19：用户开启推理时流式显示思考过程，结束后自动收起。
  `reasoning_content`、`reasoning`、`analysis` 与正文、Tool Call 分流；进行中使用 Agent 过程样式展开并持续更新，结束后同一思考 Item 持久化且默认收起，用户可手动展开；不得把思考写进 `CoachMessage.text` 或最终正文。厂商把内部草稿错误塞进正文通道时先隔离为思考，再请求一次只输出最终答案；工具续跑、重连和 Worker 替换保留思考上下文。本地/远程/Server 投影与回放已实现，Server 39 项通过、1 项仅因无 PostgreSQL 跳过；App 单元测试和思考逐态 UI 回归通过。待真实支持 reasoning 的厂商流式验收。

- [ ] BUG-20：进展页能量展示改为同口径、可追溯指标。
  不再把截至当前活动消耗按当天已过比例线性外推成 TDEE，也不把本地训练 MET 当作全部活动消耗。有 HealthKit 时显示截至当前静息、活动与总消耗；没有时明确显示“24h 静息估算”“今日训练消耗”和“基础 + 训练”，能量差沿用同一口径。截图中的两个 `—` 表示当天没有完整活动事实：前一天训练不会计入今天；本地训练热量也只有在当天每条记录都有发生前体重与时长/组次/间歇证据时才汇总，不能拿容量猜热量。来源页同步给出具体缺失原因；相关单元测试与 Simulator UI 回归通过，待真机 HealthKit 有/无活动能量两种路径验收。

- [ ] BUG-21：首个工作组进入执行态后自动录像必须可靠启动。
  第三轮根因：带练改为不可变快照后，倒计时拥有的 SwiftUI `.task` 会在快照切到 `setInProgress` 时被取消；原录像请求继承该取消，或在旧画中画宿主上等待超时，因此真机只进入第一组但未开始写文件。修复后先提交并刷新执行态快照，再由协调器独立持有录像启动任务；等待新相机宿主稳定后，按 Session、Performance、Set、Effort 稳定 ID 重新获取和校验事实，再调用录像。退出、暂停、跳过时统一取消待启动任务。`testAutomaticRecordingWaitsForInProgressSnapshotPresentation` 会主动取消倒计时任务并断言录像仍按“快照展示 → 宿主等待 → 开始录像”的顺序启动；相关带练与相机测试 71 项、`make check`、`make verify` 已通过，完整 XCTest 685 项与 Swift Testing 7 项无失败。修复提交 `d55241f` 已推送，Soma 0.0.18 (22) Release 已重新安装并启动到物理设备；待真机确认第一组出现录像状态并产出可回看的录像后关闭。

- [ ] BUG-22：训练记录按自然日分享。
  每个训练历史日期标题提供独立的 44pt 分享按钮；点击后按自然日重新查询当天全部 `WorkoutEntry`，不受当前列表分页或折叠状态影响。按日分享与计划执行分享已共同进入 `WorkoutSharePosterBuilder` 的训练记录批次聚合入口，统一生成动作摘要、完成组数、有效容量、热量、耗时、主要受力肌群和双面受力图，再复用同一个 `WorkoutShareSheet`。缺少热量或耗时事实时保持为空，不从相邻日期或计划原始 Set 补值。3 项按日聚合测试覆盖跨日排除、热量不完整与 51 条记录跨分页；深色完整分享流程和浅色标题按钮 UI 回归通过，截图确认标题按钮、双面受力图与两条动作聚合正常；`make check`、`make verify` 已通过，完整 XCTest 688 项与 Swift Testing 7 项无失败。实现提交 `0dd4f79` 已推送；Soma 0.0.18 (22) Release 已安装到物理设备，因设备锁屏未能由脚本自动启动。待解锁后的系统分享交互确认后关闭。

## 交付 TODO

### 第四轮（当前）

- [x] 修复发送后清屏与长流卡顿的增量更新/尾随机制，并补直接发送 UI 回归。
- [x] 修复语音同声学片段补标点/回退导致静默提交继续延期和可见文字倒退；定向测试 14/14。
- [x] 完成本地与 Server 思考/正文隔离、错误通道恢复和思考卡生命周期；Server 39 项通过、1 项数据库测试跳过。
- [x] 修正进展页 HealthKit 与本地回退口径，缺事实保持空并给出原因。
- [x] `make check`、模拟器构建、XCTest 703 项与 Swift Testing 7 项通过；长流 Tab、主动上滑和发送不清屏 UI 回归通过。
- [ ] 审查第四轮最终 diff，提交并推送。
- [ ] 构建 Release 并安装、启动到 iPhone 14 Pro Max `00008120-001203492678C01E`。
- [ ] 真机复验：发送不清屏、长流不卡顿、思考自动收起、语音两次停顿、进展能量说明、首组录像和按日分享。

### 前序轮次

- [x] 修复当前所有编译错误与失败测试，补齐 BUG-18～20 的确定性测试及思考逐态 UI fixture。
- [x] 重新运行本轮相关单元测试、Server 测试、Simulator UI 几何/逐态测试。
- [x] 运行 `make check` 与 `make verify`，记录第二轮新证据，不复用第一轮结果。
- [x] 审查最终 diff，只提交本任务范围；未发现越界二进制、凭据、临时产物或与本轮无关的业务改动。
- [x] 按中文 Conventional Commit 提交并推送 `main`：`70cb5c5`。
- [x] 使用匹配签名的 Release/设备流程安装并启动连接的 iPhone：Soma 0.0.18 (22) Release 已安装并成功启动；安装成功不替代人工交互验收。
- [ ] 真机人工门禁：带练 10 轮及新崩溃日志、训练卡布局、消息元信息、中文语音停顿、快捷相机桌面/锁屏、前台恢复性能、Extra Config 设置、思考展开/自动收起和进展页能量口径。
- [ ] 真机人工门禁：默认策略进入首个工作组时自动显示录像中，并在完成后得到可回看的录像文件。
- [ ] 真机人工门禁：从训练记录任一日期标题打开分享，确认海报包含当天全部动作、统计与受力图，并能调起系统分享。

## 当前执行顺序

1. 完成第四轮最终静态门禁与 diff 审查。
2. 提交、推送，并构建 Release 安装到 iPhone 14 Pro Max。
3. 真机复验 BUG-08/11/19/20/21/22；其余未结项继续按对应真机门禁关闭。

## 已锁定决策

- BUG-04 的“添加一组”改动已撤销，保留现状。
- 教练 Tab 单次再选保持 no-op，仅原生双击回到最后一条 AI 回复尾部。
- Session 升级时全部改为日期标题；升级后仍允许手动改名并恢复日期标题。
- `titleSourceRaw` 仅为已安装数据库兼容而保留，不再参与业务逻辑。
- 无体重或训练证据时热量保持 `nil`；不显示或保存伪造的 `0 kcal`。
- 快捷相机不得通过“外层媒体 Sheet → 内层相机 Sheet”嵌套展示；进入后台或锁屏时结束本次事务，恢复后不自动重开。
- BUG-14 在同口径 Release 真机 Trace 达到 warm 可交互 p95 `<100ms` 前保持未完成；静态审查和 Simulator 结果只记录为阶段证据。

## 验证证据

- 第一轮阶段证据（已被真机回归失败覆盖）：2026-09-02 的 `make check`、`make verify`、Server 33 项、XCTest 659 项、Swift Testing 7 项及定向 Simulator UI 曾通过；这些结果不代表第二轮实现已通过。
- 第二轮自动化证据：`make check`、`make verify` 通过；Server 37 项中 36 通过、1 项仅因未配置 `SOMA_TEST_DATABASE_URL` 跳过；XCTest 684 项及 Swift Testing 7 项全部通过。Agent 阶段/推理 UI 3 项全部通过；训练记录、复盘、受力图、元信息和进展能量相关 UI 12 项在修复后全部通过（10 项首轮通过，2 项修复后定向复跑通过）。
- Release 安装证据：Soma 0.0.18 (22) 已安装到物理设备 `00008150-0001145221DA401C` 并成功启动；可复用设备构建指纹记录为 `837F1BA9-9583-5432-A72C-D84B39F4033C-Release.stamp`。
- 第三轮 BUG-21 证据：`d55241f` 已推送；带练/录像相关 71 项、`make check`、`make verify` 通过，XCTest 增至 685 项且无失败；同一 Release 版本已重新安装并启动到物理设备，安装成功不替代第一组实际录像验收。
- 第四轮自动化证据：2026-09-04 `make check`、模拟器构建、XCTest 703 项与 Swift Testing 7 项通过；Server 39 项通过、1 项 PostgreSQL 测试因未配置数据库跳过；长流 Tab、真实拖动暂停尾随、发送后新尾部定位 UI 回归通过。Release 真机证据尚未补齐。
- 待补：BUG-07 新 Release 带练十轮与崩溃日志；BUG-08 长流式真机；BUG-11 中文语音真机；BUG-13 桌面/锁屏相机；BUG-14 Release signpost 与 p95；BUG-03/04/05/15/16/17/18/19/20 人工交互验收。以上证据补齐前，对应 TODO 保持未勾选。
