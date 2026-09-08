# Soma 验收清单

- 后续修订：[ADR 0119](adr/0119-full-video-and-append-only-dictation.md)（完整视频输入，禁止关键帧降级）
- 后续修订：[PRD 057](prd/057-coach-focus-progress-rings-and-library-clarity.md)（快捷聚焦、实时听写预览、营养圆环与动作类型）
- 后续修订：[PRD 058](prd/058-feedback-duration-and-editable-calories.md)（反馈失败分类、时长时分秒、可编辑训练热量）
- 后续修订：[ADR 0125](adr/0125-eager-loaded-coach-messages.md)（已加载聊天页即时排版与常驻缓存）
- 后续修订：[PRD 059](prd/059-coach-ids-progress-and-required-zeros.md)（教练 Int64 ID、训练卡 0、进展列表热量与缓存）
- 后续修订：[ADR 0126](adr/0126-workout-share-pro-max-canvas.md)（训练分享固定 Pro Max 纸面）
- 后续修订：[ADR 0127](adr/0127-agent-workout-weight-and-rest-zero.md)（Agent 训练重量与间歇未说明时写 0）
- 后续修订：[PRD 060](prd/060-remove-healthkit-until-redesign.md)（撤回 Apple 健康接入）
- 后续修订：[ADR 0128](adr/0128-remove-healthkit-until-redesign.md)（当前不接入 HealthKit）

- 上游依据：
  - [ADR 0000：压缩起点](adr/0000-origin-through-0.0.11.md) 收口的安装基线、性能预算与缓存失效规则
  - [ADR 0100：有界快照、连续流式文本与查询优先的数据访问](archive/0.0.14/adr/0100-bounded-snapshots-continuous-stream-rendering-and-query-first-data-access.md)
  - [ADR 0101：记录真值与 Agent 身体资料上下文](archive/0.0.15/adr/0101-record-truth-and-agent-profile-context.md)
  - [ADR 0102：原始训练生成计划时物化已完成执行](archive/0.0.15/adr/0102-source-workout-plan-execution-materialization.md)
  - [ADR 0103：目标导向的能量与增肌进展快照](archive/0.0.15/adr/0103-goal-directed-progress-energy-and-hypertrophy.md)
  - [ADR 0104：文字、图片与视频 ReAct 超时独立配置](archive/0.0.15/adr/0104-independent-react-timeouts-by-media.md)
  - [ADR 0106：可审查派生记录与人工中断屏障](archive/0.0.17/adr/0106-reviewable-derived-records-and-manual-interruption.md)
  - [ADR 0107：前台恢复与进展证据投影](archive/0.0.18/adr/0107-foreground-recovery-and-progress-evidence-projection.md)
  - [ADR 0108：跟随式进展披露与可审查饮食顺序](archive/0.0.18/adr/0108-contextual-progress-disclosure-and-reviewable-meal-order.md)
  - [ADR 0109：Schema 驱动的 Tool 参数恢复](archive/0.0.19/adr/0109-schema-guided-tool-argument-recovery.md)

本清单以当前 SwiftUI、SwiftData 实现和可重复运行的验证命令为准。自然语言与媒体事实由
教练对话创建；训练计划可在专用 GUI 中确定性编排，带练可保存用户逐组确认的事实。其他列表
和详情用于审查、纠错与删除结构化结果。

## 产品闭环

| 要求 | 当前证据 |
| --- | --- |
| 无账户、本地私有 | `DataSpaceController` 使用两个关闭 CloudKit 的 SwiftData 容器；媒体位于 App 沙盒，API Key 位于 ThisDeviceOnly Keychain。 |
| 演示/个人数据一键切换 | 高级设置提供分段选择；两个容器隔离，低频入口不会占用聊天页或造成误触。 |
| 启动数据迁移 | App 根层先显示迁移门禁，按个人空间、演示空间顺序用当前 `SomaDataSchema` 打开容器（不带历史 VersionedSchema 计划）。每个空间先按 key 与 schema version 7 定向检查当前 marker；命中后立即返回，不扫描业务表。未完成时除既有关系/ID/处方修复外，统一把全部 Session 改为业务时区日期标题，并幂等回填证据和历史体重充分的训练热量。失败保持可重试错误态，不允许在半迁移容器上继续读写；脱敏诊断不含身体测量、饮食原文、聊天正文与媒体文件。 |
| 聊天、图片、视频、语音 | 统一媒体输入与只读全屏查看；视频只发送完整文件，失败不改成关键帧。当前视频自动播放，切页/后台暂停，失败可重试。听写把未确认片段实时预览在输入框，只有确认片段写入草稿；停止发送前排空尾句，不缓存草稿基线或累计历史文字；用户中途改字丢弃当前猜测。iOS 26 支持时使用新本地模型，旧系统严格本地，停顿补标点，旧回调不能覆盖编辑。 |
| 对话 Session | `ConversationSessionController` 在根层首次加载时解析当前 Session；回前台保持正在看的 Session、滚动和草稿，跨日发送前再由确定性门禁解析业务 Session。默认标题按 `startedAt` 与业务时区固定为 `MM月dd日 - 周X`，不调用模型，允许同名；升级统一重命名，之后仍可手动改名并恢复日期标题，且不改变 `updatedAt`。历史抽屉支持选择、重命名和左滑删除聊天图；业务记录不随会话删除，在途 Job 拒绝删除。 |
| 发送反馈 | 提交被接受后清空草稿与附件、撤销文本焦点并启用 tail-follow；以最后一条真实消息尾部为目标，等待内容 revision 与布局完成。短内容保持贴顶，禁止通过零高度锚点滚入空白；用户主动上滑后暂停，发送新消息或双击教练再恢复。 |
| Widget 与系统快捷入口 | `SomaWidget`、锁屏组件与可用系统版本的 App Shortcut 统一打开 `soma://capture/<mode>`，不在扩展内写记录或运行 Agent。根层单一状态机等待 active Scene 后用一个顶层全屏相机展示；重复请求幂等，取消/失败/锁屏结束事务且恢复不自动重开，成功媒体只交付一次。权限拒绝或无相机提供取消、设置或选择照片。 |
| 异步对话处理 | 发送在同一事务保存用户 Turn、媒体、上下文、`AgentJob`、预绑定响应消息和 `jobQueued` Event；用户在模型首 token 前以统一过程卡看到“已收到”，模型请求开始后原位变为“正在处理请求”。临时状态只存 Activity Item，不写入 `CoachMessage.text`。FIFO/网络/配置/设备等待原位显示原因。Runner、失败、重启恢复和人工重试始终复用同一响应；重试先清除旧失败但保留成功步骤。Loop 内只有三次 1/2/4 秒退避；可见失败进入人工屏障，启动、前台、网络、配置和计时器不得自动重跑。 |
| 多个健身房和当前场馆 | 聊天可创建、更新、切换；健身房列表可直接选择当前场馆。 |
| 健身房审查 | 详情展示全部上传照片、AI 环境总结和器械列表；健身房与器械支持编辑、删除。 |
| 饮食与身体记录 | 聊天或媒体生成本地记录；饮食详情食物项与聊天菜品行共用同一套稳定可编辑行，分隔线不创建空行。整餐热量与宏量始终由菜品派生：字段完整时显示精确总计，部分菜品有值时显示 `≥ 已知小计`，全部未知显示破折号。只修改相同单位的正数份数时按比例缩放当前已有营养；直接修改其他字段互不联动。总糖不再保存；证据足够时整餐可保存「较慢／中等／较快」的组成升糖速度及成对依据，明确实际反应因人而异，不输出血糖峰值或诊断。详细评价超过实际五行才显示展开/收起。详情保留原始文字、食物/体型照片和 AI 说明。 |
| 训练与动作分析 | 训练动作使用稳定 ID；Tool Schema v4 在动作搜索/新建/更新及训练新建/更新中显式传递 `target_kind`、`laterality`、逻辑组、effort 侧别与逐组间歇。左右各做必须形成同一逻辑组的 left/right evidence；本次显式 evidence 优先于动作库 fallback。旧聚合与新逐组 Session 统一进入动作历史；缺失字段保持空，动作图与视频复盘仍只由用户主动触发。 |
| 动作快捷输入 | 输入框只在本地 active 标准名称中匹配；建议行给出「动作名 + 最近一次训练数据」，相邻次数、重量、间歇和侧别一致的组压缩为 `50kg 5×5组 间歇60s`，异构组仅按连续同值分段且不改变底层 evidence。点按只修改草稿，仍由用户主动发送。 |
| 训练计划与带练 | 计划详情依次展示可编辑概览、确定性训练效果和动作列表；侧别与按次数/按时长保存在动作定义，两类计划间歇在动作设定统一编辑，独立组只编辑次数或时长、重量、类型与备注。聊天动作卡读取动作定义的目标单位和侧别，不允许旧记录形成第二套配置源；聊天密度使用动作头与标签，数据行按“完成值 · 重量”呈现、连续同值组右侧 `×N`；各组都相同时组间歇与完成值同一行，组有差别时在组块中间，换侧间歇在左右记录中间；不加 A/B/C 前缀或重复大卡层。点击开始只选择一次三种录像策略即进入首个动作；计时与休息自动推进，进度按动作/逻辑组分段，语音播报组数与次数/秒数。动作记录先于 Session 自动完成，最后进入本地分享预览。教练基于当日原始训练生成计划时，同时组装一次已完成 Session，删除 Session 不删除原始记录。 |
| 自动录像 | Session 可关闭、每动作首个工作组或每组自动录制；主界面始终保留主动录像。倒计时只取景，开组进入 `.setInProgress` 并等预览宿主后再 `startRecording`。每次请求拥有 attempt 单终态并绑定 Effort，成功 key 为 true 的有效文件必须保留；提前结束和重复 stop 不产生第二个 Alert。相机失败暂停自动策略但不阻断训练；失败提示给出具体原因与技术标识，`startingRecording` 与录像进行中不改写视频连接、不重建 RotationCoordinator。紧凑与放大预览、历史缩略均 fill。真实 Delegate、系统中断和左右独立片段仍需真机证据。 |
| CRUD | 训练、饮食、身体详情进入即编辑；聊天内可编辑卡以 550 ms 防抖自动保存，保存中显示旋转进度，成功勾选由灰变亮并给出触觉确认，失败保持可见。训练详情受力图默认直接展开且可全屏放大；热量估算、AI 解析、原始记录与宏量营养保持折叠但展开后仍可完整编辑。训练记录逐组默认只编辑动作定义下的次数或时长与重量，不展示逻辑组或完成方式选择器。历史列表左滑红色图标删除。训练与饮食记录按自然日分组、常驻导航标题下「全部 + 按月」透明芯片筛选、按天可折叠，并支持分页加载；记录通过 `exerciseID` 关联动作库，列表行只保留主指标与取景比例缩略图，打开历史时对仅有名称的旧记录做确定性回填。健身房和器械也可修改与删除。 |
| 统计 | 按 PRD 053/054/057 提供日／周／月／年与任意历史日；未来导航置灰。饮食与能量为主图，训练、身体为摘要与详情入口。日页用四枚独立环：上中热量、下排蛋白质／碳水／脂肪；顶部事实卡写摄入与消耗，热量环心写已摄入／推荐摄入 kcal，不写还可摄入或完成百分比；热量环不重复标题，宏量用红橙紫图标与数字同行，点按热量环打开摄入明细、点按宏量环打开该营养素克数明细；不足与超量只靠进度和颜色，当日未达推荐时底部再显示仍可摄入且不可点开。周、月、年只保留日均摄入／消耗和图表，不展示营养环，点图不切换周期。摄入柱与全天预估消耗虚线共用 kcal 轴，年均值按有效天数加权。估算依据进入详情，静息不当作总消耗。 |
| 底部 Tab | 教练、训练、进展、设置四个 Tab 各自保留导航栈；换 Tab 不 pop。教练单次再选 no-op，只有系统双击教练回到最后 AI 消息尾部；训练、进展、设置仅在详情页再点回根。首次进入、切换 Session 和从其他 Tab 返回都在布局完成后定位最后 AI 尾部，短内容贴顶。 |
| 时间粒度与拖动 | 体重和容量都支持周、双周、月、季，并允许横向拖动历史窗口。 |
| 身体信息 | 保存可选出生日期、生理性别、身高、目标和备注；称呼与出生日期直接位于基本信息，不使用“更多（可选）”或“填写出生日期”开关，未选择日期保持 `nil`。年龄动态计算，体重只读取体重记录的最新有效值，体态图通过身体记录历史回溯。昵称、性别、年龄、身高、最新体重、目标和限制进入有界 Agent 上下文。 |
| 训练热量 | 普通训练与带练共用本地 MET 计算器；真实总时长优先，否则使用逐 effort 实际时长或每次约 4 秒并加明确记录的间歇，保存推算标记。体重只取训练发生前最近有效 BodyEntry；创建、更新、聊天卡编辑和带练投影都重算，启动迁移幂等回填证据充分的历史记录。缺体重/证据保持 `nil`，不写 `0 kcal`。聊天卡与详情的预计消耗可编辑；详情改热量后出现保存；清空后按公式重算。详情仍展示 MET、时长、推算状态或缺失事实。逐组时长按秒存储，界面用时分秒省略零单位。 |
| 外部健康数据 | 当前不接入 HealthKit。体重与训练只来自 Soma 记录；已存在的导入记录当普通记录保留。进展估算用 Mifflin 静息 × 个人活动系数或默认 1.4，不读设备能量。 |
| 位置与天气上下文 | 位置只在用户开启后随发送获取一次；天气相关文本才向 Open-Meteo 发送小数点后两位的公里级坐标，只在内存中派生一般风险提示，失败不阻塞 Agent，关于页提供数据归属。 |
| 应用内反馈 | 设置底部继续提供通用反馈；每条已完成 AI 回复的时间、执行记录和 `text.bubble` 反馈入口放在同一紧凑操作行，两个图标分别贴近相邻触达区边缘，并在当前消息下方原位展开支持文字、照片、视频和 1–5 星评分的紧凑 `FeedbackView`，布局完成后自动平滑滚到当前编辑器底部，不创建页面或 Sheet，手动收起也不强制滚动。逐回复反馈投递成功先打钩再渐进收起，失败保持展开并保留文字、评分和附件；设置页通用反馈同样先打钩再淡出。失败区分未配置、授权失效和网络拦截（含蜂窝 SMTP 提示）。编辑器不显示上下文提示；逐回复反馈只在用户主动发送时附带当前 Turn 的可见问答和脱敏 Job/Trace 摘要，不附原消息媒体、位置、Key、原始模型上下文、完整日志或其他会话。页面不出现 Base URL、Server、邮箱或 SMTP；客户端限制 5,000 字、10 项和 25 MB，外部分发前 `make online-check` 继续阻止客户端凭据。 |
| 聊天提交反馈 | 用户当前消息明确要求提交 Soma 产品反馈时，Agent 调用无参数 `submit_feedback`，只发送当前消息原文和当前附件；普通训练/饮食/身体反馈不触发。Tool 等待实际 SMTP 结果，失败不伪装成功；远程模式进入设备 Tool handoff，不上传 QQ 凭据。 |
| 数据导出 | 用户选择目标文件夹后，饮食和训练按本地年/月/日生成文字、结构化 JSON 与有序媒体目录；不包含演示数据、API Key 或内部 Trace。 |
| 备份与恢复 | 首次选择外部目录并设置密码后立即备份，进入后台时尽力自动更新；完整个人空间与媒体经认证加密，错误密码或损坏快照不会改变当前数据。 |
| 主动清除 | 二次确认后删除个人空间和未共享沙盒媒体，保留演示数据、API Key、系统相册及外部备份，并断开自动备份。 |

## 性能预算与回归

性能结论与证据分级见[全 App 性能审计报告](engineering/performance-audit-2026-08-24.md)，长期边界见
[ADR 0000](adr/0000-origin-through-0.0.11.md)。Debug Simulator
只用于功能回归与发现热点，不作为 120 Hz 达标证明。

| 要求 | 当前证据与验收边界 |
| --- | --- |
| 启动与 Tab | 四个 Tab 保留独立导航栈；Root 不订阅全量 Job，深链按稳定 ID 定向读取。普通点击只写一次 selection，禁止全局关闭 UIKit 动画或替换系统 Tab bar。启动、Root 可见、Tab 点击与内容可见使用隐私安全 signpost。warm 常用交互 Release 真机 p95 必须 `<100 ms`，冷页面首个有效内容 p95 必须 `<200 ms`。 |
| 查询与派生 | 根页面不得无界订阅与首屏无关的历史；详情按 ID，列表带谓词、时间窗、上限和稳定分页。前台恢复由 generation 协调器在一次真实显示帧后启动；先取消未完成自动备份，Job 候选在独立读取上下文只返回 FIFO 稳定 ID，MainActor 重新 fetch，远程网络不占首交互区间。Scene 变化取消旧 generation；不得重选 Session、重置草稿/滚动或扫描无界历史。signpost 分开记录 scene、首帧、可交互、缓存、备份、远程撤销、Job 和滚动布局。 |
| 图片与媒体 | 图片读取、ImageIO 下采样与尺寸探测不进入 View 渲染路径；缩略图缓存成本上限 48 MB，并在内存警告、数据空间切换和文件指纹变化时失效。相同内容通过独立逻辑路径的硬链接复用，孤儿清理以个人/演示引用并集为准。 |
| Agent 与长列表 | 根投影只观察非终态 Job 或 cursor 落后的 Event；Coach 每个 Session 倒序查询最近 30 条、到顶追加 30 条并保持视觉锚点。短内容贴顶，长内容以最后 AI 尾部跟随；用户上滑后不抢位置。可见消息进入 64 项有界纯渲染缓存；内存警告后只保留当前 Session 最多 10 条、总成本不超过 2 MB 的不可变 DTO，不缓存 SwiftData 对象或业务事实。流式 revision 只更新实时回复叶子，完成态 Markdown 后台准备；10,000 消息、5,000 训练记录和 1,000 媒体引用的虚构压力夹具必须通过。 |
| 卡帧与内存 | Release 真机连续滚动 hitch `<1%`，无 `>100 ms` 主线程停顿，重复 `body` 热点 `<1 ms`；连续十轮跨 Tab、媒体和聊天操作不得单调增长。必须保存至少 30 次关键交互样本，模拟器数据不能代替。 |
| 自动化与交互 | 提交前运行 `make format`、`make check`、`make verify`；模拟器覆盖四 Tab、详情、键盘、滚动、安全区、浅深主题和 Dynamic Type。最终在 iPhone 17 Pro Max 签名安装、启动并完成人工手感验收。 |

## Agent 闭环

| 要求 | 当前证据 |
| --- | --- |
| 六个平台 | OpenAI、DeepSeek、阿里云百炼、火山引擎、腾讯云和 opencode 均可配置 Base URL、API Key 与模型；Base URL 对所有平台可改写，按平台与档位独立保存。 |
| 动态模型 | 模型是纯文本输入框；保存 API Key 后调用当前平台 `/models`，过滤不可用状态，以输入历史式建议列表出现在输入框下方，可点选也可手输。候选行只显示模型 ID，不截断列表，超过五条时列表内部滚动。刷新候选不覆盖已填写的模型，只在为空时补一个默认值。 |
| 多模态提示位置 | 能力说明只在模型已填写后出现；支持、不支持必须同时显示平台模型目录中的明确字段来源。平台没有提供能力元数据时显示“未知”，模型名、平台名和 `vision` / `vl` 字样均不得作为证据。 |
| 多模态提醒 | 本地未知能力允许尝试完整视频；明确不支持时阻断。远程完整视频需要部署显式能力开关。失败展示可恢复原因，禁止自动关键帧分析。 |
| 真正 ReAct | 可配置步数上限（默认 100）和文字/图片/视频独立运行超时（默认 3/5/10 分钟，各自可设 3–60 分钟）的流式“模型自然语言或原生 tool_calls—本地工具—role=tool”循环；两项在高级设置 `ReAct 循环` 同区呈现。规范化幂等签名与 pending/committed 账本去重，工具失败可回到下一轮修正；供应商可并行返回 tool_calls，本机仍顺序执行。Tool/Skill 以原生 `toolCallID` 作为 operation 身份，从 preparing、running、waitingForDevice 到 completed/failed/cancelled 只更新同一卡；本地、Server、重连与设备执行等价，参数校验失败也先出现准备态，生产环境不以 sleep 延长阶段。当前 32 个单一职责 Tool：未选快捷按钮注册全部，选中快捷按钮只注册该按钮工具白名单。已知 Tool 的无单位数字字符串和简单分数按注册 Schema 安全归一化；仍不合法的参数以 `invalid_tool_arguments` 和原 `tool_call_id` 返回模型自纠。未知名称解码失败。过长 Tool 结果可展开；原位审查卡与 Event Cards 同时保留。原始 JSON 只在开发者 Trace 中保留。 |
| Agent 纠错与删除 | 数据查询返回稳定记录 ID；训练、饮食和身体支持显式 update 工具原位纠错并合并新媒体；delete 工具仅接受用户当前消息的明确意图，且不级联删除聊天和共享媒体。create 每次新增，不能用创建代替更新。 |
| 跨消息去重 | 相同 Tool Call 由回执幂等；跨 Turn 训练/身体业务键返回疑似重复、不静默改写。纠正必须绑定查询得到的记录 ID。歧义时保持独立记录。 |
| 可继续 Session | 教练页左上角时间按钮、左边界右滑与 VoiceOver 操作打开同一个历史会话抽屉；可新建或选择旧 Session 继续发送，跨天不自动抢走当前选择。 |
| 输入区降噪 | 位置只在首次发送时确认一次，之后由设置修改；健身房少于两个时不显示场馆切换入口。 |
| 逐组训练 | 每项训练以有序 `set_entries` 保存单组次数和外部重量，组数取数组长度，容量逐组按完整事实求和；旧标量记录确定性展开。 |
| 视频输入证明 | 完整 MP4 及历史明确引用视频进入原始消息位置；压缩保留全时长，失败阻断。三次内部重试保持同一完整视频，无 fps 抽样提示，不产生替代图片。 |
| Session 上下文 | `AgentTurnContextEnvelope v3` 冻结原始 Turn 时间、Session businessDate、时区和 `defaultOccurredAt`，只向模型提供一个带 UTC offset、IANA 时区与自然语言时段的权威本地时间；UTC 机器字段不得先于它。重试保留原 Turn 时间，Loop 时间另行标识。其余身体、健身房、业务日、历史摘要与媒体选择继续遵守条件注入和有界窗口。 |
| 双档模型 | 「LLM 配置」顶部是「标准模型 / 小模型」分段，两档共享同一套字段：平台、Base URL、API Key、模型同屏可见可改，标准档追加图片生成模型，小模型档追加启用开关，没有「高级」折叠层；两档保持独立配置且小模型可关闭；媒体、记录、纠错和安全敏感任务使用标准。 |
| AI 配置门禁 | 聊天不提供远程 Agent 开关或本地模式；标准档没有 API Key 时，发送仍然原子落盘 Turn 与 Job 并进入 `staged`，不产生 Trace 或业务记录；首次未配置时同时打开「LLM 配置」并显示配置提醒。保存配置不自动释放，用户从原消息或暂存管理明确重试后才执行。 |
| 回复文字选择 | Agent Markdown 回复使用系统可选择文本，支持长按选择与复制，并保留段落、列表和链接语义。 |
| 健身房媒体归档 | 本轮发图创建健身房会保存全部图片；下一轮要求创建或回答名称时，历史消息向模型提供 `recent_gym_turn` 语义引用，模型在 Tool Call 中选择后由 App 解析紧邻上一轮媒体位置，不暴露沙盒路径，也不读取更早或其他 Session 媒体。 |
| 媒体放大与单张解绑 | 聊天、健身房、训练、饮食和身体详情点击媒体进入统一全屏查看浮层；iOS 18+ 从缩略图 zoom，iOS 17 关闭系统弹出动画避免先黑后图。图片可缩放、多项可左右切换。聊天浮层只读，记录与健身房的删除入口只在浮层内；移除后封面与旧兼容字段同步更新，聊天原附件、其他记录引用和系统相册保持不变。 |
| 渐进式 Skills | 未选快捷按钮时，System 只披露 `name/description/when_to_use`，`load_skill` 可按需加载。选中快捷按钮且绑定 Skill 时，首轮直接注入该 Skill 全文与收口上下文，System 省略能力目录和其他 Skill 元数据，信封只带这一份 Skill，默认不再暴露 `load_skill`。固定身份与安全契约始终保留。内置 override、自定义 Skill 与 Markdown 预览可管理，Skill 不再声明工具权限。 |
| 输入框快捷按钮 | 快捷按钮可新增、改名、换图标、换绑 Skill、删除、拖动排序并单独控制显示；每个按钮持有工具白名单，默认全选、可按分组删减，也可由小模型推荐清单与理由后一键采纳。默认可见「记录饮食」「训练记录」「近期分析」三个，聊天最多显示六个。点选且输入框为空时，「近期分析」填入建议句；「记录饮食」和「训练记录」不预填。已有文字不覆盖。未知工具名在保存与运行时都被丢弃。 |
| 系统协议边界 | 固定身份、安全、真实性和授权契约不可编辑，仅人格可编辑；工具与严格参数 Schema 由 App 通过 API 注册，不进入 System Prompt；Skill 只描述方法，快捷按钮只能在当前协议内收窄权限。 |
| Trace | 一次远程消息生成一条成功或失败 Trace；model、skill、tool、output Span 作为 Event 实时更新 UI，并保存相对耗时、Token、入参与返回。 |
| 开发者设置 | 直接提供执行日志入口和数量；固定 Tool 协议不作为不可操作的设置项或说明展示。 |
| 持久 Job/Event | 每条消息拥有稳定 `AgentJob` 与单调语义 Event；Chat、Trace、通知和 Live Activity 维护独立 cursor，UI 读取不删除事件。 |
| 可选远程执行 | 设置默认关闭并披露数据流；单次可选仅本机。匿名设备签名、幂等 Job、Event 补拉、Worker lease 和设备 Tool handoff 由 `Server/` 提供，BYOK 不上传。 |
| Backend 输入等价 | iOS 用 `AgentModelInputEnvelope v2` 组装 system/history/current 消息、媒体 ID、Skill 快照、选中快捷按钮与 Skill、仅当轮有效的 Tool 定义、步数与时限；本机直接消费，远端只绑定临时 upload。Server 不含第二套 Agent Prompt；当前暴露的 runtime Skill 可就地执行，并行设备 Tool 全部持久化且结果齐备后按原调用顺序续跑。 |
| 系统进度 | Live Activity 只显示通用阶段、操作数和队列数，不含健康文本或虚假百分比；完成通知和系统表面深链到稳定 Turn。 |

## 已实现：训练智能

以下是 [PRD 010](archive/0.0.1/prd/010-exercise-library-plans-guided-training.md)、
[PRD 012](archive/0.0.1/prd/012-gui-training-program-authoring.md) 与
[PRD 013](archive/0.0.1/prd/013-guided-workout-experience-and-capture.md) 的当前实现证据。

| 要求 | 目标验收 |
| --- | --- |
| 动作身份 | `ExerciseDefinition.businessID: Int64`、必需 SwiftData Relationship、`search_exercises` 和独立 create/update/archive/merge Tool；`create_exercise` 一次接收多个标准名，`create_workout` 一次接收多条已绑定动作 ID 的记录，新建记录 ID 由本机分配。旧 UUID 数据在启动迁移中按规范名回填，空名称进入明确待确认动作。 |
| 动作历史 | 动作详情按 ID 展示 `WorkoutEntry`；带练终态 Performance 先按来源 ID 物化为记录，旧 Session 尚未物化时才回退到 Session/Set，不能重复显示。计划入口先显示本计划目标；最近一次、容量趋势和全部记录分层，异构组忽略间歇压缩且不显示组号，图表使用真实日期与训练橙，最近容量及较上次变化可直接读取。合并记录迁移训练、模板、Performance/分析链和媒体，并只撤销本次引用。 |
| 静默动作内容 | `BundledExerciseCatalog` 提供 40+ 常见动作内容与授权/项目素材；空数据库不产生动作，已知动作创建后只 fill-only 激活自身内容，未使用目录条目不进入列表或 Tool。 |
| 动作图片 | 列表左侧加载紧凑动作示意图；详情首屏只读展示示意图、名称、教练提示，并在“标准动作”内合并主要/辅助肌群文字与紧凑双面肌群图；最近训练另行分层。编辑与媒体管理（用户上传、显式 AI 动作示意图生成、示范视频、外部链接）在工具栏菜单的子页。肌群图不再 AI 生成；既有 generated/user 肌群图仍可在媒体子页查看删除。generated/user 图片进入合并、备份、恢复、清除与媒体回收。 |
| 快捷输入 | `CoachView` 本地候选读取 active 名称；`ExerciseInputSuggestionBuilder` 优先读取统一训练记录，旧带练尚未物化时才读取 completed Set，一行给出动作名加最近一次训练，不重复候选、不请求网络、不写业务数据、不为缺失历史编造数值。 |
| 计划真值 | 当前计划以动作级两类计划间歇、独立 `TemplateSetPrescription`、Session、Performance、逻辑 Set 和原子 Effort 分层；开始训练冻结快照，组间歇只编译到非最终逻辑组。旧逐组计划间歇只做一致值兼容提升。 |
| 计划 GUI 创建 | `TrainingProgramCreationView` 与当前计划编辑器共享处方草稿、动作图片选择器和最近容量解析器；只读取当前 active 动作，以稳定 ID 调用 `TrainingPlanStore` 创建计划，空字段保持 `nil`。动作设定统一编辑两类间歇，连续相同组忽略间歇收成一句，展开后仍写入独立目标行。 |
| 统计兼容 | `TrainingStatistics` 以来源 Performance ID 在投影训练记录与原始 completed Set 间择一累计，不把计划、建议或同一带练动作算两次。 |
| 带练 V5 | Coordinator 按 current Performance/Set/Effort、deadline 和 transition revision 推进；`.both` 固定左后右，时长 Effort 与左右/组间休息到期自动推进且只能一次。Performance 终态先生成具有 business ID、动作关系、唯一 projection key 的 `WorkoutEntry`，全跳过不建记录；最后一个 Effort 自动完成 Session 并进入分享预览，不再等待“保存并结束”。 |
| 自动录像 V5 | `WorkoutCameraService` 将 Delegate/stop/中断归一为 attempt 终态，Coordinator 是唯一 Alert 源；Effort 保存独立视频，Set/Performance 录像路径只作兼容投影。success key、提前 finish、重复 finish/stop、同 attempt 单 Alert 和新 retry 新 Alert 必须有自动化测试，真实相机仍需真机。 |
| 训练系统投影 | 独立 `SomaWorkoutActivityAttributes` 只投影通用阶段、组进度和休息结束时间；本地通知与 `soma://workout/session/{id}` 深链不包含动作、重量或媒体。 |
| 视频复盘 | `PerformanceReviewView` 主动创建 Agent Job；`record_performance_analysis` 校验视频指纹并幂等绑定 source Job。 |
| 内容版权 | 用户视频、本地自有/授权来源和外部链接分层；不抓取第三方课程；通用肌群图不冒充个人受力。 |
| 数据主权 | Snapshot/DTO、开放导出、加密备份恢复、主动清除和媒体引用集合覆盖全部新增模型。 |

## 已实现：可靠 Agent 与远程持续执行

以下是 [PRD 011](archive/0.0.1/prd/011-durable-agent-jobs-remote-continuity.md) 和
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

以下是 [PRD 020](archive/0.0.3/prd/020-gui-simplification-and-progressive-disclosure.md) 的当前实现证据
（v0.0.3，不新增功能）。

| 要求 | 当前证据 |
| --- | --- |
| 教练降噪 | Agent Skill/Tool 过程默认折叠为一条状态摘要行；「本次仅本机」为长按发送键菜单；Composer 上下文条单层展示；空态一句引导加两个示例；失败使用珊瑚色卡，右侧只有无文字重试图标；历史会话保留左缘右滑，并按 PRD 026 的真实使用反馈恢复左上角时间按钮。 |
| 训练降噪 | 统计/版本/AI 继续折叠、管理入菜单；计划首屏改为无标题可编辑概览、训练效果、动作列表。三种录像策略在点击开始后一步选择，取消准备页；主动录像成为执行页常驻控制，进度改为动作/逻辑组嵌套分段。逐组编辑只显示动作定义下有意义的字段，复制只创建独立副本。 |
| 进展降噪 | 足迹与动作库独立成卡，「最近记录」只保留训练/饮食/体重；足迹为朋友圈式 feeds 卡片（头像、正文可展开、宫格媒体、位置与相对时间）；视频缩略统一为 `VideoPosterView` 封面帧；记录编辑折叠受力图/热量估算/AI 解析/原始记录；历史行单主指标、筛选「全部 + 按月」。 |
| 设置降噪 | 设置为底部第 4 个 Tab，内容页右上角不再放齿轮；AI 服务「平台 → API Key → 模型」三步，Base URL/图片模型/小模型档进「高级」，保存与获取合并；任务进度、后台处理、数据、隐私与高级入口直接平铺，不显示“更多”标题；身体信息核心字段直出；隐私页仅位置开关加一句 footer；不提供 Apple 健康或 Keep/COROS 同步入口；远程数据边界折叠；Skills 二级页；「高级设置」文案统一。 |
| 动作库降噪 | 详情只读首屏 + 工具栏菜单进入编辑/媒体子页；提示文本直出无标题；受力图双面 210pt 可放大，有效区域、标签与引导线统一使用训练橙深浅；示范视频首屏可看可传（与媒体子页共用 `ExerciseDemoVideoLibrary` 写入规则）；内置目录扩充纯文字条目（150+，键唯一与肌群可映射由单测门禁）；历史默认 5 条、更早折叠；列表行缩略图 48×54、副文案一行。 |
| 红线不破坏 | 聊天发送链路、全部记录 CRUD、missing-is-nil、API Key/导出备份清除/远程授权披露、带练状态机语义均未因界面折叠而删除。 |
| 设计系统 | `AppTheme` 提供 `cardRadius`/`controlRadius` 圆角 token 与 `listThumbnailSize`/`listRowVerticalPadding` 列表密度规范；重构涉及界面已替换硬编码样式。 |

## 主体已实现：频率优先双主题与无损训练记录编辑

以下是 [PRD 039](archive/0.0.9/prd/039-frequency-first-dual-theme-ui.md) 与
[ADR 0089](archive/0.0.9/adr/0089-semantic-dual-theme-and-lossless-workout-editor.md) 的当前实现证据；真实相机与真机 VoiceOver 继续单列。

| 要求 | 当前证据 |
| --- | --- |
| 双主题 | `AppAppearancePreference` 提供跟随系统、浅色、深色，并在 `RootView` 统一映射 `preferredColorScheme`；`AppTheme` 提供纯白/纯黑 page、浅深 card/inset/separator、黑白主交互与稀疏语义彩色图标。浅色语义色适度提高明度与饱和度，在纯白背景上保持清晰且对比度至少为 4.5:1；暗色语义色保持既定色值。语义图标不使用阴影、柔光或模糊。未知偏好回落系统。 |
| 配色可读性 | `AppThemePaletteTests` 验证浅/深语义前景至少 4.5:1、黑白主控件使用反色前景，并固定两种主题的表面明度顺序。 |
| 根页面 | 四个 Tab 保持独立导航栈；教练和任一根页再点无操作，训练、进展、设置详情页再点回根。根标题均使用 inline，未选中图标为线框、选中项为中性强调。训练按进行中、计划、最近训练；进展按四周期、饮食与能量、训练、身体和原始记录组织；设置按个人与训练、服务、平铺低频入口、显示、关于、反馈。 |
| 设置图标 | 根设置项保留既有文字、SF Symbol 形状和行布局，仅将图标按身体、训练、智能、数据、通知和后台功能映射为不同语义色；图标不得统一黑白，不增加彩色底块或彩色文字。`SettingsHomeIconTests` 验证全部符号有效互异并覆盖六类功能色。 |
| 开关状态 | 全产品 Switch 复用 `appToggleStyle()`；开启轨道使用正向状态色，关闭保持系统中性，带练语音及设置子页在浅深主题都能辨认状态且保留 VoiceOver 值。 |
| 教练阅读与输入 | AI 正文和用户消息使用 Subheadline Light，结构标题与强调仅使用 Medium；AI 正文直接对齐消息区左边界，不设置重复头像或装饰列；用户消息使用主题灰色气泡。Composer 只保留加号、文本、麦克风和发送，三个 Skill 紧凑但保持 44 pt 触达；当前 Session 处理中发送键原位变为暂停键，不在回复下方重复入口。每条消息显示日期时间；时间、执行日志和反馈按相同小视觉间距左对齐，各自保留不重叠的 44×44 触达槽。训练卡动作名优先，尾随 chip/保存/删除紧凑排列；底部“添加一组”和右对齐热量同一行。 |
| AI 结构化排版 | `CoachResponseDocument` 只解析标题、段落、分隔线、有序/无序列表，`CoachResponseView` 映射为本地原生布局；未知 Markdown 可读降级，模型不能注入任意 UI。 |
| 外观与反馈 | 外观位于平铺低频入口之后、关于之前，三种偏好即时应用；纯白主题的设置 section 使用浅灰分组卡和明确间距，根分区标题对齐卡片外沿。所有实心主操作使用显式 `accent/onAccent`，不得依赖系统 prominent 反色推导。反馈继续直接嵌入最后一组，逐回复入口复用 `FeedbackView`。 |
| 无损编辑 | `WorkoutRecordDraft` 按有序 evidence 建立逻辑组和 effort；聊天 `InlineWorkoutCard` 与详情 `WorkoutRecordDetailView` 共用 `WorkoutLogicalGroupsEditor`，聊天使用 10/9 pt 紧凑密度、详情保留标准密度；保存从 draft evidence 回写，不经聚合标量重建，控件触达仍不少于 44 pt。 |
| 侧别与目标 | 编辑器覆盖双侧同时、左右各做、仅左、仅右，以及次数或时长；正常界面没有组号，VoiceOver 可用序号定位。侧别、类型、目标、次数/时长和重量相同的连续组压缩为 `×N`，间歇不参与判断；动作最后一组没有组间歇，左右动作仍有换侧间歇。 |
| 真值回归 | `WorkoutRecordEditorProjectionTests` 覆盖顺序、legacy 无索引、左右 effort、四种侧别、次数/时长、忽略间歇的连续压缩、最后一组间歇目标、录像元数据无损、添加继承结构与复制移除录像；缺失值保持 `nil`。 |
| 设计依据 | 浅深设计稿、当前实施截图、页面规则、未采用方案与验证矩阵保存在 [工程报告](engineering/soma-ui-design-system.md)；Coding Agent 使用 `.claude/skills/soma-ui-development/`。 |

## 已实现：LLM 暂存补偿与显式配置

以下是 [PRD 021](archive/0.0.3/prd/021-llm-staging-explicit-configuration-and-input-suggestions.md)、
[ADR 0045](archive/0.0.3/adr/0045-llm-outage-staging-and-compensating-drain.md) 与
[ADR 0046](archive/0.0.3/adr/0046-explicit-llm-configuration-and-input-history-suggestions.md) 的当前实现证据
（v0.0.4）。

| 要求 | 当前证据 |
| --- | --- |
| 发送不被 LLM 状态阻塞 | 缺 Key 时连续发送三条：三条 Turn、媒体引用与 Job 全部落盘且为 `staged`，没有 Trace、没有业务记录（`ConversationStagingFromSomaTests.testConversationProcessingStagesTurnWhenAPIKeyMissing`、`LLMOutageStagingTests.testMissingAPIKeyStagesMessageInsteadOfRejectingSend`）。 |
| 有任务在途仍可发送 | 发送键不再因 `isProcessing` 失效；后续消息按 `createdAt` 排队，前一条被后台租约挂起也不丢失（`AgentJobTests.testBackgroundLeaseExpirationKeepsJobRecoverable`）。 |
| 失败三分类 | `LLMOutageClassifier` 把传输错误映射为 `retryNetwork`，缺配置/地址无效/401/403/408/409/425/429/5xx 映射为 `stage`，400/404/413/422 与明确不支持多模态映射为 `fail`（`LLMOutageStagingTests`）。 |
| 暂存退避有界 | 供应商侧故障按 `2^n` 秒退避、上限 5 分钟；等待用户改配置的场景不设退避，靠配置变更信号唤醒（`testStagingRetryDelayGrowsAndCapsAtFiveMinutes`、`testStagingWithDelaySetsBoundedRetryWindow`）。 |
| 补偿消费 | App 启动、回到前台、`llmConfigurationDidChange`、上一条任务结束与退避到期只恢复普通可运行/可补偿 Job；明确欠费的 `waitingForUser` 不被这些信号释放。`AgentMutationReceipt` 继续保证同一 Turn 不重复写入。 |
| 暂存可解释 | 发送前缺少执行位置时用户消息显示「已暂存」，输入区上方显示待处理计数与“管理”入口；管理页按发送顺序列出内容摘要、状态和附件数量，支持左滑单删、清空全部与按顺序重试全部。执行失败后不再承诺自动继续；失败卡使用独立语义色，并只在右侧显示人工重试图标。 |
| LLM 配置直出 | 「AI 服务」更名「LLM 配置」；顶部档位分段，平台/Base URL/API Key/模型同屏可改；模型、Base URL 与图片生成模型改动即落盘，不依赖返回时机，设置 Tab 与暂存管理入口始终从共享 `AIService` 读取同一值。 |
| opencode | 默认 `https://opencode.ai/zen/v1`；端点拼接由测试覆盖。所有模型名一律不能推断多模态，只有模型目录明确字段可判断，否则未知。 |
| 输入历史式建议 | `InputSuggestionList` 同时服务模型建议与聊天动作建议；动作建议最多 5 条、归档动作不出现、前缀命中优先，合并规则由 `ExerciseInputSuggestionBuilderTests` 覆盖。 |
| 红线不破坏 | Tool Schema、幂等边界、missing-is-nil、本地优先与 BYOK 均未变化；暂存只推迟执行时机，队列完全保存在本机。 |

## ReAct 可靠性与上下文感知

[PRD 022](archive/0.0.3/prd/022-react-reliability-and-context-awareness.md) 与
[ADR 0047](archive/0.0.3/adr/0047-deterministic-context-pack-and-cross-turn-facts.md)–[0050](archive/0.0.3/adr/0050-per-turn-tool-group-exposure-and-parallel-calls.md)
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
| 延迟辅助 | 流式滚动约 10Hz 非动画节流，后续步骤可释放历史图片；完整视频及重试不替换成帧。Trace 可观测首增量、投影与缓存 token。 |
| 红线不破坏 | LLM 摘要只替换更早对话且有确定性兜底，不静默跨轮合并业务记录；Tool Schema 仍固定；本地/远程共用版本化 Envelope。 |

## 可靠高效 ReAct 与原位审查

[PRD 027](archive/0.0.5/prd/027-reliable-efficient-react-and-in-context-review.md) 与
[ADR 0062](archive/0.0.5/adr/0062-user-resumed-llm-interruption-barrier.md)–[0066](archive/0.0.5/adr/0066-bundled-action-illustration-coverage.md)
的当前实现证据。

| 要求 | 当前证据 |
| --- | --- |
| 人工屏障与 FIFO | 所有已越过 ReAct Loop 的可见失败进入 `waitingForUser`；启动、前台、网络、定时器和配置变化都不释放，`claimNext` 不跳过队首。“按顺序重试全部”仍由用户显式释放并由 `claimNext` 串行领取。 |
| Loop 内恢复与手动重试互斥 | 只有未产生可见增量的模型步骤可在 Loop 内执行三次 1/2/4 秒退避；失败一旦显示即停止自动领取。重试复用同一气泡，移除旧错误和失败文字，保留成功 step。 |
| 每个 step 精确续跑 | 检查点持久化原生 `assistant.tool_calls` 和逐条 `role=tool` 结果；模型成功后、每个 Tool 成功后都立即落盘。双 Tool 回归证明第二个失败后只重试第二个，恢复请求的 System/User 前缀不变。 |
| 同气泡与固定时间 | 重试复用 `responseMessageID`，清理旧 error/running 投影；Job 创建时冻结原始 Turn 时间、`effectiveBusinessDate`、时区和 `defaultOccurredAt`，首次 claim 再冻结 `loopStartedAt`。create/update 的 `occurred_at` 省略时复用稳定默认值，排队、跨午夜和重试不使用新墙钟。 |
| 两层超时 | `AgentStreamDeadlinePolicy` 为文字/图片/视频 20/40/60 秒，仅首个模型处理启用；后续模型无单步门禁。`AgentLoopDeadline` 默认以 3/5/10 分钟活动执行预算取消当前窗口，用户可分别设为 3–60 分钟；等待用户、网络或前台不计时。自动恢复保留已耗时长，用户显式重试刷新预算并读取最新设置，但保留固定业务时间与成功 step。 |
| 确定性快捷训练 | typed 最近训练草稿 trim 后未改且无附件时使用 `deterministicWorkout` Job；空 Key 测试证明不调用 LLM、执行时间实时读取并产生同构 Trace/Event/结果卡。 |
| 最新回复原位 CRUD | 四类稳定 record reference 投影训练、饮食、身体和健身房卡；同一 Turn 不同动作各成一条记录、各有一张卡，卡片插在产生它的那一步之后，写入前后的文字保持原顺序。最后一条消息必须是 AI 回复才可编辑，发送用户消息后立即锁定。保存成功显示已保存态；删除写入有界 correction block。连续成功 Skill/Tool 收成一条可展开过程摘要，失败卡单独露出，Event Cards 不被结果卡替换。 |
| 计划与一级页面 | 计划动作设定同屏提供两类适用间歇，独立组提供次数/时长和重量；进展四周期详情切换训练天数、工作组、容量与时长；设置底部直接嵌入反馈。 |
| 进展原始记录 | 日页按饮食、训练、身体分组展示，周期详情按日展示；复用原记录行与详情，不使用嵌套滚动或六条截断。 |
| Tool 与 Prompt 节制 | 未选快捷按钮注册完整当前协议 Tool，选中按钮只注册该按钮工具白名单。System 使用分层 `[SOMA SYSTEM v2]`，User 使用 `[SOMA CURRENT TURN v2]` 固定顺序且空块完全省略；后续只追加 assistant/tool 尾部。 |
| 动作图覆盖 | 内置专属图条目不少于 239，Bundle 逐资源校验；高位下拉、胸托哑铃划船、单臂绳索下拉、杠铃深蹲和静态保加利亚深蹲有确定目录映射。用户上传图最高；没有用户图时新版内置图高于旧生成图。 |
| 逐回复反馈 | 每条已完成 AI 回复的时间、执行日志和 `text.bubble` 图标组成紧凑操作行；两个图标分别贴近相邻 44 pt 触达区的内侧边缘，缩短可见距离但不牺牲触达面积。点按反馈后在当前消息下方原位展开表单，布局完成后自动平滑滚到当前编辑器底部，支持关闭、文字、照片、视频和 1–5 星，不显示上下文提示、不发起页面或 Sheet 切换，手动收起不强制滚动。投递成功先打钩，再渐进收起；失败保持展开并保留草稿与附件。入口只携带消息 ID，发送时才定向读取上下文；Envelope 限定当前 Turn 可见问答、媒体数量及脱敏 Job/Trace/Span 摘要，总长不超过 5,000 字。 |
| Gmail 自动化 | Codex 自动化 `soma-gmail-draft-pr` 每 3 小时运行一次；只处理一封未标记反馈，从最新 `origin/main` 建隔离分支并产出分析、必要 PRD/ADR、实现、测试、Changelog 和 Draft PR。成功建 PR 后才标记邮件；不合并、发布或真机安装。 |

## 消息元信息、快捷按钮 CRUD、可观测性与饮食双卡片

[PRD 033](archive/0.0.7/prd/033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md)、
[ADR 0082](archive/0.0.7/adr/0082-shortcut-owned-tool-bindings-and-method-only-skills.md)–[0085](archive/0.0.7/adr/0085-record-cards-follow-the-producing-step.md)、
[BUG 0024](bugs/0024-streaming-cross-actor-swiftdata-crash.md) 与
[BUG 0025](bugs/0025-guided-recording-terminated-by-connection-reconfiguration.md) 的当前实现证据。

| 要求 | 当前证据 |
| --- | --- |
| 消息元信息单行 | `ChatMessageMetaLine` 在消息底部输出一行 caption2：每条消息固定显示日期与时间，跨年额外显示年份；用户消息带位置时同行显示「日期时间 · 位置」并对长 POI 中间截断。独立位置胶囊已删除，VoiceOver 合并朗读。 |
| 日期入口位置 | 记录日期入口位于导航栏 `principal` 的两行标题下方居中，输入区不再放日期芯片；改期仍持久化到 Session 并只影响本次对话默认日期。 |
| 快捷按钮存储 | `AgentInputShortcutStore` 以 UserDefaults JSON 保存增删改与排序，未知工具名在读写两侧清理；删除 Skill 时解绑引用它的按钮。`AgentInputShortcutTests` 覆盖默认三按钮、可见性与规范化。 |
| 曝光边界 | 选中按钮时 `AgentToolExposurePolicy` 只返回该按钮工具白名单与当前协议交集，未选时返回全量；`AgentJob.selectedShortcutID` 让排队、恢复与远程 Envelope 沿用同一判断，旧 checkpoint 的 `exposedGroups` 仍可还原。 |
| AI 推荐工具 | `AgentToolRecommendationService` 只在用户点按时发一次非流式请求，优先小模型档，返回清单与理由并丢弃未知名称；未配置模型或响应不可解析时保持原选择并说明失败原因，请求不含健康数据。 |
| 流式稳定性 | 流式 chunk 回调保持 `@MainActor`，文字增量经 `AgentTextDeltaCoalescer` 合批；segment id 携带形态标记保证 `ForEach` 身份唯一；DEBUG 下投影入口断言主 actor，`make check` 静态守卫这两条。 |
| LLM 工具清单可见 | 本机与后台持续处理的每次模型调用都把 `exposed_tool_names` 与数量写进 model span metadata 和诊断日志；Server 的 `model.started` Event 携带实际工具集合，执行时间线只显示摘要，完整绑定工具/入参/返回在 Span 详情页可选择复制。 |
| 诊断日志 | `DiagnosticsLogStore` 双文件滚动记录生命周期、模型调用、Tool 结果、Turn 终态与录像阶段，恒定脱敏密钥与 Authorization，不写媒体 Base64。 |
| 崩溃误报边界 | `AppRunSentinel` 只保留待关联上下文，未清位、强杀、调试器停止、模拟器停止和覆盖安装都不是崩溃证据。只有 MetricKit `MXCrashDiagnostic` 可生成报告；升级时清理所有缺少 `metricKit` 证据来源的旧队列。`CrashDiagnosticsTests` 覆盖来源门禁。 |
| 崩溃自动上报 | MetricKit 明确提供崩溃类型、终止原因和堆栈后，`CrashReportComposer` 才汇总环境、可关联的上次运行上下文与日志尾部；`DiagnosticReportMailer` 以独立主题和 `.txt` 附件发送，失败留盘重试、最多 5 份。高级设置提供总开关与查看入口。 |
| 录像失败原因 | `WorkoutRecordingFailureDiagnosis` 把 `AVError.Code` 与中断原因映射为具体中文原因并附 `（domain code · stage）`；非预期结束与中断都使用该诊断，同时写入诊断日志。 |
| 饮食双卡片 | 聊天内第一张「记饮食」卡是可直接改的菜品清单，行内可改名称、份量、kcal 与三大宏量并支持增删行与改餐次；第二张「饮食评价」卡只读，随草稿由 `MealNutritionTotals.derive` 实时重算，缺项显示「未估算」不补零，保存后写入值与卡二一致。 |
| 卡片位置 | `AgentTurnTranscriptSegments` 把 `record_refs` 插在产生它的 Tool 或过程摘要之后，重复引用只出一张卡，无法归位的兜底在末尾；饮食 Skill 要求写入前先说一句不含数字的识别说明。`AgentChatPresentationTests` 覆盖顺序与去重。 |
| 饮食时间 | `defaultOccurredAt` 保留发送时刻钟点；05–11 早餐、11–14 午餐、14–17 下午点心、17–22 晚餐，其余加餐。只有用户原文明确说出餐次时可覆盖，模型 `meal_type` 不能单独覆盖；饮食 Skill 明确要求没有用户明确时间就省略 `occurred_at`。 |
| 升糖评价 | 总糖已从菜品、整餐、Tool、查询、备份和开放导出删除。速度只接受 `slow/moderate/fast` 且必须与依据成对；增删或修改菜品后旧评估自动失效。详细描述按真实布局超过五行才显示展开/收起。 |

## 已实现：历史、媒体、Tab 与带练取景打磨

[PRD 034](archive/0.0.8/prd/034-history-media-tabs-and-guided-capture-polish.md)、
[PRD 035](archive/0.0.9/prd/035-guided-preview-then-record-and-immediate-share.md)、
[ADR 0086](archive/0.0.8/adr/0086-preview-and-history-thumbs-use-aspect-fill.md) 与
[BUG 0025](bugs/0025-guided-recording-terminated-by-connection-reconfiguration.md)、
[BUG 0026](bugs/0026-guided-auto-recording-still-stops-without-reason.md) 的当前实现证据。

| 要求 | 当前证据 |
| --- | --- |
| 媒体 zoom | `MediaViewer` 在 iOS 18+ 使用 `navigationTransition(.zoom)`；iOS 17 关闭 cover 动画并先交付已解码图。调用点经 `mediaViewerCover` / `mediaZoomSource`。`VideoPosterView` 未就绪占位为 `AppTheme.softTint`。 |
| 饮食行复用 | 详情 `MealRecordEditor` 与聊天共用 `MealItemDraftRow`；聊天 `InlineRecordShell` 内边距 10/7，菜名 footnote、宏量 caption2。 |
| 历史芯片与折叠 | `historyListChrome` 使用 inline 标题加图标；`HistoryMonthFilterBar` 无 `.bar` 实心底。每一天是 `HistoryDayHeader` 卡片，日期与条数与行缩略图共用 `HistoryDayCardLayout.horizontalInset`，折叠后仍显示条数与已知容量/热量。`WorkoutHistoryQueryTests` 覆盖饮食按天分组、摘要只累加完整容量/热量，以及同年芯片省略年份。 |
| Span 独立页 | `AgentTraceSpanRow` 是 `NavigationLink`；`AgentTraceSpanPayloads.sections` 分段入参/返回。`AgentTraceSpanPayloadsTests` 覆盖超长入参不依赖时间线内嵌。 |
| Tab 再选 | `RootTabReselectObserver` 只旁听原生 Tab Bar 上触摸开始时已选中的 item；`AppTabNavigationState` 从设置 path 和训练/进展根显隐维护非 Observation 根状态。`AppTabReselect.effect` 将每次点击限定为一个效果：普通切换只写一次 selection，教练与任一根页 `.noAction`，训练、进展、设置仅在非根时 `.resetStack`。旧 `.restoreCoachRoot` 通知已删除。教练根仍只持有稳定入参，Tab 激活态经 `\.coachTabIsActive` 只送达实时转写与切回滚底叶子；`AppTabTransitionCoordinator` 只记录隐私安全 signpost。`AppTabReselectTests`、`CoachTabBehaviorUITests` 与 `perf-check` 覆盖根感知行为。 |
| 自动录像宿主 | `beginCurrentSet` 先进入 `.setInProgress` 并打开放大取景，`waitUntilPreviewHostSettled` 后再 `startRecording`。已有预览连接时换宿主不重建、不因 `session-interruption` 停掉 Session；`prepare()` 复用仍在跑的 Session。录像中可缩小。非目标组不显示取景。`GuidedWorkoutCoordinatorTests` / `WorkoutCameraServiceTests` / `GuidedWorkoutLayoutTests` 覆盖时序与居中；`validate-repository.sh` 静态守卫。 |
| 预览 fill | `WorkoutCameraSurface` 与 `CameraPreviewView` 默认 `.resizeAspectFill`；历史录像缩略按取景比例 `scaledToFill`。 |
| 完成后分享 | 计划执行结束（最后 Effort 收口或提前结束）后直接呈现 `WorkoutShareSheet`；关闭后回到训练主页。海报固定白底黑字，橙黄色主视觉内展示大号容量、肌群图和三列统计；分享弹层适配双主题。动作名和数据优先单行、长内容自适应换行；明细复用逻辑组连续压缩并保留所有异构段；同值左右合并、异值分列、未知重量不作自重。见 [ADR 0117](adr/0117-workout-share-editorial-poster.md)。 |
| 计划执行复盘 | 按 Session 的 Performance 顺序和 `sourcePerformanceID` 加载对应训练记录，直接复用进展页 `ProgressRecentActivityRow`，显示动作名、压缩组次、可计算容量和训练时间，并进入同一 `WorkoutRecordDetailView`。完成但投影缺失时只在未设置删除抑制的情况下幂等修复；用户已删除时显示“训练记录已删除”。 |

## 会话标题与输入上下文单行布局

[PRD 037](archive/0.0.9/prd/037-generated-editable-session-titles-and-single-row-composer-context.md) 与
[ADR 0088](archive/0.0.9/adr/0088-async-generated-session-title-with-manual-precedence.md) 的当前实现证据。

| 要求 | 当前证据 |
| --- | --- |
| 日期标题 | Session 创建时按 `startedAt` 与业务时区同步生成 `MM月dd日 - 周X`；不调用小模型或标准模型，允许同日重名。schema version 7 启动迁移把全部旧 Session（包括曾手动命名）统一为日期标题。 |
| 手动改名 | 升级后长按抽屉行仍可手动重命名，并可恢复当前 Session 的日期标题；两者都不修改 `updatedAt`。`titleSourceRaw` 只保留已安装数据库/旧备份字段兼容，业务不读写。 |
| 备份兼容 | `ConversationSessionDTO` 继续无损往返兼容列；导入后的当前业务规则以标题文本和业务时区为准，不恢复模型命名链。 |
| 单行上下文 | `CoachComposer` 把最多六个快捷按钮和达到两个后的健身房 Menu 放进同一个水平 `ScrollView`；窄屏、长名称与大字号横向滚动，不折到第二行。附件和动作建议继续使用独立内容上下文条。 |
| UI 与无障碍 | Session 行不显示省略号；标题长按直接打开限制非空 40 字的重命名弹框，删除只保留原生尾随左滑。会话行继续提供 VoiceOver 重命名自定义操作与手势提示。 |

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
个人空间为空、演示空间/API Key/系统相册与外部备份仍在，且自动备份已断开。

锁屏组件需要真机手工验收：长按锁屏进入“自定”→“锁定屏幕”→“添加小组件”，确认 Soma
下出现文字、拍照、照片/视频入口；分别添加行内、圆形或矩形样式，点击后应先遵循系统解锁，
再进入对应的教练输入流程。

历史媒体验收使用虚构图片和视频：在同一 Session 先发送媒体，收到回复后再发送不带附件的
追问，确认 Agent 能引用前一轮画面；新建或切换到另一个 Session 后发送相同追问，确认不会
携带旧 Session 媒体。构造十一轮以上对话，确认远程请求只包含最近十个完整来回。

教练页手工验收：点击左上角时间按钮打开会话抽屉，再关闭并从左边界右滑打开同一抽屉；新建两个非空 Session 后分别点击标题外的行尾空白切换、长按标题重命名并继续发送；确认每次进入只出现最近 30 条，已加载页滑动过程高度不变、不跳；到顶再增加 30 条且当前位置不跳；切 Session 或 Tab 回来时已画过的气泡第一帧就是终态，不再从占位或 Incremental 重画；短对话顶部对齐，打开 Session 时长对话停在最后一条消息末尾；长流期间向上阅读不会被自动拉回底部；持续流式至少 35 秒后继续滚动、切 Session 和切 Tab，确认没有随正文增长而逐渐加重的卡顿或发热；从其他 Tab 切回教练时列表自动回到最新消息；在长对话中先上滑再点「教练」Tab，确认页面、抽屉、健身房页、滚动位置和分页数量均不变化；教练长对话存在时连续在训练、进展、设置之间切换，确认切换动画不掉帧；在长对话中连续快速输入、删改文字并使用听写，确认输入区跟手、消息列表无联动卡顿；
首次发送分别验证允许和拒绝位置都只出现一次确认；准备 0、1、2 个健身房验证只有两馆时
显示切换入口；保持一个长会话和未发送草稿，连续三次进入后台再返回，页面出现后立即滚动和输入，
确认当前 Session、位置和草稿不变且没有触摸冻结；长按用户主题灰色气泡并拖动选区，分别在浅色、深色外观确认选区与气泡明显区分，
且复制菜单仍可用；确认 AI 正文从消息区左边界开始、没有重复头像或装饰列；长按 Agent 的列表、链接和多段回复验证可精确选择复制。分别点击聊天中的
单张、双张和三张以上折叠媒体，确认从缩略图位置放大进入全屏、可切换与缩放，且没有删除聊天附件的入口，
过程中不先出现一块空黑全屏。准备四个以上虚构动作并查询两条虚构训练，确认过程默认只显示一条状态摘要行；点开后 Tool
卡片先显示结果数量或简短结论，展开逐项完整显示动作/训练信息但不出现 UUID、JSON、
`function` 或 `tool_call` 内部标记，收起后恢复紧凑高度。原始参数与 ID 应继续能在
“高级设置 → 执行日志”中审查：时间线只显示摘要，点 LLM 行进入独立页查看完整入参并可复制。

历史与 Tab 验收：打开训练历史，导航栏常驻「训练记录」标题与图标，其下是没有实心底条的「全部」和有数据的月份芯片，点日期折叠再展开当天；
饮食历史同样按天分组。从进展进入一条饮食详情，切到训练 Tab 再切回进展，仍停在该详情；再点
「进展」回到进展首页，再点根页「进展」不滚动也不刷新。教练在当前 Session、抽屉或健身房页
再次点按均无反应。进展按 [PRD 000](prd/000-origin-through-0.0.11.md) 与 [PRD 057](prd/057-coach-focus-progress-rings-and-library-clarity.md) 检查日／周／月／年、日历任意选日、
箭头和回到当前周期；首次进入默认「日」和今天，手动选周后切 Tab 返回仍为周；点选图表不改变时间窗口、也不切换周期。柱图从零开始，虚线与柱使用同一 kcal 轴，年按有效天数加权。
今日不混入完整日均值，未来不补零；累计未知项按零计入小计，原记录仍为空，缺失数在能量依据里可见。
能量依据按 [ADR 0000](adr/0000-origin-through-0.0.11.md) 使用紧凑数值列表，公式、来源和诊断在计算明细内。
分别点击摄入／总消耗，原位显示餐食／消耗组成的彩色明细浮层；周月年分项与首页有效日均值一致，训练不重复叠加。
有有效全天静息即用个人设置或默认参考 1.4 估算，不读取设备能量，不把默认值写成用户事实。
按 [ADR 0000](adr/0000-origin-through-0.0.11.md) 与 [ADR 0122](adr/0122-nutrition-rings-and-period-deficit.md) 验证日页无重复训练／身体卡且原记录和分享可达；周显示训练频率与周均体重，月显示容量及月内体重变化，年显示按月训练天数与月均体重变化。缺测不补体重，单个测量日／月不生成变化值。
训练详情切换天数／工作组／容量／时长，身体详情切换体重／体脂率／腰围，点击进入相同原记录详情；修改、删除后统计刷新，分享复用当日聚合。
设置根页没有「健康数据与设备」；Info.plist 与工程不含 HealthKit 权限。

训练计划 GUI 验收使用两个虚构动作：计划详情从上到下是无标题可编辑概览、确定性训练效果、
动作列表和训练历史，不显示业务版本号、版本历史或恢复入口。第一个动作配置 `.both`，包含热身
次数组、左右重量不同的工作次数组和工作计时组；第二个动作配置 `.right`。逐组新增、复制、
删除和排序后确认所有组完全独立，切换 target kind 不会同时保存次数与秒数，空字段没有被补齐。
再次编辑直接更新当前计划；已开始 Session 的旧 `plannedSets` 快照保持不变，新 Session 使用更新后的处方。

计划与动作详情验收继续使用虚构数据：计划总览中累计辅助组数不能把辅助肌群列为主要；受力图有效
区域、标签与引导线在浅深主题中均为训练橙深浅。动作详情的主要肌群、辅助肌群、提示、双面受力图
与图例位于“标准动作”的同一列表行，没有空白 Divider 行或独立受力图章节。点击一个含异构组的
计划动作后，首个业务区块显示
本计划目标；最近一次显示 `4×5次 29kg · 1×3次 29kg` 而非逐组序号，最近容量、较上次变化、图上
两点和横轴真实日期与两条记录逐项一致，最后逻辑组的组后间歇不出现。

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
本地分享预览”自动执行，不出现“保存并结束”；只有点击分享才打开系统分享。体重只使用 Session
开始前最近有效 BodyEntry，计划执行热量等于来源动作记录之和。清空身体记录后，训练仍能完成，
热量保持为空且计划页/分享页提供身体信息入口，不显示 `0 kcal`。从历史删除 Session 时清理来源
带练投影记录、Set/Effort、分析和私有录像；由当日原始训练组装的 Session 只解除原始记录关系，
不能删除用户原始记录。删除单条带练投影后 suppression 阻止其复活。

视频真机验收使用虚构素材：百炼 Qwen 直传一个约 7MB 内短视频，确认 Trace 的
`direct_video_count` 大于零；再用明确不支持的平台验证发送被阻断、没有关键帧替代；最后使用不可读
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
使用包含三类虚构食物的餐食确认评价卡新增一行建议食用顺序；进入详情可编辑该行，改变任一菜品后
旧顺序自动清空，备份恢复与便携导出仍能保留新顺序。

LLM 配置在模拟器补充验收：在模型输入框手输一个不在 `/models` 列表中的 ID，返回设置首页再
进入，确认值不变且重新拉取候选也不覆盖；切换到小模型档确认平台、Base URL、Key、模型独立；
选择 `opencode` 确认 Base URL 预填 `https://opencode.ai/zen/v1` 且可改写。

## 动作库分类与餐次明细（PRD 055／057）

按 [PRD 055](prd/055-exercise-facets-and-meal-breakdown.md) 与 [PRD 057](prd/057-coach-focus-progress-rings-and-library-clarity.md)：左侧常驻身体部位及下级主要肌群、动作类型（复合力量／孤立训练／核心／爆发表现／有氧体能／未标注），搜索只与右侧卡片同宽；右侧即时更新，名称搜索与分类路径取交集；详情返回保留选择，空结果可重置。不再提供独立「受力肌群」轴。日摄入明细显示餐次前缀和固定双主题配色，未知热量显示未估算，不重复卡面已有汇总。确定性测试、正常字号双主题、小屏键盘／滚动与 iPad 检查已通过；不涉及数据库迁移。

## 快捷聚焦、实时听写与进展圆环（PRD 057）

按 [PRD 057](prd/057-coach-focus-progress-rings-and-library-clarity.md)：主屏幕快速记录组件浅色／深色／着色都能看清；饮食可编辑卡保存时不拖慢隐藏的进展 Tab。默认快捷按钮为「记录饮食」「训练记录」「近期分析」；点选且输入框为空时，「近期分析」填入建议句，「记录饮食」和「训练记录」不预填。选中快捷按钮后 System 只保留身份、人格与安全契约，信封只带该 Skill，默认不暴露 `load_skill`。听写未确认片段实时出现在输入框，确认后才写入草稿；中途改字丢弃当前猜测。麦克风进入录音态，不再显示「正在本地听写…」。进展日页用四枚独立环（上中热量、下排蛋白质／碳水／脂肪）对照推荐摄入；顶部事实卡写摄入与消耗，热量环心写已摄入／推荐摄入 kcal，不写还可摄入或完成百分比；热量环不重复标题，宏量用红橙紫图标与数字同行，点按热量环打开摄入明细、点按宏量环打开该营养素克数明细；不足与超量只靠进度和颜色，当日未达推荐时底部再显示仍可摄入且不可点开。周、月、年只保留日均与图表，不展示营养环，点图不切换周期。

## 撤回 Apple 健康接入（PRD 060）

按 [PRD 060](prd/060-remove-healthkit-until-redesign.md)、[ADR 0128](adr/0128-remove-healthkit-until-redesign.md)：设置无健康同步入口；进展快照不读设备能量；工程无 HealthKit entitlement 与健康用途说明。

## 教练 ID、训练卡 0 与进展一致性（PRD 059）

按 [PRD 059](prd/059-coach-ids-progress-and-required-zeros.md)、[ADR 0126](adr/0126-workout-share-pro-max-canvas.md)、[ADR 0127](adr/0127-agent-workout-weight-and-rest-zero.md)：本机上下文与跨轮引用只暴露 Int64 `record_id` / `exercise_id` / `program_id` / `session_id`，饮食食物项不再给出 UUID。Agent 省略训练重量或非最后组间歇时落 0；0kg 显示自重。进展日列表每条训练同时给出容量与已估算热量；预估总消耗仍是静息 × 活动系数，已记录训练 kcal 只作对照、不累加。训练分享导出 440×956 pt。计划训练统计按 Session ID 打开复盘。教练页写入后 RootView 递增进展 revision，隐藏的进展 Tab 再进入会重读当日快照。冷启动后已排版页展示全部消息，含助手气泡。可编辑卡保存后有「已保存」胶囊与教练 Toast。左右各做的组数 `×N` 在成对卡片右侧垂直居中。超长标题换行。
