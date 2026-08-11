# Soma 验收清单

本清单以当前 SwiftUI、SwiftData 实现和可重复运行的验证命令为准。自然语言与媒体事实由
教练对话创建；训练计划可在专用 GUI 中确定性编排，带练可保存用户逐组确认的事实。其他列表
和详情用于审查、纠错与删除结构化结果。

## 产品闭环

| 要求 | 当前证据 |
| --- | --- |
| 无账户、本地私有 | `DataSpaceController` 使用两个关闭 CloudKit 的 SwiftData 容器；媒体位于 App 沙盒，API Key 位于 ThisDeviceOnly Keychain。 |
| 演示/个人数据一键切换 | 高级设置提供分段选择；两个容器隔离，低频入口不会占用聊天页或造成误触。 |
| 聊天、图片、视频、语音 | `CoachView` 统一接收文字和媒体；单条消息最多混合选择十项图片/视频，三项起使用主图在前的稳定画布，后续媒体在同一画布上缩小、旋转并从右侧露出，避免极端横竖比破坏聊天节奏；显式展开后保留各自比例并可收起，点击任一聊天媒体进入只读全屏查看，图片可缩放、多项可左右切换；视频按模型能力直传或关键帧降级并明示实际模式；`SpeechInputService` 使用系统语音识别；消息正文支持完整 Markdown、原生范围选择与复制，用户绿色气泡的选区在浅色和深色外观下都使用高对比系统前景色。`MarkdownAttributedStringBuilder` 从 `presentationIntent` 重建段落与列表断行，避免教练回复黏连。 |
| 对话 Session | `ConversationSessionController` 在根层首次加载和 Scene 重新进入前台时解析当前 Session；今天有最后消息则复用，否则新建当天 Session；旧消息按自然日归档，历史会话可回看。 |
| 发送反馈 | 提交被接受后清空草稿与附件、撤销文本焦点并滚到稳定底部锚点；用户消息和 Agent Event 更新继续保持在底部等待回复。 |
| Widget 与系统快捷入口 | 免费签名阶段 `SomaWidget` 仅提供中尺寸文字、拍照、照片/视频快速记录；三种锁屏快捷组件与 App Shortcuts 提供相同入口。均只深链进入既有录入路径，不读取训练状态、不在扩展内写记录或运行 Agent。情境化组件见暂缓的 PRD 017 与 ADR 0042。 |
| 异步对话处理 | 发送先原子保存 Turn、媒体、上下文与 `AgentJob`；App 根层 runner 串行领取，有限后台租约到期进入 `waitingForForeground`。有有效 step 检查点时回前台或重启复用同一条回复气泡从下一步续跑且不递增 `attemptNumber`；无检查点的中断标为失败并保留手动重试，重新进入 App 不会自动重跑失败任务。 |
| 多个健身房和当前场馆 | 聊天可创建、更新、切换；健身房列表可直接选择当前场馆。 |
| 健身房审查 | 详情展示全部上传照片、AI 环境总结和器械列表；健身房与器械支持编辑、删除。 |
| 饮食与身体记录 | 聊天或媒体生成本地记录；详情保留原始文字、食物/体型照片和 AI 说明。 |
| 训练与动作分析 | 训练动作使用稳定 ID；旧聚合与新逐组 Session 统一进入动作历史。包内动作内容保持静默，仅在用户形成动作后关联；列表展示动作图，详情展示多张动作图与程序化正背面肌群受力图。缺失字段保持空；动作示意图生成和视频复盘都只由用户主动触发，肌群图不再走 AI 生成。 |
| 动作快捷输入 | 输入框只在本地 active 标准名称中匹配；建议行一次给出「动作名 + 最近一次训练数据」，点一次写入完整草稿，没有历史时只写动作名。只修改草稿且仍由用户主动发送。 |
| 训练计划与带练 | 计划列表可直接新建，动作选择器显示示意图并支持多选搜索；处方默认折叠，可显式复用最近明确值并进入排序模式。GUI 与 Agent 共用 Program 和不可变模板版本。计划详情首屏只保留动作列表与开始训练，统计、版本历史与 AI 建议默认折叠，编辑/归档/删除收入工具栏菜单（删除保留训练历史），版本历史展示确定性变更摘要。带练以紧凑/放大双投影一键保存当前组，录制与跳过收入组操作菜单、教练提示按需展开、进度以“第 N/M 组”文字表达；休息按目标结束时间恢复，暂停、跳过、替换和异常退出保持可解释；录像失败以 toast 提示原因。复盘页可本机生成并分享训练海报。 |
| 自动录像 | Session 可关闭、每动作录一个目标工作组或每组都录；非自动目标组仍可手动录制。只有实际请求录像才启动相机，只有系统确认开始录像才展示取景器；使用前置摄像头、无麦克风，紧凑小窗采用填充裁切消除黑边，放大态保持完整画幅，预览与文件共享镜像/旋转；相机失败不阻断 Set 事实。 |
| CRUD | 训练、饮食、身体详情进入即编辑，修改后显示保存；次要区块（受力图、热量估算、AI 解析、原始记录、宏量营养）默认折叠但展开后仍可完整编辑；历史列表左滑红色图标删除。训练记录按自然日分组，筛选为「全部 + 按月」的扁平菜单并支持分页加载；记录通过 `exerciseID` 关联动作库，列表行只保留主指标与缩略图，打开历史时对仅有名称的旧记录做确定性回填。健身房和器械也可修改与删除。 |
| 统计 | 进展首屏收敛为紧凑“当前上下文”入口、最近记录、带“最近 7 天”摘要的连续性热力图、体重趋势和训练容量趋势。 |
| 时间粒度与拖动 | 体重和容量都支持周、双周、月、季，并允许横向拖动历史窗口。 |
| 身体信息 | 保存出生日期、生理性别、身高、参考体重、目标和备注；年龄动态计算，体态图通过身体记录历史回溯。 |
| 训练热量 | 使用本地 MET 公式；优先实际时长，无氧推算时长只用于热量且明确标记，不回填实际训练时长。 |
| 外部健康数据 | HealthKit 只读导入体重、训练和活动能量；转换为 Soma 模型，按空间/来源/数据流保存游标，使用样本 ID 去重并处理来源删除。 |
| 位置与天气上下文 | 位置只在用户开启后随发送获取一次；天气相关文本才向 Open-Meteo 发送小数点后两位的公里级坐标，只在内存中派生一般风险提示，失败不阻塞 Agent，关于页提供数据归属。 |
| 应用内反馈 | 设置的“关于”区进入 Soma 内置反馈页，一个输入区支持文字、照片和视频并直接发送，不跳转邮件 App；页面不出现 Base URL、Server、邮箱或 SMTP 说明。当前个人安装包通过 QQ SMTP 投递到固定 Gmail，只发送用户明确填写和选择的内容，不自动附带身体数据、聊天、Trace 或日志。客户端限制 5,000 字、10 项和 25 MB；外部分发前 `make online-check` 必须阻止客户端继续携带邮件凭据。 |
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
| 真正 ReAct | 可配置步数上限（默认 100，高级设置 `ReAct 步骤上限`）的流式“模型自然语言或原生 tool_calls—本地工具—role=tool”循环；规范化幂等签名与 pending/committed 账本去重，工具失败可回到下一轮修正；供应商可并行返回 tool_calls，本机仍顺序执行。每轮只暴露 13 个 Tool 中的 core + 按需 plans/gym/review/feedback，仅 `expand_tool_group` 可中途扩展；v1 合并别名只执行历史调用。普通过程折叠为状态摘要；饮食成功只显示一张可编辑结果卡。原始 JSON 只在开发者 Trace 中保留。 |
| Agent 纠错与删除 | 数据查询返回稳定记录 ID；训练、饮食和身体支持显式 update 工具原位纠错并合并新媒体；delete 工具仅接受用户当前消息的明确意图，且不级联删除聊天和共享媒体。 |
| 跨消息去重 | 同一现实事件的补图或纠错综合来源、时间、类型、文本、结构化数值、媒体和纠错语义确定性合并；歧义候选保持独立。 |
| 可继续 Session | 历史会话抽屉由教练页左边界右滑打开（导航栏不放常驻按钮，VoiceOver 提供等效操作）；可新建或选择旧 Session 继续发送，跨天不自动抢走当前选择。 |
| 输入区降噪 | 位置只在首次发送时确认一次，之后由设置修改；健身房少于两个时不显示场馆切换入口。 |
| 逐组训练 | 每项训练以有序 `set_entries` 保存单组次数和外部重量，组数取数组长度，容量逐组按完整事实求和；旧标量记录确定性展开。 |
| 视频输入证明 | 能力注册确认的百炼 Qwen 模型优先接收约 7MB 内的兼容 MP4，首请求不抽帧也不同时发送关键帧；其他模型使用明确关键帧模式。直传在首增量前失败才抽帧并消耗唯一重试，零帧且无直传视频时阻止请求。 |
| Session 上下文 | `AgentTurnContextEnvelope v2` 为本地/远程统一投影：不可覆盖的发送/尝试时间、约 6,000 token 内最多十个完整来回、短事实引用和更早 digest。当前 Turn 有媒体时只发送当前媒体；明确回指选最近一个，比较最多两个，其他历史只发文字。`query_user_data` 支持真实日期过滤、字段投影与分页。 |
| 双档模型 | 「LLM 配置」顶部是「标准模型 / 小模型」分段，两档共享同一套字段：平台、Base URL、API Key、模型同屏可见可改，标准档追加图片生成模型，小模型档追加启用开关，没有「高级」折叠层；两档保持独立配置且小模型可关闭；媒体、记录、纠错和安全敏感任务使用标准。 |
| AI 配置门禁 | 聊天不提供远程 Agent 开关或本地模式；标准档没有 API Key 时，发送与重试仍然原子落盘 Turn 与 Job 并进入 `staged`，不产生 Trace 或业务记录；首次未配置时同时打开「LLM 配置」并显示配置提醒。 |
| 回复文字选择 | Agent Markdown 回复使用系统可选择文本，支持长按选择与复制，并保留段落、列表和链接语义。 |
| 健身房媒体归档 | 本轮发图创建健身房会保存全部图片；下一轮要求创建或回答名称时，历史消息向模型提供 `recent_gym_turn` 语义引用，模型在 Tool Call 中选择后由 App 解析紧邻上一轮媒体位置，不暴露沙盒路径，也不读取更早或其他 Session 媒体。 |
| 媒体放大与单张解绑 | 聊天、健身房、训练、饮食和身体详情点击媒体进入统一全屏查看浮层；图片可缩放、多项可左右切换。聊天浮层只读，记录与健身房的删除入口只在浮层内；移除后封面与旧兼容字段同步更新，聊天原附件、其他记录引用和系统相册保持不变。 |
| 渐进式 Skills | 系统只披露目录；`load_skill` 按需加载八项可编辑 Skill，并生成独立 Span。 |
| 系统协议边界 | 角色和安全策略可编辑；工具与参数 Schema 由 App 通过 API 注册，不进入提示词且不能被旧自定义值覆盖。 |
| Trace | 一次远程消息生成一条成功或失败 Trace；model、skill、tool、output Span 作为 Event 实时更新 UI，并保存相对耗时、Token、入参与返回。 |
| 开发者设置 | 直接提供执行日志入口和数量；固定 Tool 协议不作为不可操作的设置项或说明展示。 |
| 持久 Job/Event | 每条消息拥有稳定 `AgentJob` 与单调语义 Event；Chat、Trace、通知和 Live Activity 维护独立 cursor，UI 读取不删除事件。 |
| 可选远程执行 | 设置默认关闭并披露数据流；单次可选仅本机。匿名设备签名、幂等 Job、Event 补拉、Worker lease 和设备 Tool handoff 由 `Server/` 提供，BYOK 不上传。 |
| 系统进度 | Live Activity 只显示通用阶段、操作数和队列数，不含健康文本或虚假百分比；完成通知和系统表面深链到稳定 Turn。 |

## 已实现：训练智能

以下是 [PRD 010](prd/010-exercise-library-plans-guided-training.md)、
[PRD 012](prd/012-gui-training-program-authoring.md) 与
[PRD 013](prd/013-guided-workout-experience-and-capture.md) 的当前实现证据。

| 要求 | 目标验收 |
| --- | --- |
| 动作身份 | `ExerciseDefinition`、`query_user_data(scope=exercises, query=...)`、`mutate_user_data` 与失效 ID 恢复错误；动作库必须搜索并分页，不再向模型返回完整全库。 |
| 动作历史 | 动作详情按 ID 合并 `WorkoutEntry` 与 Session/Set；合并记录迁移训练、模板、Performance/分析链和媒体，并只撤销本次引用。 |
| 静默动作内容 | `BundledExerciseCatalog` 提供 40+ 常见动作内容与授权/项目素材；空数据库不产生动作，已知动作创建后只 fill-only 激活自身内容，未使用目录条目不进入列表或 Tool。 |
| 动作图片 | 列表左侧加载紧凑动作示意图；详情首屏只读展示示意图、名称、折叠教练提示、紧凑单面肌群图与最近训练，编辑与媒体管理（用户上传、显式 AI 动作示意图生成、示范视频、外部链接）在工具栏菜单的子页。肌群图不再 AI 生成；既有 generated/user 肌群图仍可在媒体子页查看删除。generated/user 图片进入合并、备份、恢复、清除与媒体回收。 |
| 快捷输入 | `CoachView` 本地候选读取 active 名称；`ExerciseInputSuggestionBuilder` 合并旧记录与已完成 Set 的最新有效容量，一行给出动作名加最近一次训练，不请求网络、不写业务数据、不为缺失历史编造数值。 |
| 计划真值 | `TrainingProgram`、`WorkoutTemplateVersion`、`TemplateExercise`、Session、Performance、Set 和 Recommendation 分层；开始训练冻结快照。 |
| 计划 GUI 创建 | `TrainingProgramCreationView` 与版本编辑器共享处方草稿、动作图片选择器和最近容量解析器；只读取当前 active 动作，以稳定 ID 调用 `TrainingPlanStore` 创建版本 1，空字段保持 `nil`。 |
| 统计兼容 | `TrainingStatistics` 只合并旧聚合与新 completed actual Set，不把计划或建议计入容量。 |
| 带练 | `GuidedWorkoutCoordinator` 支持从进行中 Set 一步保存；可见倒计时组件按绝对截止时间自动进入本组，且相机启动不会阻塞状态呈现；`restTargetEndAt` 持久恢复休息，紧凑/放大 UI、暂停、跳过、替换、中断恢复和完成摘要都读取同一 Session 事实。 |
| 自动录像 | `WorkoutCameraService` 与 Session policy 决定单目标工作组或全部组；Coordinator 也允许当前组手动录像。`didStartRecordingTo` 是“录像已开始”的唯一事实，Set 保存自己的视频引用；紧凑取景使用 `.resizeAspectFill`，完整取景使用 `.resizeAspect`，二者与文件共享方向和镜像。未录像时不启动、不展示相机；前置相机、无音轨、中断/后台/热压力/磁盘错误均明确显示且不阻断训练。 |
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
| 教练降噪 | Agent Skill/Tool 过程默认折叠为一条状态摘要行；「本次仅本机」为长按发送键菜单；Composer 上下文条单层展示；空态一句引导加两个示例；重试为低权重按钮；历史会话仅左缘右滑进入（真机验收修订移除工具栏按钮）。 |
| 训练降噪 | 计划详情统计/版本/AI 折叠、管理入菜单；动作行可直达动作详情；「训练效果总览」由处方肌群与组数确定性聚合出双面受力图与总览文本（`TrainingPlanOverview` 单测）；带练执行录制与跳过入菜单、提示按需展开、进度文字化；准备页录像默认折叠、语音提示位于设置；处方编辑默认只暴露组数与次数；创建计划目标/提示折叠为可选。 |
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
| 补偿消费 | App 启动、回到前台、`llmConfigurationDidChange`、上一条任务结束与退避到期触发 `resumePendingJobs`；`releaseStagedJobs` 只解锁后端可用的 Job，按 FIFO 串行执行，`AgentMutationReceipt` 保证同一 Turn 不重复写入（`testReleaseStagedJobsRespectsReadinessAndClearsBackoff`）。 |
| 暂存可解释 | 暂存中的用户消息显示「已暂存，恢复后自动继续」，输入区上方显示「N 条已暂存 · 去配置」并深链到「LLM 配置」；不展示状态机名称、退避秒数或内部分类结果。 |
| LLM 配置直出 | 「AI 服务」更名「LLM 配置」；顶部档位分段，平台/Base URL/API Key/模型同屏可改；模型、Base URL 与图片生成模型改动即落盘，不依赖返回时机，返回设置首页再进入值不变。 |
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
| 聚合查询 | `query_user_data` 接受 `date_from`/`date_to`/`group_by`/`metric`，由 `AgentUserDataAggregator` 本地聚合。 |
| 跨轮事实 | `AgentCrossTurnFactSummary` 注入近期 mutation 摘要与十轮外 digest；`AgentJobStore.events` 带谓词拉取。 |
| 规范化幂等 | `AgentToolCallSignature` 归一 trim/同义字段/数值/nil；`set_entries` 保序；失败 receipt 可重试（`AgentReliabilityTests`）。 |
| 业务级疑似重复 | 同日同动作同组指纹命中返回既有 ID +「疑似重复」，不静默合并（`AgentBusinessKeyDeduper`）。 |
| 同气泡续跑 | Job 持久化 `lastCompletedStep`/`loopCheckpoint`；有检查点时复用 `responseMessageID` 且不递增 `attemptNumber`；`DataIntegrityRepair` 不把可恢复中断标为 failed。 |
| 工具组与并行 | `AgentToolExposurePolicy` 预选 core/plans/gym/review/feedback；`parallelToolCalls=true` 且本机顺序执行；未展开时同 session 连续两轮 system+tools 前缀稳定。 |
| 延迟辅助 | 流式滚动约 10Hz 非动画节流；历史视频帧经 `VideoFrameCache` LRU；step ≥ 2 历史帧占位。Trace 可观测 `time_to_first_delta_ms`/`projection_ms`/`cached_prompt_tokens`。 |
| 红线不破坏 | 不用 LLM 滚动摘要；不静默跨轮合并；Tool Schema 仍固定；远程 Job 协议不变。 |

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

教练页手工验收：从左边界右滑打开会话抽屉，新建两个非空 Session 后来回切换并继续发送；
首次发送分别验证允许和拒绝位置都只出现一次确认；准备 0、1、2 个健身房验证只有两馆时
显示切换入口；长按用户绿色气泡并拖动选区，分别在浅色、深色外观确认选区与气泡明显区分，
且复制菜单仍可用；长按 Agent 的列表、链接和多段回复验证可精确选择复制。分别点击聊天中的
单张、双张和三张以上折叠媒体，确认进入全屏、可切换与缩放，且没有删除聊天附件的入口。
准备四个以上虚构动作并查询两条虚构训练，确认过程默认只显示一条状态摘要行；点开后 Tool
卡片先显示结果数量或简短结论，展开逐项完整显示动作/训练信息但不出现 UUID、JSON、
`function` 或 `tool_call` 内部标记，收起后恢复紧凑高度。原始参数与 ID 应继续能在
“高级设置 → 执行日志”中审查。

训练计划 GUI 验收：在“进展 → 训练计划”从右上角加号进入新建页（空态文案指向加号）；
动作库为空时确认保存不可用且有引导。准备两个虚构动作后在图片列表中多选，填写部分处方、保留另一部分
空白；显式点击“使用上次”只复用最近明确值。进入排序模式拖动换序并删除/重新添加，保存后
确认列表出现计划且空字段没有被补齐。再次编辑产生新版本，确认已开始 Session 的旧快照不变。

计划带练真机验收：在准备页展开“录像”后分别选择“关闭”“每个动作录一组”“每一组都录”。
关闭时进入每一组均不请求相机权限、不显示取景器，但组操作菜单中的“录制本组”可启动录像；单组模式在首组热身与非热身计划中
只录第 2/1 组；全部组模式逐组产生独立录像。每次都确认倒计时 `3、2、1`、开始第 N 组、完成
休息、下一组和训练完成有顺序正确且不重复的中文语音。相机准备期间训练事实已经进入执行态；
只有出现系统录制回调后才出现红点和取景器，失败必须显示具体错误。紧凑小窗不得有上下黑边，
点击后立即进入完整取景；连续收起、再次放大不得黑屏或重启当前文件。竖屏放大把标题、组进度、
提示和完成按钮固定到底部安全区，标题显示为“动作名（重量、次数）”，取景器使用其上方全部
剩余空间。带练页可横竖切换，分别
录制一段并逐边比较预览
与保存视频的画幅、方向和镜像；录制中旋转手机，当前片段保持锁定，停止后下一段重新适配。
完成一组只点击一次并立即进入休息；锁屏后确认 Live Activity/本地通知倒计时正确，点击返回
当前 Session。完成计划后必须看到时长、完成/跳过组、录像数和分动作结果；回到训练历史后从
右向左滑动记录可删除 Session、逐组事实、分析和私有录像。前后台、暂停、来电中断、权限拒绝
和低存储场景不得把未完成组记为完成。

视频真机验收使用虚构素材：百炼 Qwen 直传一个约 7MB 内短视频，确认 Trace 的
`direct_video_count` 大于零；再用不支持直传的平台验证关键帧数量大于零；最后使用不可读
文件验证请求在本机失败，不产生伪装成视频分析的回复。

健身房媒体真机验收使用虚构照片：先发送两张健身房照片，等 Agent 询问名称后在下一轮只回复
场馆名，确认健身房详情保存两张照片；点击缩略图进入全屏查看，在浮层中切换并逐张移除，
确认封面顺延，聊天中的两张照片仍能打开。训练、饮食和身体记录各准备两项媒体，点击放大后
从浮层分别移除一项，并确认另一项、记录本身与聊天原件不变。

AI 配置引导与暂存在模拟器使用空标准档 Key 验收：准备文字和附件后点击发送，确认消息已落盘
并显示“已暂存”、输入区出现「1 条已暂存 · 去配置」，同时打开“设置 → LLM 配置”并显示提醒；
执行日志没有新增失败项。继续发送两条，确认三条都进入暂存且不再重复弹出配置页。保存标准档
Key 后返回教练，确认三条按发送顺序自动进入流式 Agent、不需要手动重试、不产生重复业务记录；
设置中不出现远程 Agent 开关或本地模式提示。

LLM 配置在模拟器补充验收：在模型输入框手输一个不在 `/models` 列表中的 ID，返回设置首页再
进入，确认值不变且重新拉取候选也不覆盖；切换到小模型档确认平台、Base URL、Key、模型独立；
选择 `opencode` 确认 Base URL 预填 `https://opencode.ai/zen/v1` 且可改写。
