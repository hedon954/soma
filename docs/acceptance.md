# Soma 验收清单

本清单以当前 SwiftUI、SwiftData 实现和可重复运行的验证命令为准。自然语言与媒体事实由
教练对话创建；训练计划可在专用 GUI 中确定性编排，带练可保存用户逐组确认的事实。其他列表
和详情用于审查、纠错与删除结构化结果。

## 产品闭环

| 要求 | 当前证据 |
| --- | --- |
| 无账户、本地私有 | `DataSpaceController` 使用两个关闭 CloudKit 的 SwiftData 容器；媒体位于 App 沙盒，API Key 位于 ThisDeviceOnly Keychain。 |
| 演示/个人数据一键切换 | 高级设置提供分段选择；两个容器隔离，低频入口不会占用聊天页或造成误触。 |
| 启动数据迁移 | App 根层先显示迁移门禁，按个人空间、演示空间顺序用当前 `SomaDataSchema` 打开容器（不带历史 VersionedSchema 计划），再完成 Int64 分配、关系修复、旧聚合处方展开为 independent sets、旧 Set 变为单 `.none` Effort、为每条训练记录补齐不重复 projection key 并校验非空快照后才创建业务页面。失败保持可重试错误态，不允许在半迁移容器上继续读写；失败诊断必须含堆栈、错误 Mirror/Dump、SQLite 表结构、空/重复 projection key 计数和截断训练记录样例，且不含身体测量、饮食原文、聊天正文与媒体文件。当前 schema 上的预修复与 nil-key 回填测试必须通过；打开路径不依赖历史版本磁盘夹具。 |
| 聊天、图片、视频、语音 | `CoachView` 统一接收文字和媒体；单条消息最多混合选择十项图片/视频，三项起使用主图在前的稳定画布，后续媒体在同一画布上缩小、旋转并从右侧露出，避免极端横竖比破坏聊天节奏；显式展开后保留各自比例并可收起，点击任一聊天媒体进入只读全屏查看，图片可缩放、多项可左右切换；视频按模型能力直传或关键帧降级并明示实际模式；`SpeechInputService` 使用系统语音识别；消息正文支持完整 Markdown、原生范围选择与复制，用户绿色气泡的选区在浅色和深色外观下都使用高对比系统前景色。`MarkdownAttributedStringBuilder` 从 `presentationIntent` 重建段落与列表断行，避免教练回复黏连。 |
| 对话 Session | `ConversationSessionController` 在根层首次加载和 Scene 重新进入前台时解析当前 Session；今天有最后消息则复用，否则新建当天 Session；旧消息按自然日归档。历史抽屉可回看、继续，并支持左滑删除该对话的聊天图；训练、饮食、身体记录不随会话删除。在途 Agent Job 拒绝删除。 |
| 发送反馈 | 提交被接受后清空草稿与附件、撤销文本焦点并滚到稳定底部锚点；用户消息和 Agent Event 更新继续保持在底部等待回复。 |
| Widget 与系统快捷入口 | 免费签名阶段 `SomaWidget` 仅提供中尺寸文字、拍照、照片/视频快速记录；三种锁屏快捷组件与 App Shortcuts 提供相同入口。均只深链进入既有录入路径，不读取训练状态、不在扩展内写记录或运行 Agent。情境化组件见暂缓的 PRD 017 与 ADR 0042。 |
| 异步对话处理 | 发送先原子保存 Turn、媒体、上下文与 `AgentJob`；App 根层 runner 串行领取，有限后台租约到期进入 `waitingForForeground`。有有效 step 检查点时回前台或重启复用同一条回复气泡从下一步续跑且不递增 `attemptNumber`；无检查点的中断标为失败并保留手动重试，重新进入 App 不会自动重跑失败任务。 |
| 多个健身房和当前场馆 | 聊天可创建、更新、切换；健身房列表可直接选择当前场馆。 |
| 健身房审查 | 详情展示全部上传照片、AI 环境总结和器械列表；健身房与器械支持编辑、删除。 |
| 饮食与身体记录 | 聊天或媒体生成本地记录；饮食详情食物项与聊天菜品行共用同一套可编辑行。详情保留原始文字、食物/体型照片和 AI 说明。 |
| 训练与动作分析 | 训练动作使用稳定 ID；旧聚合与新逐组 Session 统一进入动作历史。包内动作内容保持静默，仅在用户形成动作后关联；列表展示动作图，详情展示多张动作图与程序化正背面肌群受力图。缺失字段保持空；动作示意图生成和视频复盘都只由用户主动触发，肌群图不再走 AI 生成。 |
| 动作快捷输入 | 输入框只在本地 active 标准名称中匹配；建议行一次给出「动作名 + 最近一次训练数据」，点一次写入完整草稿，没有历史时只写动作名。只修改草稿且仍由用户主动发送。 |
| 训练计划与带练 | PRD 031 的当前验收目标：计划详情依次展示可编辑概览、确定性训练效果和动作列表；侧别与按次数/按时长保存在动作定义，计划组只编辑该定义下有意义的次数或时长、重量与间歇。点击开始只选择一次三种录像策略即进入首个动作；计时与休息自动推进，进度按动作/逻辑组分段，语音播报组数与次数/秒数。动作记录先于 Session 自动完成，最后进入本地分享预览。实现中项目必须由启动数据回填、Coordinator、投影、热量和 UI 测试逐项证明，不能只以编译通过代替。 |
| 自动录像 | Session 可关闭、每动作首个工作组或每组自动录制；主界面始终保留主动录像。倒计时结束先在现有 PIP 宿主等到 `didStartRecordingTo`，再切 `.setInProgress`。每次请求拥有 attempt 单终态并绑定 Effort，成功 key 为 true 的有效文件必须保留；提前结束和重复 stop 不产生第二个 Alert。相机失败暂停自动策略但不阻断训练；失败提示给出具体原因与技术标识，`startingRecording` 与录像进行中不改写视频连接。紧凑与放大预览、历史缩略均 fill。真实 Delegate、系统中断和左右独立片段仍需真机证据。 |
| CRUD | 训练、饮食、身体详情进入即编辑，修改后显示保存；次要区块（受力图、热量估算、AI 解析、原始记录、宏量营养）默认折叠但展开后仍可完整编辑。训练记录逐组默认只编辑动作定义下的次数或时长与重量，不展示逻辑组或完成方式选择器。历史列表左滑红色图标删除。训练与饮食记录按自然日分组、常驻导航标题下「全部 + 按月」透明芯片筛选、按天可折叠，并支持分页加载；记录通过 `exerciseID` 关联动作库，列表行只保留主指标与取景比例缩略图，打开历史时对仅有名称的旧记录做确定性回填。健身房和器械也可修改与删除。 |
| 统计 | 进展首屏收敛为紧凑“当前上下文”入口、最近记录、带“最近 7 天”摘要的连续性热力图、体重趋势和训练容量趋势。 |
| 底部 Tab | 教练、训练、进展、设置四个 Tab 各自保留导航栈；换 Tab 不 pop，再点已选中的 Tab 才回到该 Tab 根页面。教练再选回到当前 Session，不清空对话。 |
| 时间粒度与拖动 | 体重和容量都支持周、双周、月、季，并允许横向拖动历史窗口。 |
| 身体信息 | 保存出生日期、生理性别、身高、参考体重、目标和备注；年龄动态计算，体态图通过身体记录历史回溯。 |
| 训练热量 | 使用本地 MET 公式；动作记录优先 Effort 实际时长，次数回退只用于热量并标估算。参考体重取 Session 开始前最近有效值再回退用户资料；计划执行只求和来源动作记录。缺体重保持为空并引导填写，不阻断训练、不写 `0 kcal`、不自动回填历史。 |
| 外部健康数据 | HealthKit 只读导入体重、训练和活动能量；转换为 Soma 模型，按空间/来源/数据流保存游标，使用样本 ID 去重并处理来源删除。 |
| 位置与天气上下文 | 位置只在用户开启后随发送获取一次；天气相关文本才向 Open-Meteo 发送小数点后两位的公里级坐标，只在内存中派生一般风险提示，失败不阻塞 Agent，关于页提供数据归属。 |
| 应用内反馈 | 设置底部以“反馈”标题直接嵌入 Soma 内置反馈表单，说明文字在 Dynamic Type 和列表安全边距下不被输入卡遮挡；一个输入区支持文字、照片和视频并直接发送，不跳转邮件 App，页面不出现 Base URL、Server、邮箱或 SMTP 说明。当前个人安装包通过 QQ SMTP 投递到固定 Gmail，只发送用户明确填写和选择的内容，不自动附带身体数据、聊天、Trace 或日志。客户端限制 5,000 字、10 项和 25 MB；外部分发前 `make online-check` 必须阻止客户端继续携带邮件凭据。 |
| 聊天提交反馈 | 用户当前消息明确要求提交 Soma 产品反馈时，Agent 调用无参数 `submit_feedback`，只发送当前消息原文和当前附件；普通训练/饮食/身体反馈不触发。Tool 等待实际 SMTP 结果，失败不伪装成功；远程模式进入设备 Tool handoff，不上传 QQ 凭据。 |
| 数据导出 | 用户选择目标文件夹后，饮食和训练按本地年/月/日生成文字、结构化 JSON 与有序媒体目录；不包含演示数据、API Key 或内部 Trace。 |
| 备份与恢复 | 首次选择外部目录并设置密码后立即备份，进入后台时尽力自动更新；完整个人空间与媒体经认证加密，错误密码或损坏快照不会改变当前数据。 |
| 主动清除 | 二次确认后删除个人空间和未共享沙盒媒体，保留演示数据、API Key、系统相册、Apple 健康及外部备份，并断开自动备份。 |

## Agent 闭环

| 要求 | 当前证据 |
| --- | --- |
| 六个平台 | OpenAI、DeepSeek、阿里云百炼、火山引擎、腾讯云和 opencode 均可配置 Base URL、API Key 与模型；Base URL 对所有平台可改写，按平台与档位独立保存。 |
| 动态模型 | 模型是纯文本输入框；保存 API Key 后调用当前平台 `/models`，过滤不可用状态，以输入历史式建议列表出现在输入框下方，可点选也可手输。候选行只显示模型 ID，不截断列表，超过五条时列表内部滚动。刷新候选不覆盖已填写的模型，只在为空时补一个默认值。 |
| 多模态提示位置 | 能力说明只在模型已填写后出现，且只占一行；文案明确说明是多模态能力（支持图片与视频关键帧 / 只能发送文字 / 未标注时由平台在发送时验证）。 |
| 多模态提醒 | 已知不支持的模型上传前阻止；未知能力由服务端验证，失败时把平台原始原因展示到聊天和 Trace。 |
| 真正 ReAct | 可配置步数上限（默认 100，高级设置 `ReAct 步骤上限`）的流式“模型自然语言或原生 tool_calls—本地工具—role=tool”循环；规范化幂等签名与 pending/committed 账本去重，工具失败可回到下一轮修正；供应商可并行返回 tool_calls，本机仍顺序执行。当前 32 个单一职责 Tool：未选快捷按钮注册全部，选中快捷按钮只注册该按钮工具白名单。未知名称解码失败。过长 Tool 结果可展开；原位审查卡与 Event Cards 同时保留。原始 JSON 只在开发者 Trace 中保留。 |
| Agent 纠错与删除 | 数据查询返回稳定记录 ID；训练、饮食和身体支持显式 update 工具原位纠错并合并新媒体；delete 工具仅接受用户当前消息的明确意图，且不级联删除聊天和共享媒体。create 每次新增，不能用创建代替更新。 |
| 跨消息去重 | 相同 Tool Call 由回执幂等；跨 Turn 训练/身体业务键返回疑似重复、不静默改写。纠正必须绑定查询得到的记录 ID。歧义时保持独立记录。 |
| 可继续 Session | 教练页左上角时间按钮、左边界右滑与 VoiceOver 操作打开同一个历史会话抽屉；可新建或选择旧 Session 继续发送，跨天不自动抢走当前选择。 |
| 输入区降噪 | 位置只在首次发送时确认一次，之后由设置修改；健身房少于两个时不显示场馆切换入口。 |
| 逐组训练 | 每项训练以有序 `set_entries` 保存单组次数和外部重量，组数取数组长度，容量逐组按完整事实求和；旧标量记录确定性展开。 |
| 视频输入证明 | 能力注册确认的百炼 Qwen 模型优先接收约 7MB 内的兼容 MP4，首请求不抽帧也不同时发送关键帧；其他模型使用明确关键帧模式。直传在首增量前失败才抽帧并消耗唯一重试，零帧且无直传视频时阻止请求。 |
| Session 上下文 | `AgentTurnContextEnvelope v3` 冻结原始 Turn 时间、Session businessDate、时区和 `defaultOccurredAt`，条件注入身体资料、当前健身房、业务日记录与近期体重。最近十个完整 user-assistant 对保持原生角色；更早历史在 Loop 前滚动替换为摘要并产生 Chat 事件卡。当前 Turn 有媒体时只发送当前媒体；明确回指选最近一个，比较最多两个。 |
| 双档模型 | 「LLM 配置」顶部是「标准模型 / 小模型」分段，两档共享同一套字段：平台、Base URL、API Key、模型同屏可见可改，标准档追加图片生成模型，小模型档追加启用开关，没有「高级」折叠层；两档保持独立配置且小模型可关闭；媒体、记录、纠错和安全敏感任务使用标准。 |
| AI 配置门禁 | 聊天不提供远程 Agent 开关或本地模式；标准档没有 API Key 时，发送与重试仍然原子落盘 Turn 与 Job 并进入 `staged`，不产生 Trace 或业务记录；首次未配置时同时打开「LLM 配置」并显示配置提醒。 |
| 回复文字选择 | Agent Markdown 回复使用系统可选择文本，支持长按选择与复制，并保留段落、列表和链接语义。 |
| 健身房媒体归档 | 本轮发图创建健身房会保存全部图片；下一轮要求创建或回答名称时，历史消息向模型提供 `recent_gym_turn` 语义引用，模型在 Tool Call 中选择后由 App 解析紧邻上一轮媒体位置，不暴露沙盒路径，也不读取更早或其他 Session 媒体。 |
| 媒体放大与单张解绑 | 聊天、健身房、训练、饮食和身体详情点击媒体进入统一全屏查看浮层；iOS 18+ 从缩略图 zoom，iOS 17 关闭系统弹出动画避免先黑后图。图片可缩放、多项可左右切换。聊天浮层只读，记录与健身房的删除入口只在浮层内；移除后封面与旧兼容字段同步更新，聊天原附件、其他记录引用和系统相册保持不变。 |
| 渐进式 Skills | System 只披露 `name/description/when_to_use`；`load_skill` 可按需加载。选中的快捷按钮绑定 Skill 时，首轮直接注入完整 Markdown 与专属上下文；内置 override、自定义 Skill 与 Markdown 预览可管理，Skill 不再声明工具权限。 |
| 输入框快捷按钮 | 快捷按钮可新增、改名、换图标、换绑 Skill、删除、拖动排序并单独控制显示；每个按钮持有工具白名单，默认全选、可按分组删减，也可由小模型推荐清单与理由后一键采纳。默认可见「饮食分析」「训练记录」「近期分析」三个，聊天最多显示六个。未知工具名在保存与运行时都被丢弃。 |
| 系统协议边界 | 固定身份、安全、真实性和授权契约不可编辑，仅人格可编辑；工具与严格参数 Schema 由 App 通过 API 注册，不进入 System Prompt；Skill 只描述方法，快捷按钮只能在当前协议内收窄权限。 |
| Trace | 一次远程消息生成一条成功或失败 Trace；model、skill、tool、output Span 作为 Event 实时更新 UI，并保存相对耗时、Token、入参与返回。 |
| 开发者设置 | 直接提供执行日志入口和数量；固定 Tool 协议不作为不可操作的设置项或说明展示。 |
| 持久 Job/Event | 每条消息拥有稳定 `AgentJob` 与单调语义 Event；Chat、Trace、通知和 Live Activity 维护独立 cursor，UI 读取不删除事件。 |
| 可选远程执行 | 设置默认关闭并披露数据流；单次可选仅本机。匿名设备签名、幂等 Job、Event 补拉、Worker lease 和设备 Tool handoff 由 `Server/` 提供，BYOK 不上传。 |
| Backend 输入等价 | iOS 用 `AgentModelInputEnvelope v2` 组装 system/history/current 消息、媒体 ID、Skill 快照、选中快捷按钮与 Skill、仅当轮有效的 Tool 定义、步数与时限；本机直接消费，远端只绑定临时 upload。Server 不含第二套 Agent Prompt；当前暴露的 runtime Skill 可就地执行，并行设备 Tool 全部持久化且结果齐备后按原调用顺序续跑。 |
| 系统进度 | Live Activity 只显示通用阶段、操作数和队列数，不含健康文本或虚假百分比；完成通知和系统表面深链到稳定 Turn。 |

## 已实现：训练智能

以下是 [PRD 010](prd/010-exercise-library-plans-guided-training.md)、
[PRD 012](prd/012-gui-training-program-authoring.md) 与
[PRD 013](prd/013-guided-workout-experience-and-capture.md) 的当前实现证据。

| 要求 | 目标验收 |
| --- | --- |
| 动作身份 | `ExerciseDefinition.businessID: Int64`、必需 SwiftData Relationship、`search_exercises` 和独立 create/update/archive/merge Tool；`create_exercise` 一次接收多个标准名，`create_workout` 一次接收多条已绑定动作 ID 的记录，新建记录 ID 由本机分配。旧 UUID 数据在启动迁移中按规范名回填，空名称进入明确待确认动作。 |
| 动作历史 | 动作详情按 ID 展示 `WorkoutEntry`；带练终态 Performance 先按来源 ID 物化为记录，旧 Session 尚未物化时才回退到 Session/Set，不能重复显示。合并记录迁移训练、模板、Performance/分析链和媒体，并只撤销本次引用。 |
| 静默动作内容 | `BundledExerciseCatalog` 提供 40+ 常见动作内容与授权/项目素材；空数据库不产生动作，已知动作创建后只 fill-only 激活自身内容，未使用目录条目不进入列表或 Tool。 |
| 动作图片 | 列表左侧加载紧凑动作示意图；详情首屏只读展示示意图、名称、折叠教练提示、紧凑单面肌群图与最近训练，编辑与媒体管理（用户上传、显式 AI 动作示意图生成、示范视频、外部链接）在工具栏菜单的子页。肌群图不再 AI 生成；既有 generated/user 肌群图仍可在媒体子页查看删除。generated/user 图片进入合并、备份、恢复、清除与媒体回收。 |
| 快捷输入 | `CoachView` 本地候选读取 active 名称；`ExerciseInputSuggestionBuilder` 优先读取统一训练记录，旧带练尚未物化时才读取 completed Set，一行给出动作名加最近一次训练，不重复候选、不请求网络、不写业务数据、不为缺失历史编造数值。 |
| 计划真值 | V5 以 `TrainingProgram.overview`、版本、动作、独立 `TemplateSetPrescription`、Session、Performance、逻辑 Set、原子 Effort 和 Recommendation 分层；开始训练冻结含 independent sets 的快照。V4 聚合处方只用于兼容迁移。 |
| 计划 GUI 创建 | `TrainingProgramCreationView` 与版本编辑器共享处方草稿、动作图片选择器和最近容量解析器；只读取当前 active 动作，以稳定 ID 调用 `TrainingPlanStore` 创建版本 1，空字段保持 `nil`。计划列表与动作编辑器把连续相同组收成一句，展开某一组后仍写入独立处方行。 |
| 统计兼容 | `TrainingStatistics` 以来源 Performance ID 在投影训练记录与原始 completed Set 间择一累计，不把计划、建议或同一带练动作算两次。 |
| 带练 V5 | Coordinator 按 current Performance/Set/Effort、deadline 和 transition revision 推进；`.both` 固定左后右，时长 Effort 与左右/组间休息到期自动推进且只能一次。Performance 终态先生成具有 business ID、动作关系、唯一 projection key 的 `WorkoutEntry`，全跳过不建记录；最后一个 Effort 自动完成 Session 并进入分享预览，不再等待“保存并结束”。本行在目标测试和 `make verify` 通过前属于实施中证据。 |
| 自动录像 V5 | `WorkoutCameraService` 将 Delegate/stop/中断归一为 attempt 终态，Coordinator 是唯一 Alert 源；Effort 保存独立视频，Set/Performance 录像路径只作兼容投影。success key、提前 finish、重复 finish/stop、同 attempt 单 Alert 和新 retry 新 Alert 必须有自动化测试，真实相机仍需真机。 |
| 训练系统投影 | 独立 `SomaWorkoutActivityAttributes` 只投影通用阶段、组进度和休息结束时间；本地通知与 `soma://workout/session/{id}` 深链不包含动作、重量或媒体。 |
| 视频复盘 | `PerformanceReviewView` 主动创建 Agent Job；`record_performance_analysis` 校验视频指纹并幂等绑定 source Job。 |
| 内容版权 | 用户视频、本地自有/授权来源和外部链接分层；不抓取第三方课程；通用肌群图不冒充个人受力。 |
| 数据主权 | Snapshot/DTO、开放导出、加密备份恢复、主动清除和媒体引用集合覆盖全部新增模型。 |

## 已实现：可靠 Agent 与远程持续执行

以下是 [PRD 011](prd/011-durable-agent-jobs-remote-continuity.md) 和
[BUG 0004](bugs/0004-agent-background-stream-interruption.md)、
[BUG 0005](bugs/0005-remote-agent-streaming-latency-regression.md) 的当前实现证据。远端持续
运行以部署 `Server/` 及配置 Provider、对象存储、App Attest 和 APNs 为前提。

| 要求 | 目标验收 |
| --- | --- |
| 持久发送 | `AgentJobStore.enqueue` 在一笔 SwiftData transaction 中保存 Turn、附件引用、上下文、Job 和首个 Event；失败时保留输入并回收副本。 |
| 本地 Outbox | `clientJobID == AgentJob.id`；等待网络保留 `nextRetryAt`，同一 ID 幂等重投。 |
| Event Log | 本地与服务端均使用唯一递增 sequence；分页/SSE 从 cursor 补拉，读取不删除。 |
| 前台流式等价 | Local Provider Event 与 Remote Server Event 都归一为 `AgentTraceEvent`；文本逐段投影，最终 output 校正完整答案且不重复拼接。 |
| 即时唤醒 | Provider 原生流式返回；PostgreSQL `LISTEN/NOTIFY` 唤醒 Worker 与 SSE；健康路径不使用固定一秒或两秒轮询。 |
| 本地恢复 | 注入式后台租约到期保存等待状态；新 Attempt 重跑且 `AgentMutationReceipt` 防止重复写入。 |
| 匿名设备 | Secure Enclave/Keychain P256 身份、challenge、短期 access/rotation token、nonce 与签名验证。 |
| 远程执行 | PostgreSQL 保存 Job/Event/Tool/Outbox；Worker lease/epoch 支持进程替换，纯远程步骤不依赖 App 存活。 |
| 设备 Tool | 服务端固定 schema 生成 `waitingForDevice`；iOS 复核 Tool、Turn、空间、mutation 并按 `toolCallID` 幂等返回。 |
| BYOK | iOS 提交不包含用户 API Key；Worker 只从部署 secret 读取 Soma 管理凭据。 |
| Live Activity | Shared ContentState 只含阶段、operation/queue count、sequence/stale；token 竞态、乱序和失效有收敛路径。 |
| 远程清除 | PostgreSQL cleanup 与对象存储删除覆盖终态确认、7 天硬上限、30 天元数据和设备撤销。 |
| 降级 | 远程默认关闭；协议、网络、Provider 和 APNs 失败分别映射为等待、可解释失败或本地同步纠正。 |

## 已实现：GUI 精简与渐进披露

以下是 [PRD 020](prd/020-gui-simplification-and-progressive-disclosure.md) 的当前实现证据
（v0.0.3，不新增功能）。

| 要求 | 当前证据 |
| --- | --- |
| 教练降噪 | Agent Skill/Tool 过程默认折叠为一条状态摘要行；「本次仅本机」为长按发送键菜单；Composer 上下文条单层展示；空态一句引导加两个示例；重试为低权重按钮；历史会话保留左缘右滑，并按 PRD 026 的真实使用反馈恢复左上角时间按钮。 |
| 训练降噪 | 统计/版本/AI 继续折叠、管理入菜单；计划首屏改为无标题可编辑概览、训练效果、动作列表。三种录像策略在点击开始后一步选择，取消准备页；主动录像成为执行页常驻控制，进度改为动作/逻辑组嵌套分段。逐组编辑只显示动作定义下有意义的字段，复制只创建独立副本。 |
| 进展降噪 | 足迹与动作库独立成卡，「最近记录」只保留训练/饮食/体重；足迹为朋友圈式 feeds 卡片（头像、正文可展开、宫格媒体、位置与相对时间）；视频缩略统一为 `VideoPosterView` 封面帧；记录编辑折叠受力图/热量估算/AI 解析/原始记录；历史行单主指标、筛选「全部 + 按月」。 |
| 设置降噪 | 设置为底部第 4 个 Tab，内容页右上角不再放齿轮；AI 服务「平台 → API Key → 模型」三步，Base URL/图片模型/小模型档进「高级」，保存与获取合并；任务进度与后台处理位于「更多」；身体信息核心三字段直出；隐私页仅位置开关加一句 footer；Keep/COROS 折叠为「其他设备」；远程数据边界折叠；Skills 二级页；「高级设置」文案统一。 |
| 动作库降噪 | 详情只读首屏 + 工具栏菜单进入编辑/媒体子页；提示文本直出无标题；受力图双面 210pt 可放大；示范视频首屏可看可传（与媒体子页共用 `ExerciseDemoVideoLibrary` 写入规则）；内置目录扩充纯文字条目（150+，键唯一与肌群可映射由单测门禁）；历史默认 5 条、更早折叠；列表行缩略图 48×54、副文案一行。 |
| 红线不破坏 | 聊天发送链路、全部记录 CRUD、missing-is-nil、API Key/HealthKit/导出备份清除/远程授权披露、带练状态机语义均未变化，折叠不等于删除。 |
| 设计系统 | `AppTheme` 提供 `cardRadius`/`controlRadius` 圆角 token 与 `listThumbnailSize`/`listRowVerticalPadding` 列表密度规范；重构涉及界面已替换硬编码样式。 |

## 已实现：LLM 暂存补偿与显式配置

以下是 [PRD 021](prd/021-llm-staging-explicit-configuration-and-input-suggestions.md)、
[ADR 0045](adr/0045-llm-outage-staging-and-compensating-drain.md) 与
[ADR 0046](adr/0046-explicit-llm-configuration-and-input-history-suggestions.md) 的当前实现证据
（v0.0.4）。

| 要求 | 当前证据 |
| --- | --- |
| 发送不被 LLM 状态阻塞 | 缺 Key 时连续发送三条：三条 Turn、媒体引用与 Job 全部落盘且为 `staged`，没有 Trace、没有业务记录（`SomaTests.testConversationProcessingStagesTurnWhenAPIKeyMissing`、`LLMOutageStagingTests.testMissingAPIKeyStagesMessageInsteadOfRejectingSend`）。 |
| 有任务在途仍可发送 | 发送键不再因 `isProcessing` 失效；后续消息按 `createdAt` 排队，前一条被后台租约挂起也不丢失（`AgentJobTests.testBackgroundLeaseExpirationKeepsJobRecoverable`）。 |
| 失败三分类 | `LLMOutageClassifier` 把传输错误映射为 `retryNetwork`，缺配置/地址无效/401/403/408/409/425/429/5xx 映射为 `stage`，400/404/413/422 与明确不支持多模态映射为 `fail`（`LLMOutageStagingTests`）。 |
| 暂存退避有界 | 供应商侧故障按 `2^n` 秒退避、上限 5 分钟；等待用户改配置的场景不设退避，靠配置变更信号唤醒（`testStagingRetryDelayGrowsAndCapsAtFiveMinutes`、`testStagingWithDelaySetsBoundedRetryWindow`）。 |
| 补偿消费 | App 启动、回到前台、`llmConfigurationDidChange`、上一条任务结束与退避到期只恢复普通可运行/可补偿 Job；明确欠费的 `waitingForUser` 不被这些信号释放。`AgentMutationReceipt` 继续保证同一 Turn 不重复写入。 |
| 暂存可解释 | 暂存中的用户消息显示「已暂存，恢复后自动继续」，输入区上方显示待处理计数与“管理”入口；管理页按发送顺序列出内容摘要、状态和附件数量，支持左滑单删、清空全部与按顺序重试全部，不展示状态机名称、退避秒数或供应商原始报文。自动补偿期间教练气泡不展示重试按钮。 |
| LLM 配置直出 | 「AI 服务」更名「LLM 配置」；顶部档位分段，平台/Base URL/API Key/模型同屏可改；模型、Base URL 与图片生成模型改动即落盘，不依赖返回时机，设置 Tab 与暂存管理入口始终从共享 `AIService` 读取同一值。 |
| opencode | 默认 `https://opencode.ai/zen/v1`，端点拼接与多模态标注（GPT/Codex 不支持、Claude/Gemini 支持、其余未知）由 `LLMConfigurationTests` 覆盖。 |
| 输入历史式建议 | `InputSuggestionList` 同时服务模型建议与聊天动作建议；动作建议最多 5 条、归档动作不出现、前缀命中优先，合并规则由 `ExerciseInputSuggestionBuilderTests` 覆盖。 |
| 红线不破坏 | Tool Schema、幂等边界、missing-is-nil、本地优先与 BYOK 均未变化；暂存只推迟执行时机，队列完全保存在本机。 |

## ReAct 可靠性与上下文感知

[PRD 022](prd/022-react-reliability-and-context-awareness.md) 与
[ADR 0047](adr/0047-deterministic-context-pack-and-cross-turn-facts.md)–[0050](adr/0050-per-turn-tool-group-exposure-and-parallel-calls.md)
的当前实现证据。

| 要求 | 当前证据 |
| --- | --- |
| 确定性上下文包 | `AgentContextPackBuilder` 生成有预算摘要；缺失字段不写、超预算确定性截断（`AgentReliabilityTests` 空态用例）。 |
| 领域查询 | 训练、饮食、身体与计划分别使用 list/get Tool；上下文已预加载的当日事实不再重复查询，趋势仍由 `AgentUserDataAggregator` 本地确定性聚合后注入。 |
| 跨轮事实 | 最近十对保持原生角色；`ConversationCompactionMiddleware` 将已有摘要与新移出窗口的完整对重写为替代摘要，小模型、标准模型、确定性 digest 三级回退；`AgentJobStore.events` 带谓词拉取。 |
| 规范化幂等 | `AgentToolCallSignature` 归一 trim/同义字段/数值/nil；`set_entries` 保序；失败 receipt 可重试（`AgentReliabilityTests`）。 |
| 业务级疑似重复 | 同日同动作同组指纹命中返回既有 ID +「疑似重复」，不静默合并（`AgentBusinessKeyDeduper`）。 |
| 同气泡续跑 | Job 持久化 `lastCompletedStep`/`loopCheckpoint`；有检查点时复用 `responseMessageID` 且不递增 `attemptNumber`；`DataIntegrityRepair` 不把可恢复中断标为 failed。 |
| 工具曝光与并行 | `AgentToolExposurePolicy`：未选快捷按钮注册当前协议 32 个 Tool；选中按钮使用该按钮 `toolNames` 与协议的交集，恢复时沿用 checkpoint 的 `exposedToolNames`。`parallelToolCalls=true` 且本机顺序执行。 |
| 延迟辅助 | 流式滚动约 10Hz 非动画节流；历史视频帧经 `VideoFrameCache` LRU；step ≥ 2 历史帧占位。Trace 可观测 `time_to_first_delta_ms`/`projection_ms`/`cached_prompt_tokens`。 |
| 红线不破坏 | LLM 摘要只替换更早对话且有确定性兜底，不静默跨轮合并业务记录；Tool Schema 仍固定；本地/远程共用版本化 Envelope。 |

## 可靠高效 ReAct 与原位审查

[PRD 027](prd/027-reliable-efficient-react-and-in-context-review.md) 与
[ADR 0062](adr/0062-user-resumed-llm-interruption-barrier.md)–[0066](adr/0066-bundled-action-illustration-coverage.md)
的当前实现证据。

| 要求 | 当前证据 |
| --- | --- |
| 欠费人工屏障与 FIFO | `waitingForUser` 不可运行且不被启动、前台、定时器或配置变化释放；`claimNext` 不跳过队首。“按顺序重试全部”统一释放待处理状态但仍由 `claimNext` 串行领取；`LLMOutageStagingTests` 覆盖欠费分类、后发暂存、批量释放顺序、单删和全清。 |
| 自动恢复与手动重试互斥 | Loop 内网络/供应商自动恢复把气泡保持为取消态且不展示重试；气泡进入 `.failed` 后提升为 `waitingForUser` 并停止自动领取。`ConversationTurnProjection.canRetry` 与 `promoteFailedResponsesToManualRetry` 测试覆盖。 |
| 每个 step 精确续跑 | 检查点持久化原生 `assistant.tool_calls` 和逐条 `role=tool` 结果；模型成功后、每个 Tool 成功后都立即落盘。双 Tool 回归证明第二个失败后只重试第二个，恢复请求的 System/User 前缀不变。 |
| 同气泡与固定时间 | 重试复用 `responseMessageID`，清理旧 error/running 投影；Job 创建时冻结原始 Turn 时间、`effectiveBusinessDate`、时区和 `defaultOccurredAt`，首次 claim 再冻结 `loopStartedAt`。create/update 的 `occurred_at` 省略时复用稳定默认值，排队、跨午夜和重试不使用新墙钟。 |
| 两层超时 | `AgentStreamDeadlinePolicy` 为文字/图片/视频 20/40/60 秒，仅首个模型处理启用；后续模型无单步门禁。`AgentLoopDeadline` 以 3/5/10 分钟活动执行预算取消当前窗口，等待用户、网络或前台不计时；自动恢复保留已耗时长，用户显式重试刷新预算但保留固定业务时间与成功 step。 |
| 确定性快捷训练 | typed 最近训练草稿 trim 后未改且无附件时使用 `deterministicWorkout` Job；空 Key 测试证明不调用 LLM、执行时间实时读取并产生同构 Trace/Event/结果卡。 |
| 最新回复原位 CRUD | 四类稳定 record reference 投影训练、饮食、身体和健身房卡；同一 Turn 不同动作各成一条记录、各有一张卡，卡片插在产生它的那一步之后，写入前后的文字保持原顺序。最后一条消息必须是 AI 回复才可编辑，发送用户消息后立即锁定。保存成功显示已保存态；删除写入有界 correction block。连续成功 Skill/Tool 收成一条可展开过程摘要，失败卡单独露出，Event Cards 不被结果卡替换。 |
| 计划与一级页面 | 计划编辑同屏提供组数、次数、重量、间歇；进展首卡直出当前健身房；设置底部直接嵌入反馈；空 Session 提供确定性和最多六条自定义快捷语。 |
| Tool 与 Prompt 节制 | 未选快捷按钮注册完整当前协议 Tool，选中按钮只注册该按钮工具白名单。System 使用分层 `[SOMA SYSTEM v2]`，User 使用 `[SOMA CURRENT TURN v2]` 固定顺序且空块完全省略；后续只追加 assistant/tool 尾部。 |
| 动作图覆盖 | 内置专属图条目不少于 100，Bundle 逐资源校验；真机核对得到的 24 个常见动作名称全部有确定目录映射与离线动作图，不把个人训练事实写入仓库。 |
| Gmail 自动化 | Codex 自动化 `soma-gmail-draft-pr` 每 3 小时运行一次；只处理一封未标记反馈，从最新 `origin/main` 建隔离分支并产出分析、必要 PRD/ADR、实现、测试、Changelog 和 Draft PR。成功建 PR 后才标记邮件；不合并、发布或真机安装。 |

## 消息元信息、快捷按钮 CRUD、可观测性与饮食双卡片

[PRD 033](prd/033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md)、
[ADR 0082](adr/0082-shortcut-owned-tool-bindings-and-method-only-skills.md)–[0085](adr/0085-record-cards-follow-the-producing-step.md)、
[BUG 0024](bugs/0024-streaming-cross-actor-swiftdata-crash.md) 与
[BUG 0025](bugs/0025-guided-recording-terminated-by-connection-reconfiguration.md) 的当前实现证据。

| 要求 | 当前证据 |
| --- | --- |
| 消息元信息单行 | `ChatMessageMetaLine` 在气泡底部输出一行 caption2：当天只显示 `HH:mm`，跨天补 `M月D日`，跨年补年份；用户消息带位置时同行显示「时间 · 位置」并对长 POI 中间截断，助手消息只显示时间。独立位置胶囊已删除，VoiceOver 合并朗读。 |
| 日期入口位置 | 记录日期入口位于导航栏 `principal` 的两行标题下方居中，输入区不再放日期芯片；改期仍持久化到 Session 并只影响本次对话默认日期。 |
| 快捷按钮存储 | `AgentInputShortcutStore` 以 UserDefaults JSON 保存增删改与排序，未知工具名在读写两侧清理；删除 Skill 时解绑引用它的按钮。`AgentInputShortcutTests` 覆盖默认三按钮、可见性与规范化。 |
| 曝光边界 | 选中按钮时 `AgentToolExposurePolicy` 只返回该按钮工具白名单与当前协议交集，未选时返回全量；`AgentJob.selectedShortcutID` 让排队、恢复与远程 Envelope 沿用同一判断，旧 checkpoint 的 `exposedGroups` 仍可还原。 |
| AI 推荐工具 | `AgentToolRecommendationService` 只在用户点按时发一次非流式请求，优先小模型档，返回清单与理由并丢弃未知名称；未配置模型或响应不可解析时保持原选择并说明失败原因，请求不含健康数据。 |
| 流式稳定性 | 流式 chunk 回调保持 `@MainActor`，文字增量经 `AgentTextDeltaCoalescer` 合批；segment id 携带形态标记保证 `ForEach` 身份唯一；DEBUG 下投影入口断言主 actor，`make check` 静态守卫这两条。 |
| LLM 工具清单可见 | 每次模型调用把 `exposed_tool_names` 与数量写进 model span metadata 和诊断日志；执行时间线只显示摘要，完整绑定工具/入参/返回在 Span 详情页可选择复制。 |
| 诊断日志 | `DiagnosticsLogStore` 双文件滚动记录生命周期、模型调用、Tool 结果、Turn 终态与录像阶段，恒定脱敏密钥与 Authorization，不写媒体 Base64。 |
| 崩溃误报边界 | `AppRunSentinel.isRunningUnderTests` 让测试进程既不置位哨兵也不上报；哨兵额外记录上次运行是否附着调试器，`CrashReportEligibility` 拒绝把调试器结束当成崩溃。设置页可丢弃排队报告。`CrashDiagnosticsTests` 覆盖这两条。 |
| 崩溃自动上报 | `AppRunSentinel` 识别上次异常终止，MetricKit 提供崩溃类型与堆栈；`CrashReportComposer` 汇总环境、崩溃 Session 上下文、最后一次 Job/Trace 与日志尾部，`DiagnosticReportMailer` 以独立主题和 `.txt` 附件发送，失败留盘重试、最多 5 份。高级设置提供总开关与查看入口。 |
| 录像失败原因 | `WorkoutRecordingFailureDiagnosis` 把 `AVError.Code` 与中断原因映射为具体中文原因并附 `（domain code · stage）`；非预期结束与中断都使用该诊断，同时写入诊断日志。 |
| 饮食双卡片 | 聊天内第一张「记饮食」卡是可直接改的菜品清单，行内可改名称、份量、kcal 与三大宏量并支持增删行与改餐次；第二张「饮食评价」卡只读，随草稿由 `MealNutritionTotals.derive` 实时重算，缺项显示「未估算」不补零，保存后写入值与卡二一致。 |
| 卡片位置 | `AgentTurnTranscriptSegments` 把 `record_refs` 插在产生它的 Tool 或过程摘要之后，重复引用只出一张卡，无法归位的兜底在末尾；饮食 Skill 要求写入前先说一句不含数字的识别说明。`AgentChatPresentationTests` 覆盖顺序与去重。 |
| 饮食时间 | `defaultOccurredAt` 保留发送时刻钟点，餐次按记录发生时刻推断；饮食 Skill 明确要求没有用户明确时间就省略 `occurred_at`。 |

## 已实现：历史、媒体、Tab 与带练取景打磨

[PRD 034](prd/034-history-media-tabs-and-guided-capture-polish.md)、
[ADR 0086](adr/0086-preview-and-history-thumbs-use-aspect-fill.md) 与
[BUG 0025](bugs/0025-guided-recording-terminated-by-connection-reconfiguration.md) 后续修订的当前实现证据。

| 要求 | 当前证据 |
| --- | --- |
| 媒体 zoom | `MediaViewer` 在 iOS 18+ 使用 `navigationTransition(.zoom)`；iOS 17 关闭 cover 动画并先交付已解码图。调用点经 `mediaViewerCover` / `mediaZoomSource`。`VideoPosterView` 未就绪占位为 `AppTheme.softTint`。 |
| 饮食行复用 | 详情 `MealRecordEditor` 与聊天共用 `MealItemDraftRow`；聊天 `InlineRecordShell` 内边距 10/7，菜名 footnote、宏量 caption2。 |
| 历史芯片与折叠 | `historyListChrome` 使用 inline 标题加图标；`HistoryMonthFilterBar` 无 `.bar` 实心底。每一天是 `HistoryDayHeader` 卡片，日期与条数与行缩略图共用 `HistoryDayCardLayout.horizontalInset`，折叠后仍显示条数与已知容量/热量。`WorkoutHistoryQueryTests` 覆盖饮食按天分组、摘要只累加完整容量/热量，以及同年芯片省略年份。 |
| Span 独立页 | `AgentTraceSpanRow` 是 `NavigationLink`；`AgentTraceSpanPayloads.sections` 分段入参/返回。`AgentTraceSpanPayloadsTests` 覆盖超长入参不依赖时间线内嵌。 |
| Tab 再选 | `AppTabReselect.stackID` 仅在 selected == incoming 时换 UUID；`RootView` 用 `.id` 重建该 Tab 栈。`AppTabReselectTests` 覆盖再选与切换。 |
| 自动录像宿主 | `beginCurrentSet` 先 `startRecording` 再 `setPhase(.setInProgress)`。`applyCaptureGeometry` 在 `startingRecording`/`recording` 跳过 movieOutput；`validate-repository.sh` 静态守卫。 |
| 预览 fill | `WorkoutCameraSurface` 与 `CameraPreviewView` 默认 `.resizeAspectFill`；历史录像缩略按取景比例 `scaledToFill`。 |

## 实施前文档门禁

- PRD 010/011、ADR 0028—0035 和两份工程协议相互一致；ADR 0034 固定文档生命周期，
  ADR 0035 固定静默内容目录与按需图片生成边界。
- 旧文与新文的修订、替代和研究落地关系双向可达。
- `make check` 执行 Markdown 链接、文档生命周期、隐私与仓库契约检查。

## 可重复验证

```bash
make verify

# 已登录免费 Apple 账号时的连线真机构建
DEVELOPMENT_TEAM=你的TeamID make install-device
```

TestFlight 需要付费 Apple Developer Program 和 App Store Connect 记录；免费 Personal Team 可以完成连线真机安装，但签名会定期过期。

天气真机验收需要开启“随消息记录位置”，分别发送普通饮食文本和户外运动文本：普通文本不
请求天气；户外文本即使断网也能完成 Agent。隐私页应披露公里级坐标与 IP 会发送给
Open-Meteo，关于页应能打开数据归属链接。

数据与备份真机验收使用虚构记录：导出后在“文件”中检查 `年/月/日/饮食|训练` 下的文字、
JSON 和有序媒体；设置密码备份后让 App 进入后台，再返回确认“最后成功”更新时间。恢复时先
用错误密码确认当前数据不变，再用正确密码替换恢复。清除前保留一份外部备份，清除后确认
个人空间为空、演示空间/API Key/系统相册/Apple 健康与外部备份仍在，且自动备份已断开。

锁屏组件需要真机手工验收：长按锁屏进入“自定”→“锁定屏幕”→“添加小组件”，确认 Soma
下出现文字、拍照、照片/视频入口；分别添加行内、圆形或矩形样式，点击后应先遵循系统解锁，
再进入对应的教练输入流程。

历史媒体验收使用虚构图片和视频：在同一 Session 先发送媒体，收到回复后再发送不带附件的
追问，确认 Agent 能引用前一轮画面；新建或切换到另一个 Session 后发送相同追问，确认不会
携带旧 Session 媒体。构造十一轮以上对话，确认远程请求只包含最近十个完整来回。

教练页手工验收：点击左上角时间按钮打开会话抽屉，再关闭并从左边界右滑打开同一抽屉；新建两个非空 Session 后来回切换并继续发送；
首次发送分别验证允许和拒绝位置都只出现一次确认；准备 0、1、2 个健身房验证只有两馆时
显示切换入口；长按用户绿色气泡并拖动选区，分别在浅色、深色外观确认选区与气泡明显区分，
且复制菜单仍可用；长按 Agent 的列表、链接和多段回复验证可精确选择复制。分别点击聊天中的
单张、双张和三张以上折叠媒体，确认从缩略图位置放大进入全屏、可切换与缩放，且没有删除聊天附件的入口，
过程中不先出现一块空黑全屏。准备四个以上虚构动作并查询两条虚构训练，确认过程默认只显示一条状态摘要行；点开后 Tool
卡片先显示结果数量或简短结论，展开逐项完整显示动作/训练信息但不出现 UUID、JSON、
`function` 或 `tool_call` 内部标记，收起后恢复紧凑高度。原始参数与 ID 应继续能在
“高级设置 → 执行日志”中审查：时间线只显示摘要，点 LLM 行进入独立页查看完整入参并可复制。

历史与 Tab 验收：打开训练历史，导航栏常驻「训练记录」标题与图标，其下是没有实心底条的「全部」和有数据的月份芯片，点日期折叠再展开当天；
饮食历史同样按天分组。从进展进入一条饮食详情，切到训练 Tab 再切回进展，仍停在该详情；再点
「进展」回到进展首页。教练再点回到当前 Session，对话仍在。

训练计划 GUI 验收使用两个虚构动作：计划详情从上到下是无标题可编辑概览、确定性训练效果、
动作列表和折叠历史/版本，不再出现“目标”“当前模板”两行。第一个动作配置 `.both`，包含热身
次数组、左右重量不同的工作次数组和工作计时组；第二个动作配置 `.right`。逐组新增、复制、
删除和排序后确认所有组完全独立，切换 target kind 不会同时保存次数与秒数，空字段没有被补齐。
再次编辑产生新版本，已开始 Session 的旧 `plannedSets` 快照保持不变。

开练与自动推进验收：点击“开始训练”立即看到“每个动作录第一组”“每一组都录”“不录像”，
任一选择后直接进入首个动作，不出现准备 Sheet、折叠录像区或第二个开始按钮。分别执行三种策略，
确认首组策略跳过热身并选择首个 working 逻辑组；所有策略下带练主界面都保留 VoiceOver 可达的
录像按钮。`.both` 固定左后右，左侧完成后进度半填，左右间歇归零自动进入右侧三秒倒计时；右侧
完成后组间间歇自动进入下一组。计时组归零自动写实际秒数并完成。暂停、锁屏、View 重建、前后台
和重复 timeline tick 都不得让同一 Effort 或休息推进两次。进入新动作仍等待“准备本动作”。

分段进度与语音验收：顶部按动作等宽分大段，每个大段按逻辑组切小段，`.both` 不把组数翻倍；
完成、当前、跳过和失败有颜色以外的表达。语音准确说出动作名、组数和每组次数/秒数；逐组参数
不同时逐组摘要，`.both` 明确“左右各做，左侧先开始”，过期语音不拖到下一阶段。

录像真机验收：完整 request 必须在权限、配置、Session 启动与写文件之前建立。选择自动录像后，
动作介绍/倒计时先依次显示请求权限、启动相机和相机已就绪，ready 时就能看到真实取景；倒计时
归零后红点应在仍为 PIP 时出现，随后才放大到本组取景，连续 3 组不得因换宿主提前结束。选择
“不录像”时相机保持关闭，直到点击常驻按钮。只有 `didStartRecordingTo` 后才出现红点。分别验证
正常录像、权限拒绝、权限设置恢复、配置/Session/写文件启动超时、快速前后台、锁屏、来电/系统
中断、媒体服务恢复、低存储和连续重试；每个机器阶段都必须在有限时间内成功或弹出一次可恢复
警告，不能永久停在“正在开启”。旧 request 超时后的迟到回调不得污染新 retry。

同一 attempt 即使 Delegate 提前结束且完成组随后 stop 也最多弹一个警告，新 retry 可再次提示。
用户明确停止且文件有效时正常保存；系统中断、后台或异常提前停止时，即使 success key 为 true，
有效文件也作为“部分录像证据”保留并明确提示，不能冒充完整成功。恢复旧 Session 的自动录像暂停
原因必须可见，手动成功 retry 后才清除。`.both` 左右分别录制后，两段均可独立播放并绑定对应 Effort。
Console 只含 attempt、阶段、error domain/code、success key 等诊断，不含路径、动作、重量或帧。
紧凑/完整取景均 fill 无上下黑边，横竖屏、镜像、旋转锁定与绿色相机指示仍按真实设备逐边对照；历史
有录像的训练行封面按取景比例裁切。Simulator 不作为成功录像证据。安装到设备只证明构建、签名与安装；
上述交互逐项完成前仍标记待验收。

记录、热量与完成验收：完成一个动作的一侧或一组并跳过其余 Effort 时，整次计划尚未结束也应
出现一条只含实际完成证据的动作训练记录；全跳过动作不建空记录，重复恢复/materialize 不产生
第二条。最后一个 Effort 后按“最后动作记录 → Session completed/finalized → 系统训练投影结束 →
本地分享预览”自动执行，不出现“保存并结束”；只有点击分享才打开系统分享。参考体重使用 Session
开始前最近有效值，计划执行热量等于来源动作记录之和。清空身体记录和参考体重后，训练仍能完成，
热量保持为空且计划页/分享页提供身体信息入口，不显示 `0 kcal`。从历史删除 Session 时清理来源
动作记录、Set/Effort、分析和私有录像；删除单条投影记录后 suppression 阻止其复活。

视频真机验收使用虚构素材：百炼 Qwen 直传一个约 7MB 内短视频，确认 Trace 的
`direct_video_count` 大于零；再用不支持直传的平台验证关键帧数量大于零；最后使用不可读
文件验证请求在本机失败，不产生伪装成视频分析的回复。

健身房媒体真机验收使用虚构照片：先发送两张健身房照片，等 Agent 询问名称后在下一轮只回复
场馆名，确认健身房详情保存两张照片；点击缩略图进入全屏查看，在浮层中切换并逐张移除，
确认封面顺延，聊天中的两张照片仍能打开。训练、饮食和身体记录各准备两项媒体，点击放大后
从浮层分别移除一项，并确认另一项、记录本身与聊天原件不变。

AI 配置引导与暂存在模拟器使用空标准档 Key 验收：准备文字和附件后点击发送，确认消息已落盘
并显示“已暂存”、输入区出现「1 条待处理」与“管理”入口，同时首次打开“设置 → LLM 配置”
并显示提醒；执行日志没有新增失败项。继续发送两条，确认三条都进入暂存且不再重复弹出配置页。
打开暂存管理，确认三条按发送顺序显示摘要、状态和附件数量；分别验证单删、清空确认与“按顺序
重试全部”。从管理页进入 LLM 配置应与设置 Tab 的平台、地址、Key 和模型一致。保存标准档 Key 后
返回教练，确认其余消息按发送顺序进入流式 Agent，不产生重复业务记录；设置中不出现远程 Agent
开关或本地模式提示。

崩溃诊断与录像原因真机验收：先在高级设置确认「自动发送崩溃诊断」开关状态，用「查看上次报告」
确认报告不含 API Key、Authorization 或媒体内容；人工触发一次诊断邮件，确认主题独立且附件为 `.txt`。
带练连续录制 3 组，并分别制造后台切换、来电中断与低存储，确认提示给出具体原因和技术标识，
诊断日志能查到对应阶段。BUG 0025 的根因结论以真机复验为准。

快捷按钮与饮食双卡片验收：新增一个按钮并只勾选饮食工具，发送一次饮食描述，确认执行日志的
「绑定工具」只包含所选工具；隐藏该按钮后确认聊天输入区不再出现它。在饮食第一张卡改一道菜的
热量并保存，确认第二张卡与「饮食记录」详情同步更新；清空某个宏量后确认显示「未估算」而不是 0。

LLM 配置在模拟器补充验收：在模型输入框手输一个不在 `/models` 列表中的 ID，返回设置首页再
进入，确认值不变且重新拉取候选也不覆盖；切换到小模型档确认平台、Base URL、Key、模型独立；
选择 `opencode` 确认 Base URL 预填 `https://opencode.ai/zen/v1` 且可改写。
