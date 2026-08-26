# Soma 全 App 性能审计报告（2026-08-24）

- 状态：本轮已收尾；Release 真机长流与 Tab 预算通过，Session p95 354.505 ms 未通过，其余动态门禁延期
- 目标设备：iPhone 17 Pro Max，120 Hz 严格档
- 数据基线：已安装 Soma `0.0.11 (15)`，SwiftData marker `schemaVersion = 6`
- 上游依据：[ADR 0000](../adr/0000-origin-through-0.0.11.md) 收口的真机预算与有界数据访问规则
- 收尾复盘：[本轮性能优化收尾与踩坑报告](performance-optimization-retrospective-2026-08-25.md)

## 2026-08-25 最终收尾补充

Release 真机内存虚构夹具完成 30 轮四 Tab、120 个完整 signpost：整体 p50 `63.480 ms`、p95
`82.731 ms`、max `100.921 ms`；每个目标各 30 个样本且无中断，当前 `<100 ms` p95 门禁通过。
Coach 方向 p50 `74.509 ms`、p95 `98.877 ms`。

同一构建完成 30 轮 Session、60 个完整 signpost：p50 `92.454 ms`、p95 `354.505 ms`、max
`357.702 ms`，超过 `<200 ms` 门禁。本轮按维护者要求停止继续修复；SwiftUI/Allocations、全路径
滚动和连续真机内存门禁同样延期。因此最终结论是“Tab 已达标、Session 未达标”，不能宣称全 App
已全面达到 120 Hz 严格档。发布整理已把最终 harness 的 Session/滚动适配器从 `CoachView` 抽到
独立支持文件，`make check` 当前通过；完整发布门禁结果在发布前最终复核。自动化与实现踩坑、
证据口径和下轮起点见收尾复盘。

## 2026-08-25 纠偏结论

此前“单帧替换”的 Simulator 结果依赖全局 `UIView.setAnimationsEnabled(false)`，会让系统交互反馈
延迟或样式异常，不能作为可接受优化，现已完整删除并由静态门禁禁止恢复。当前 Tab 点击路径只写
一次 selection；四个 Tab 的导航与页面状态仍分别保留。保留状态不等于系统永久缓存已排版像素，
inactive 子树再次可见时仍可能执行 SwiftUI diff、布局和文本测量。

真机独立根子树样本把训练、进展、设置方向性降低到约 `33–105 ms`，但返回 Coach 仍约
`578–592 ms`。Time Profiler 中主线程成本集中于 AttributeGraph 更新/布局、Lazy stack 测量、
TextKit/输入框与 CoreText，不是 SwiftData 重开或全库读取。

“长时间流式后越来越卡、手机发热”的直接代码原因已经确认并修复：每个约 200 ms 的投影 tick
曾让整个 `CoachSessionView` 失效，并为正在增长的全文构造临时 `AgentTurnItem`、重复清洗全文、
重新布局全文和滚到底部。现在 UI 只更新实时回复叶子，只修改稳定分块的尾块；隐藏 Coach Tab
停止订阅流式 revision，完整字符串只在完成落盘时合并一次。完成态 Markdown 与内联文本解析使用
有界缓存，内存警告时清空。

最终 Release 真机又定位并删除了最后一层线性放大：稳定分块虽然避免重新构造全文，但内层即时
`VStack` 仍会在尾块变化时测量全部冻结正文，CoreText/`NSOptimalLineBreaker` 因而持续重复断行。
正文块改用 `LazyVStack`、每块固定纵向理想尺寸，并把可变尾块从 768 收紧到 256 字符。相同 35 秒
虚构长流场景中，总 CPU 从 `6.047 s` 降到 `0.998 s`，主线程从 `6.004 s` 降到 `0.950 s`
（`-84.2%`）；5 秒后的主线程单核负载从 `16.785%` 降到 `2.643%`，15 秒后仍为
`2.649%`，没有再随正文增长反弹。独立 Animation Hitches 录制为 0 个 actual hitch、0 个
`>33 ms` 潜在交互延迟，设备热状态全程 `Nominal`。

真机随后暴露了另一条与“消息总数”无关的大会话卡死路径。只读统计显示故障 Session 只有 12 条
消息，正文不足 1 KB；真正的差异是最新回复引用了一份十项饮食记录。旧实现会在页面出现时为每项
菜品同时创建菜名、热量、份量和四项营养值的原生 `TextField`，并由 `ViewThatFits` 构建候选布局，
一次切换即可集中产生几十个 TextKit 输入控件。现在默认只显示轻量文本按钮，用户点中的单个值才
创建输入控件，失焦后释放。虚构十项饮食卡 UI 回归已覆盖 Session 点击、长按重命名和往返切换；
新包也已直接启动到真机原故障 Session 并保持进程存活，最终触摸手感仍待维护者确认。

Coach 的消息窗口进一步收紧为“按访问发生”：Session 首次只查询最近 10 条和一条更早哨兵，
到达顶部后每次追加 10 条并恢复旧首条的视觉锚点。短内容顶部对齐，长内容初始定位最后一条到底部。
只有懒栈真正创建的可见气泡才会把清洗文本、Turn 分段、附件和位置解析结果写入 64 项有界缓存；
未打开的 Session 和未滚到的历史消息既不解析也不缓存。记录卡同样在出现后才按业务 ID 异步读取
一项，不建立 SwiftData 模型对象全局缓存。用户向上阅读时会停止 5 Hz 流式自动滚底，避免手势与
程序滚动互相争抢造成卡顿和额外布局。

自动化夹具使用显式 UI-test 哨兵、内存数据库和虚构数据；已确认画面真实持续增长到第 165–177 段。
Simulator 只证明路径和视觉合同，最终 120 Hz、卡帧、内存和热状态仍以 Release 真机为准。
真机录制入口会先读取 CoreDevice 锁屏状态；锁定时不再启动编译、UI 自动化或 xctrace，避免把锁屏
等待和空 trace 误当 App 性能样本。

## 结论

Tab 切换本身不会重新打开数据库；卡顿主要来自 Tab 首次构建或 SwiftUI 更新时，大量
`@Query` 同时取值、无界查询订阅无关对象、`body` 内重复派生、同步图片读取解码，以及启动和
Agent/带练状态推进中的整表扫描。整改把根层生命周期保留为稳定的四个导航栈，同时将热点改为
定向 fetch、分页、纯值快照、后台 actor、异步图片管线和有上限缓存。

静态计数从 77 个 `@Query` 降到 42 个；`RootView` 从常驻查询降为 0，`CoachView`、
`InsightsView` 和 `SettingsView` 各为 3 个，且 `InsightsView` 剩余项均为按记录 ID、
`fetchLimit = 1` 的详情加载器。`FetchDescriptor` 文本计数从 262 增到 332，
这是把少数“取全表后内存过滤”拆成更多按 ID/状态/Session 的数据库谓词所致，不代表读取量增加。

第二轮专门沿用户点击后的同步反馈路径继续做减法：普通 Tab 切换只写一次选中状态，性能
signpost 由稳定引用持有，系统自行表现选中图标；设置根页不再提前读取 LLM Keychain 配置或发起
模型列表请求；教练根页把动作建议所需的大集合搬到后台纯值快照；进展根页用带脏标记的 warm
cache 合并刷新；训练复盘视频哈希和语音识别资源均推迟到用户真正触发对应动作时。

第三轮继续沿“点击发生后，主线程还有什么必须同步完成”逐项收口：Root 首次恢复不再与
`scenePhase.active` 重复；Coach 将消息、Job、暂存 Turn 和重试状态合并成单次投影；训练计划统计、
动作库最近训练、进展计数与读取最新体重记录进入后台有界读取；训练总结、分享和带练记录只读最新版
关系图，不再逐层按 UUID 回查。Keychain、崩溃诊断、媒体准备、JPEG/PNG 编码和文件写入也从
页面出现或 MainActor 同步路径中移除。

第四轮进一步只看 TabView 提交选中外观的同一 MainActor 周期。Coach 原先在每次出现时写一遍
可观察的可见状态、同步解码快捷按钮 JSON、重复读取位置偏好；离开时即使语音早已结束，也可能
同步停用 `AVAudioSession`。Insights 则在 `onAppear` 内立即提交快照请求状态。现在显隐元数据使用
非 Observation 引用，快捷按钮、建议与 Insights 快照均先让出点击提交周期，音频停用只在确实
录音时发生并同样延后。Training 与 Settings 根页未发现同类出现钩子工作，保持不增加逻辑。

第五轮继续从系统 Tab 容器和所有导航目的页做减法。当前 iOS 18+ 改走原生 `Tab` 内容构建器，
iOS 17 只保留共享内容的兼容分支；Tab signpost 在选中提交后才结束。Coach 不再在 View 构造时
解码快捷按钮、提前创建语音服务或用顶层 `GeometryReader` 包裹整页；Settings 根页不再拥有未打开
的 LLM 表单状态，并把反馈编辑器延后一个提交周期。高级设置、Skills、快捷按钮、崩溃报告和日志
的 JSON/文件读取也全部离开导航首帧。最后，训练续训卡、带练关系、动作历史、足迹和 Insights 图表
删除了重复排序、过滤与扫描；足迹分页从 100 收窄到 40，历史首批查询先让出导航提交周期。

第六轮曾尝试用全局 UIKit 动画开关消除系统内容交叉淡化；用户实测证明该方案造成反馈延迟和样式
异常，因此相关实现、测试结论和验收表述已撤销。保留的有效结论只有：四个独立根子树明显降低了
训练、进展和设置的返回成本，而 Coach 的剩余长尾来自布局与文本更新，需要通过叶子状态隔离和
稳定文本分块解决。

## 方法与证据等级

- **code-backed**：调用图、查询谓词、分页上限、actor/缓存所有权和取消路径可由代码直接证明。
- **trace-backed**：iOS 26.5、iPhone 17 Pro Max Simulator、Debug 构建的 signpost 与 ETTrace。
- **trace-backed**：另含 iPhone 17 Pro Max / iOS 26.3.1 上旧版 30 次冷启动、30 轮四 Tab 与 10 轮滚动，以及当前构建 27 个完整冷启动初样本。
- **待真机**：当前构建 120 Hz Animation Hitches、Release 主线程停顿、内存增长、30 次严格同间隔冷启动和最终真实手感。

审计覆盖 App/Views/Components/Models/Services、SwiftData、文件与媒体、Agent 本地/远程投影、
带练、备份恢复、Widget/Live Activity 入口，并以 `rg` 静态扫描、压力测试、模拟器 UI 回归、
OS signpost 和 ETTrace 交叉验证。

## 主要问题与整改

| 优先级 | 原问题 | 根因 | 整改与当前边界 | 证据 |
| --- | --- | --- | --- | --- |
| P0 | warm Tab 仍有明显“按下后才反应” | 一次选择同时更新选中 Tab、pending signpost、手工填充图标与导航栈辅助状态，Root 被连续失效 | 普通切换只写一次 `selectedTab`；重复点当前 Tab 才写对应栈 ID；signpost 移入不参与观察的稳定 tracker；选中外观交给系统 TabView | `AppTabReselectTests` 验证 switch/reselect 各自只产生一个 effect；`perf-check` 禁止恢复 pending Root 状态和手工选中图标 |
| P0 | iOS 26 warm Tab 动画与内容反馈延迟 | 全局 UIKit 动画抑制会影响系统 Tab 反馈，且不能降低 Coach 实际布局工作 | 完整删除全局动画开关；保留原生 Tab 动画，点击只写 selection；以叶子失效、文本分块和布局减法降低真实工作量 | 静态门禁禁止 `setAnimationsEnabled`；四 Tab UI 合同回归通过；最终真机 p95 待补 |
| P0 | 长流式后整 App 变卡发热 | 每个 tick 广泛失效 Coach；稳定分块后内层即时栈仍反复测量、断行全部冻结正文 | revision 限定到实时回复叶子；隐藏 Tab 停止观察；正文块懒布局、尾块最多 256 字符；完成时才合并全文 | Release 真机同场景主线程 CPU `6.004 → 0.950 s`（`-84.2%`）；35 秒 Animation Hitches 0，热状态 Nominal |
| P0 | 进入含多项饮食卡的历史 Session 后卡死退出 | 最新可编辑饮食卡为每个值立即创建原生 `TextField`，候选布局进一步放大 TextKit/AttributeGraph 成本；消息读取本身很小 | 默认渲染轻量文本按钮，点按后只创建当前一个输入控件；失焦释放，完整记录与编辑语义不变 | 真机只读数据定位；十项虚构饮食卡定向 UI 回归通过；新包直接打开原故障 Session 后进程稳定，最终触摸确认待补 |
| P0 | 根页面出现/消失工作与系统选中外观争用同一周期 | Coach 写可见状态、解码快捷按钮、重复读偏好并可能停用音频；Insights 在 `onAppear` 写快照请求 | Coach 可见性不参与 Observation；快捷按钮/建议/音频清理和 Insights 请求均先 `Task.yield()`；Training/Settings 不新增出现逻辑 | 第四轮静态门禁、Simulator build 与 583 项 iOS 测试通过；第六轮实际点击通过 |
| P0 | 当前系统仍走旧式 Tab 声明且埋点结束参与选中提交 | iOS 26 仍使用 `.tabItem` 兼容声明；内容同步 `onAppear` 结束 signpost | iOS 18+ 使用原生 `Tab` 内容构建器，iOS 17 复用同一内容的兼容分支；signpost 先让出提交周期 | code-backed、Simulator build；实际切换、保栈与重复点按回根通过 |
| P0 | 进展 Tab 首次和重复渲染卡顿 | 十张 `@Query` 在 `body` 内同步筛选、排序、格式化并构造图表，且每次出现都重新刷新 | 后台 `InsightsSnapshotLoader` 读取有界窗口并生成 Sendable DTO；缓存键包含日期、时区和数据 revision，相关保存只标脏，隐藏期间不失效 View，warm 返回复用快照 | ETTrace 改造前 `InsightsView.body` 92.164 ms、快照构造 11.509 ms；保存影响判断单测通过，最终真机 trace 待补 |
| P0 | 带练每次状态推进随历史增长变慢 | `activeSession/currentSet/currentEffort` 和集合 helper 每次取整表再过滤 | 全部改为 session/performance/set/effort ID 谓词与排序；当前对象 `fetchLimit = 1` | 静态门禁要求相关空 `FetchDescriptor()` 为 0 |
| P0 | 启动迁移重复扫库 | marker 检查前执行投影键和动作属性回填，Root 再跑多组历史 repair | marker 谓词和 `fetchLimit = 1` 前移；marker 6 正常启动立即返回；Root 只保留终止中断 Trace 与当前内容激活 | `RootView @Query = 0`；启动历史回填静态门禁 |
| P0 | 图片消息、缩略图和全屏查看掉帧 | View 渲染路径同步 `Data(contentsOf:)`、`UIImage(data:)` 和原图解码 | `ImagePipeline` actor 合并同请求、ImageIO 下采样、48 MB `NSCache`、文件指纹失效；内存警告/空间切换清空 | View/Component 同步图片读取静态计数为 0；图片管线测试通过 |
| P1 | 教练长会话放大重算与常驻内存 | 当前 Session 全历史、全部 Job、记录引用与输入建议多次线性扫描，根 View 还持有约 2,140 个训练模型上限 | 最近 10 条、到顶每页 10；非终态 Job；根 `@Query` 8 → 3；只缓存实际可见气泡的 64 项纯渲染结果，未访问 Session 不预热；记录卡出现后才异步按 ID 取一项 | 10,000 消息压力夹具；初始 10 → 到顶 20 的 UI 回归；后台快照和保存影响单测通过 |
| P1 | Agent 投影随历史 Event 增长 | Host 订阅全部 Event，并拼接所有字段生成字符串 revision | Host 只观察非终态或 cursor 落后的 Job；每 Job `fetchCount`/sequence 高水位；Hashable 值修订 | `AgentSystemProjectionHost`/Store 单测与静态字符串 revision 门禁 |
| P1 | 训练/历史/足迹一次加载全部记录 | 根页、分享、结束训练和详情无日期窗、无上限或 O(n²) 配对 | 训练根用一个有界计划查询拆分当前/归档；分享和结束训练沿关系/ID 定向读取；历史和足迹分页；动作/复盘按业务 ID；配对使用字典 | 5,000 训练记录聚合压力夹具及训练计划/分享/带练测试通过 |
| P1 | 对话删除和清空待处理队列偶发长停顿 | 删除一项也读取全部 Session/Job/Message/Event/Trace/Receipt | 先按 session/turn/job/message/trace ID 定向 fetch；仅媒体保留扫描属于低频回收步骤 | 三个服务的空全表热路径由 `perf-check` 阻断 |
| P1 | 导出/备份开始时 UI 先卡住 | 文件写入已 detached，但全库 DTO capture 在 `@MainActor` | `PersonalDataSnapshotLoader` 使用独立 ModelActor；加密、复制、恢复准备均在可取消 detached task；循环检查取消 | code-backed；完整 `make verify` 已通过 |
| P2 | 重复媒体和孤儿文件占空间 | 每次保存 UUID 副本；演示素材先复制；清理只看单空间有误删风险 | 内容哈希命名 + 每引用唯一硬链接；一次性合并既有重复 inode；演示按缺失复制；清理用个人/演示引用并集 | 1,000 引用压力测试、共享硬链接删除安全测试 |
| P1 | 设置根页打开即做无关配置工作 | LLM Keychain 读取、配置解析、模型列表网络刷新在设置首页出现时触发 | 所有 LLM 配置读取和模型刷新移到“语言模型”目的页；根页也不再计算或展示 Trace 数量 | code-backed；`SettingsView @Query = 3`，静态门禁禁止恢复根 Trace 计数 |
| P1 | 设置详情导航与诊断页首帧仍做同步 JSON/文件读取 | 高级设置、Skills、快捷按钮在 `onAppear` 解码 UserDefaults；诊断页同步读取报告目录和最多 256 KB 日志 | 导航提交后 detached 解码；日志与报告由串行队列异步读取/清空；写入后删除不必要的二次解码 | 异步日志/报告测试与 `perf-check` 通过 |
| P1 | 视频复盘与语音能力提前占用主线程 | 点击分析时同步读取/哈希视频；教练首次构建就创建 `SFSpeechRecognizer` 和 `AVAudioEngine` | 视频指纹按路径、大小、修改时间缓存，UI 使用 detached 异步哈希；语音识别器和音频引擎只在首次语音动作后创建 | 异步/同步指纹一致性测试通过；第二轮 ETTrace 中 `SFSpeechRecognizer`、`AVAudioEngine` 均为 0 个样本 |
| P0 | Coach 消息数量增长后 Tab 返回和流式刷新变慢 | 每个消息气泡重复扫描全部 Job、Turn 和消息决定状态，形成 O(n²) | 每次渲染建立一次 `CoachMessageRenderProjection` 和可重试消息 ID 集合；气泡只做字典/集合 O(1) 查询；删除两组重复直播状态观察 | 10,000 消息压力夹具、编译与 583 项 iOS 测试通过；最终真机 warm p95 待补 |
| P0 | 长流时向上阅读仍被持续拉回底部 | 每个流式修订都会安排一次程序滚动，用户手势和 5 Hz 自动滚动争抢同一 ScrollView | 只在仍跟随底部时合并滚动；检测到用户拖动或离开底部立即取消待执行滚动；到顶分页后恢复旧首条视觉锚点 | 长流 UI 夹具中初始 10 条、连续向上手势和自动分页到 20 条通过 |
| P1 | 训练详情与动作库存在隐藏 N+1 | 每个 Session/动作分别查询统计、最近训练、Set/Effort 与动作定义 | 训练统计和动作最近记录由 ModelActor 单次快照；折叠统计懒加载；当前 marker 6 关系图直接提供 Performance/Set/Effort/Definition | 当前关系夹具与迁移修复测试通过；静态门禁禁止恢复逐关系 descriptor |
| P1 | 启动后仍可能重复恢复和同步解码诊断 | Root `.task` 与首次 active 同时解析/恢复；崩溃报告在 MainActor 读取并二次解码 | 初次维护完成前忽略首次 active；维护步骤主动 yield；诊断报告串行队列异步加载并复用内存缓存 | code-backed；诊断异步/缓存和 Root 单次恢复静态门禁 |
| P1 | 数据库任意保存让无关页面重算 | `didSave` 只要包含对象 ID 就尝试解析多类模型 | 先比较 `PersistentIdentifier.entityName`，仅命中对应实体集合后才解析；删除也按实体分类 | 保存 Agent Event 不影响 Coach 建议、Insights、训练历史和动作库；Workout 保存只失效相关投影 |
| P2 | 低频日志页被历史拖慢 | 日志筛选在内存完成，正文提前解码 | 执行日志 30 条分页且状态进入谓词；详情展开后才解码 | code-backed |
| P1 | 训练、动作详情和足迹重复构造同一派生结果 | 续训卡多次排序同一关系；带练重筛已限定 Query；动作历史和足迹在每个 `body` 重复合并/排序 | 每个 `body` 单次投影；带练直接复用有序 Query；足迹只在分页结果变化时重建且每页 40 | 静态门禁与 iOS 585 项聚焦测试通过 |

## 缓存与懒加载规则

| 缓存/投影 | Key | 上限 | 失效 |
| --- | --- | --- | --- |
| 图片 | 标准化文件 URL、文件大小/修改时间、目标像素 | 48 MB cost limit；同请求合并 | 内存警告、数据空间切换、文件指纹改变、显式清空 |
| 进展快照 | 日期起点、当前时区、相关业务数据 revision | workout 1,000、meal/body 500、message 1,000、set 5,000 | 相关记录保存后标脏；隐藏期间合并，下一次出现或下拉刷新时更新 |
| 教练建议快照 | 相关业务数据 revision | definition 2,000、workout 100、session 40、performance 400、set 1,500 | 仅训练/动作库等相关模型保存；聊天消息、Trace 和流式 Event 保存不失效 |
| 教练消息查询 | 当前 Session ID、分页上限 | 初始 10 + 1 哨兵，到顶每次 +10 | Session 切换重置为 10；对应消息变化 |
| 已查看消息渲染 | 消息 ID + 原始正文/Turn/附件/位置字段 | 64 项；仅可见气泡构建时写入，不预热未访问 Session | 字段变化覆盖；内存警告清空 |
| Agent 投影 | Job ID + 各消费者 cursor/high-water mark | 非终态或落后 Job | 新 sequence、终态完成并追平、空间切换 |
| 视频性能指纹 | performance ID、文件路径、大小、修改时间 | 32 项 | 文件指纹变化自然换 key；内存警告和显式清空 |
| 崩溃诊断报告 | 诊断目录当前内容 | 最多 5 份、每份 2 MB | 新增、删除、更新、清空和裁剪时同步更新串行队列缓存 |
| Keychain 必要密钥状态 | 当前 provider/profile 所需凭据 | 进程内当前值 | 写入、删除和显式 warm 时更新；设置详情负责触发首次读取 |
| 训练计划统计 | program ID | 仅当前展开详情的纯值快照 | 展开时加载；Session/Performance/Set/Effort 保存后按实体分类失效 |
| 动作最近训练 | exercise ID | 动作库当前最多 2,000 个 ID 的纯值字典 | Workout/Exercise 保存后重载；消息、Trace/Event 保存不失效 |
| 媒体物理内容 | SHA-256；逻辑引用仍使用独立路径 | 文件系统容量 | 最后一个硬链接被删除；孤儿维护按双空间引用并集 |

缓存不持有跨 `ModelContext` 的 SwiftData 对象，也不成为业务事实来源。

## 剩余全量读取清单

第二轮后，源码中空参数 `FetchDescriptor<Model>()` 的词法出现量为 89，不能等同于 89 个
交互期全表读取。逐项可达性复核如下：

| 数量 | 所在边界 | 保留原因 |
| ---: | --- | --- |
| 30 | `SomaDataMigration` | 当前 marker 未完成时的一次性数据收口；正常启动先命中 marker 并返回 |
| 25 | `DataArchiveModels` | 用户明确执行完整备份/导出时必须枚举全部持久模型 |
| 14 | `MediaMaintenance` | Root 可交互后的后台孤儿清理必须构造个人/演示双空间引用并集 |
| 6 | `DemoSeeder` | 演示空间当前基线仅首次初始化/修复；`UserDefaults` marker 后不再执行 |
| 4 | `ExerciseLoggingProfile` | 当前 schema 收口时一次性推断缺失动作记录方式 |
| 3 | `InsightsView` | 仅用于 `fetchCount` 组成失效 key，不物化模型对象 |
| 2 | `ExerciseLibraryStore` | 当前动作目录批量激活与一次性旧名称收口；编辑、重命名、合并和撤销已改成定向查询 |
| 2 | `DemoTrainingPlanSeeder` | 演示空间一次性计划种子 |
| 2 | `ChatRecordEditorCards` | 当前健身房唯一性和删除后选择替代项，需要遍历通常极小的健身房集合 |
| 1 | `TrainingPlanStore` | 只在 Session 同时缺少当前 id/name snapshot 的基线前残留行才进入；当前路径先按 program ID 查一项 |

因此没有把完整归档、明确的一次性迁移或必须构造引用闭包的任务伪装成“可以分页”的交互查询；
所有当前高频 UI、Agent、带练和动作库编辑路径均由 `perf-check` 约束为定向或有界读取。

## 交互路径审计矩阵

| 路径 | 结果 |
| --- | --- |
| 冷启动/当前 marker | marker 先行，已完成安装不再进入整表迁移；Root 可见后才跑孤儿/去重维护 |
| 前后台 | 只恢复前台等待/过期租约 Job；状态谓词进入数据库；媒体和相机资源仍成对释放 |
| 数据空间切换 | Root 按空间重建；图片缓存清空；媒体维护按双空间引用并集 |
| 四个 Tab | 稳定导航栈；普通切换只写一次选中状态；重复点当前 Tab 才回根；iOS 26.5 Simulator 实际点击、跨 Tab 保栈和再选回根通过；内容由约 298–388 ms 跨帧淡化收敛为单帧替换，Release 真机 p95 待补 |
| 教练 | 当前 Session 分页、发送附件异步持久化、流式约 100 ms 合批、记录卡按 ID 查一项；建议快照后台化，语音资源按首次使用创建 |
| 训练/带练 | 根查询有界；状态机定向查询；相机/视频保存异步；倒计时只更新必要叶子状态 |
| 进展 | 后台窗口快照；最近活动最多 30；完整历史分页；Charts 只接收有界 DTO |
| 设置/日志 | 设置根不读取 LLM 配置、不刷新模型、不计算 Trace 数；执行日志 30 条分页，Prompt/Span/正文按详情读取 |
| 媒体 | 异步下采样、缓存、硬链接去重、双空间孤儿清理 |
| 备份/恢复 | 快照读取与文件加密后台化；取消可传播；最终数据库替换仍为明确的阻塞事务 |
| Widget/Live Activity | 不读完整身体库；继续只消费隐私安全的小投影 |

## 当前持久模型审查

当前 28 个 SwiftData 模型均有现行业务用途：身体事实与外部游标、动作与计划、Session/Set/Effort
执行事实、Recommendation/Analysis、Conversation/Trace/Receipt、持久 Job/Event、迁移 marker、
业务 ID sequence 和滚动摘要。没有模型可以在不破坏 `0.0.11 (15)` 当前数据或现行架构的前提下
整体删除。本次删除的是不可达的历史整表 repair、旧重复检测 helper、批量计划来源 backfill 和相应
旧断言；仍被 marker 6、当前在途 Job、当前归档恢复或当前字段 getter 使用的技术兼容代码保留。

## 动态证据与限制

第六轮在 iPhone 17 Pro Max / iOS 26.5 Simulator 上完成实际点击。门控前 warm 四向切换的 signpost
约 54–62 ms，但逐帧视频仍观察到页面像素变化跨越约 298–388 ms，说明 signpost 的
`Task.yield()` 结束点不能代表系统淡化完全结束。门控后现代 `Tab` 的全页面内容在一帧内完成替换，
之后仅底部系统选中区域继续变化；设置详情跨 Tab 保栈、重复点设置回根均通过。UI 自动化还会执行
Accessibility 元素查询，因此这些数字只用于 A/B 和功能证据，不替代 Release 真机 p95。

随后使用无 ETTrace、无测试宿主的 Release Simulator App 进行独立暖态复验。实时 signpost 分别约
53 ms（教练→训练）、56 ms（训练→进展）、60 ms（进展→设置）和 63 ms（设置→教练）。逐帧
视频将上方内容区与底部 Tab 区分开计算；四次切换都只有一个高差异内容帧，之后仅底栏选择反馈或
极小局部更新。进展快照约 23 ms、教练建议约 22 ms，并未再次延长页面内容转场。该四次小样本证明
实现不依赖 Debug/ETTrace，但仍不用于计算严格 p95。

同一 Release Simulator 随后连续执行 10 轮四 Tab，共 40 次切换，全部成功。App signpost 总体
p50 59 ms、p95 61 ms、最大 63 ms；训练、进展、设置、教练各自最大值分别为 55、60、61、
63 ms。每轮后的宿主进程 RSS 在约 414.6–418.0 MB 间波动，最终约 415.2 MB，低于首轮约
415.5 MB，没有单调增长。该预检会受到 Simulator 与 Accessibility 自动化影响，只排除明显长尾、
动画恢复泄漏和方向性内存增长，不能替代真机 Allocations 或 120 Hz 验收。

ETTrace 改造前样本为 21.84 s，总 active 2.44 s；`SwiftData` inclusive 1.746 s，
`InsightsView.body` 92.164 ms。中间样本证明仅把聚合移出 `body` 仍不够：十个 Query getter 使
`dataRevision/body` 94.199 ms，因此最终删除渲染期 revision 轮询。随后样本证明 ModelActor 若在
MainActor 上创建仍可留下 50.302 ms inclusive；最终实现进一步在 detached task 内创建 actor。
这一最后边界已有代码和构建证据，但尚未取得 Release 真机 trace，不能写成已通过 120 Hz 验收。

第二轮在 iPhone 17 Pro Max / iOS 26.5 Simulator 上重新链接 ETTrace，并用匹配 UUID 的 Soma
dSYM 完成启动采样。11.527 s 录制窗口中，`SomaApp.init` inclusive 约 101.762 ms、
`DataSpaceController.makeContainers` 约 84.877 ms、`RootView.body` 约 28.523 ms、SwiftData
栈约 130.821 ms；`SFSpeechRecognizer`、`SpeechInputService.init` 和 `AVAudioEngine` 均为 0 个
样本。该结果证明 App 自身符号化可用，并验证语音资源不再随教练首屏创建；它仍是 Debug
Simulator 抽样，不能替代 Release 真机的绝对耗时结论。

第六轮又采集了匹配 dSYM 的四 Tab 冷/暖与隔离 Settings → Insights ETTrace。暖样本 active
约 1.094 s，其中 Charts inclusive 约 0.598 s；隔离样本 active 约 0.539 s，其中 Charts
约 0.416 s。但栈同时被 `_AXXMIGCopyAttributeValue`、`UIResponder.undoManager` 等
Accessibility 解析显著主导，属于自动化查找 Tab 元素时构建 Charts 可访问性树的污染，不能据此
把正常图表渲染认定为业务热点。临时 ETTrace 链接已从 `project.yml` 移除并重新生成工程。
Simulator 的 Animation Hitches 模板明确报告不支持该平台，因此真正 hitch 仍只在 Release 真机验收。

## 最终自动化与模拟器验收

| 门禁 | 结果 |
| --- | --- |
| `make check` / `make perf-check` | 发布整理已将性能 harness 适配器抽离 `CoachView`；SwiftFormat、SwiftLint、文档链接、生命周期、隐私、数据库文档、仓库契约和性能热点门禁全部通过 |
| Server | 30 个可运行测试通过；PostgreSQL 集成测试因未设置 `SOMA_TEST_DATABASE_URL` 按既有门禁跳过 1 个 |
| iOS | `v0.0.12 (16)` 发布候选最终 `make verify`：595 XCTest + 7 Swift Testing 通过、0 失败；构建成功 |
| Simulator | iPhone 17 Pro Max / iOS 26.5 的 Debug 符号化 ETTrace 和无 ETTrace Release App 均完成构建、安装与实际点击；四 Tab 切换、跨 Tab 保栈、重复点按回根以及门控后单帧内容替换已验证 |
| Release Simulator warm Tab | 10 轮、40 次全部成功；signpost p50 59 ms、p95 61 ms、最大 63 ms；逐帧内容区均只出现一次完整页面变化，底栏后续反馈保留；仅作干净构建预检，不替代 30 次真机 p95 |
| Release Simulator RSS | 每轮四 Tab 后约 414.6–418.0 MB，最终约 415.2 MB、低于首轮约 415.5 MB；无单调增长，但不能替代真机 Allocations |
| 真机采样入口 | 独立 trace 数与交互轮数分离；录制有 300 秒默认收尾上限并验证 TOC 完整性；Tab 模式自动要求每个 Tab 达到声明样本数且 p95 `<=100 ms`，卡死、空壳、缺样本或超预算均写入 manifest 后失败 |
| 静态结果 | `@Query` 77 → 42，Root 0、Coach/Insights/Settings 各 3；`FetchDescriptor` 文本引用 332；App/Views/Components 同步图片读取 0；动作库当前编辑路径空 descriptor 13 → 2 |
| Release Simulator 包体 | 在独立 HEAD worktree 与当前工作区使用同一 iOS 26.5 SDK、arm64、Release、无签名构建；逻辑文件总量 `75,732,816 → 76,666,992 B`（`+934,176 B`，`+1.23%`），主二进制 `+934,208 B`、Assets 不变、Widget `-32 B` |
| 旧版真机冷启动 | iPhone 17 Pro Max / iOS 26.3.1、`0.0.11 (15)` 完成 30 次 terminate-existing 启动；初始化到首帧 p50 `151.780 ms`、p95 `180.079 ms`，到 foreground-active p50 `560.485 ms`、p95 `608.506 ms` |
| 旧版真机交互 | 30 轮四 Tab（120 次选择）和 10 轮设置页滚动；Animation Hitches 为 0，约 44.898 秒窗口内潜在延迟 203 次、`>=100 ms` 69 次、p95 `164.636 ms`、最大 `180.739 ms` |
| 当前构建冷启动初样本 | 27 个完整生命周期：初始化到首帧 p50 `149.647 ms`、p95 `162.684 ms`；到 foreground-active p50 `421.462 ms`、p95 `486.797 ms`。因启动间隔比旧版密、漏掉 3 个完整样本，只作为方向性证据 |
| 真机签名/数据 | Team `6C6NQVDA4M` 覆盖安装和启动成功，版本仍为 `0.0.11 (15)`；没有卸载容器，原训练计划和历史在 UI 中保留 |
| 当前长流 Time Profiler | 同一 35 秒虚构长流中，总 CPU `6.047 → 0.998 s`（`-83.5%`），主线程 `6.004 → 0.950 s`（`-84.2%`）；5 秒后主线程单核 `16.785% → 2.643%`，15 秒后为 `2.649%` |
| 当前长流 Animation Hitches | 35 秒 Release 真机录制：actual hitch 0、`>33 ms` 潜在交互延迟 0；设备热状态在 36.28 秒观测窗口全程 `Nominal` |

包体基线 worktree 不包含 Git 忽略的本机 `FeedbackCredentials.plist`，当前 Bundle 中该文件为 324 B；
因此上表在当前结果中排除了它，只比较相同输入。该文件内容没有被读取或写入报告。没有改造前签名
归档，不能把无签名 Simulator 数字表述为 App Store IPA 大小。

## 未关闭的外部验收

- Release 真机各关键交互 30 次、warm p95 `<100 ms`、冷页面 p95 `<200 ms`。
- 30 轮 Tab、滚动和真实 Session 的 Animation Hitches 卡帧率 `<1%`、无 `>100 ms` 主线程停顿；
  独立长流夹具已经通过 0 hitch、0 个 `>33 ms` 延迟。
- SwiftUI `body` 无可重复 `>1 ms` 热点；十轮跨 Tab/媒体/聊天无单调内存增长。
- 真机签名安装后的键盘、浅深色、Dynamic Type、相机、锁屏和网络状态手感。
- 旧版冷启动、Tab 与滚动基线已经补采；旧版没有本次新增 signpost，因此 warm Tab 只能以
  Animation Hitches 的潜在响应延迟和 actual hitch 同路径比较，不能补造点击到稳定内容 p95。
- 当前构建已经签名安装并保留真实数据；第一批 after 只有 27 个完整生命周期，Mac 自动锁屏导致
  下一批真机通道断开且 30/30 launch 失败。该失败批次排除，解锁后按旧版间隔补录完整 30 次。
- 为避免写入唯一用户的真实数据，长会话发送和媒体创建不做旧版真机自动化；用 10,000 消息、
  1,000 媒体引用压力夹具覆盖增长路径，并在新版只读打开现有内容完成内存/SwiftUI 验收。

仓库提供可重复采样入口。Tab signpost 的严格口径是在一个 Time Profiler trace 内完成 30 轮四 Tab：

```bash
SOMA_PROFILE_DEVICE=<UDID> \
SOMA_PROFILE_TEMPLATES='Time Profiler' \
SOMA_PROFILE_RUNS=1 \
SOMA_PROFILE_INTERACTION=tabs \
SOMA_PROFILE_INTERACTION_ROUNDS=30 \
SOMA_PROFILE_DURATION=120s \
make perf-profile-device
```

脚本会从 120 次选择中自动导出 `Soma Tab Transition`，要求每个 Tab 至少 30 项并拒绝 p95
`>100 ms`。Animation Hitches、SwiftUI 和 Allocations 使用同一 30 轮路径分别录制；
`SOMA_PROFILE_RUNS` 仅表示独立 trace 数，不能再当成交互次数。每份 trace 必须在默认 300 秒收尾
上限内完成并能导出有效 TOC，否则 manifest 标为失败。以上项目在真实设备未连接或未完成相同交互
采样时必须保持“待真机”，不能以 Simulator 或成功安装代替。
