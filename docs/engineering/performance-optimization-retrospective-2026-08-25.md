# Soma 本轮性能优化收尾与踩坑报告（2026-08-25）

- 状态：本轮按维护者要求收尾；核心代码整改已落地，真机 Tab 预算通过，Session 预算未通过
- 审查范围：当前工作区相对 `HEAD` 的 `git diff`、自动化门禁、Simulator/真机 Trace 与失败产物
- 目标设备：iPhone 17 Pro Max，iOS 26.3.1，Release，120 Hz 严格档
- 数据边界：性能夹具只使用显式环境变量、内存数据库和虚构内容，不读取或写入个人数据
- 长期边界：[ADR 0000](../adr/0000-origin-through-0.0.11.md) 收口的真机预算与有界数据访问规则
- 完整审计：[全 App 性能审计报告](performance-audit-2026-08-24.md)
- 关键故障：[BUG 0034](../bugs/0034-large-session-inline-editor-render-hang.md)、
  [BUG 0035](../bugs/0035-long-stream-text-relayout-thermal-jank.md)
- 后续修订：[性能优化经验教训（2026-08-26）](performance-optimization-lessons-2026-08-26.md)
- 下游落地：[真机性能录制：一次安装，多次复用](device-performance-profiling.md)

## 1. 收尾结论

本轮最初的“Tab 是否每次重读数据库”判断不成立。四个 Tab 保留各自导航栈，但 SwiftUI 在隐藏
子树重新可见时仍会执行属性更新、diff、布局和文本测量；保留 View 身份不等于缓存已经排版完成的
像素。真正的主要卡点是无界查询、宽观察范围、`body` 内重复派生、主线程文件/图片工作、长正文
反复断行，以及复杂消息卡一次性创建大量原生输入控件。

截至收尾：

- 长流式发热与随时间加重的卡顿已经得到 Release 真机前后 Trace 证明，主线程 CPU 下降
  `84.2%`，35 秒 Animation Hitches 为 0，热状态保持 `Nominal`。
- 四 Tab 的最终真机 30 轮/120 次切换完整通过，整体 p95 `82.731 ms`，Coach 方向 p95
  `98.877 ms`，满足当前 `<100 ms` 门禁。
- Session 的最终真机 30 轮/60 次切换完整采到，但 p95 `354.505 ms`，超过 `<200 ms`
  门禁。因此不能宣称聊天页或全 App 已全面达到 120 Hz 严格档。
- 当前代码仍以 `.id(activeSessionID)` 重建 Session 页面，已查看 Session 没有保留独立的页面/布局
  生命周期；这与 Session 长尾一致，但尚缺按切换方向拆分的 Trace，属于 code-backed 高概率原因，
  不是已完成修复。
- SwiftUI Instrument、Allocations、全路径滚动和连续十轮真机内存曲线未完成，本轮明确延期。

## 2. 本轮性能优化全量梳理

### 2.1 启动、迁移与前后台

- 将 `DataMigrationMarker.schemaVersion = 6` 的定向检查和 `fetchLimit = 1` 前移；当前安装已完成
  marker 时立即返回，不再在每次启动重复跑业务整表回填。
- 删除 marker 6 后不可达的启动 repair、旧投影键回填和重复兼容读取；仍保留当前归档、当前 store
  打开和在途 Agent Job 真正可达的字段。
- Root 首次 `.task` 与首次 `scenePhase.active` 不再重复解析 Session、恢复 Job 和运行维护。
- 演示内容激活、媒体去重和孤儿回收移到 Root 可见后；重工作支持取消并避免阻塞首帧。
- Root 常驻 `@Query` 降为 0；深链和提醒按稳定 ID、状态与 `fetchLimit = 1` 定向获取。

### 2.2 四 Tab 与 Root 生命周期

- 保留“教练、训练、进展、设置”四个原生 Tab 和四套稳定导航栈；普通切换只写一次
  `selectedTab`，重复点当前 Tab 才重建对应栈 ID 并回根。
- signpost 的 pending interval 移到不参与 Observation 的稳定引用，避免埋点本身触发第二轮 Root
  失效。
- iOS 18+ 使用原生 `Tab` 内容构建器，iOS 17 只保留共享内容的兼容分支；选中图标交给系统，
  不再由业务状态重复切换 filled symbol。
- Coach/Insights 的次要刷新先让出 selection 提交周期；音频清理只在确实录音时发生。
- 完整撤销全局 `UIView.setAnimationsEnabled(false)` 方案，并用静态门禁禁止恢复。

### 2.3 Coach Session、消息窗口与滚动

- `ConversationSessionController` 持有当前 Session 引用，不再让 `body` 为当前会话读取全部
  Session。
- 当前 Session 初始只查询最近 10 条消息和一条“是否还有更早”的哨兵；到顶后每次增加 10 条，
  并恢复加载前首条消息的视觉锚点。
- 短消息不足一屏时顶部对齐；长消息超过一屏时初始最后一条贴底。
- 用户主动向上阅读或离开底部后，取消 5 Hz 流式自动滚底，避免手势和程序滚动争抢同一个
  `ScrollView`。
- Session 列表整行可点按切换；标题长按仍重命名，左滑删除保持系统交互。
- 原位记录卡不再为每张卡同步创建 `@Query`；卡片真正出现后先让出切换帧，再按业务 ID 异步读取
  一项。
- 当前缺陷：Session 身份变化仍通过 `.id(activeSessionID)` 丢弃并重建整个
  `CoachSessionPage`。消息纯值解析缓存能复用部分工作，但不能保留已经访问 Session 的完整 View
  状态和布局，最终 p95 仍未达标。

### 2.4 长流式文本与聊天渲染

- 流式增量约 100–200 ms 合批；不按 token 写数据库。
- `liveEventRevision` 只由实时回复叶子观察；稳定消息、Composer、列表投影和隐藏 Coach Tab 不再
  随每个 tick 重建。
- 增长正文改成稳定冻结块和最多 256 字符的可变尾块；完整正文只在结束时合并并持久化一次。
- 文本块使用 `LazyVStack` 和固定纵向理想尺寸，避免尾块变化时重新测量、断行全部冻结正文。
- 完成态 Markdown/AttributedString 使用有界 `NSCache`；内存警告统一清空。
- 消息、Job、暂存 Turn、可重试状态先构造一次投影，气泡按集合/字典 O(1) 读取，删除逐消息扫描
  整段会话的 O(n²) 路径。
- 只有真正进入懒栈的可见气泡才写入消息渲染缓存；未打开 Session 和未滚到的历史消息不预热。

### 2.5 复杂记录卡与输入控件

- 真机故障 Session 实际只有 12 条消息且正文不足 1 KB；卡死不由“消息太多”导致。
- 真正热点是十项饮食记录为菜名、份量、热量和多项营养值一次性创建几十个 `TextField`，再被
  候选布局重复构建，集中放大 TextKit、AttributeGraph 和布局成本。
- 默认态改为轻量文本按钮；只有用户当前点中的一个值创建 `TextField`，失焦后释放。
- 虚构十项饮食卡覆盖默认 0 个编辑器、单字段编辑、Session 往返、整行点击和长按重命名。

### 2.6 查询、派生快照与失效范围

- 静态 `@Query` 从 77 个降为 42 个；Root 为 0，Coach/Insights/Settings 各 3 个。
- `FetchDescriptor` 文本引用从 262 增到 332，原因是把“取全表再内存过滤”拆成更多按 ID、状态、
  日期和 Session 的定向谓词，不代表读取量上升。
- `ModelContext.didSave` 先按持久实体名称判断影响；Agent Event 保存不再使训练、进展、动作库或
  Coach 建议无关失效。
- Insights 使用后台 `ModelActor` 生成不可变 DTO；cache key 包含日期、时区和相关数据 revision，
  隐藏期间只标脏，warm 返回复用已加载快照。
- 训练计划统计、动作最近训练、读取最新体重记录和 Coach 动作建议改为后台有界快照。
- 训练历史、足迹和执行日志分别使用有限首批与分页；筛选尽量进入数据库谓词。

### 2.7 图片、媒体与文件 I/O

- `ImagePipeline` actor 统一异步读取、ImageIO 下采样、相同请求合并、取消和目标像素缓存。
- 图片缓存成本上限 48 MB；key 包含文件身份和目标像素，内存警告、数据空间切换或文件指纹变化
  时失效。
- View/Component 渲染路径移除同步 `Data(contentsOf:)`、`UIImage(data:)` 和原图尺寸探测。
- 全屏媒体只处理当前项和邻近需求，不长期缓存原始大图。
- 媒体物理内容按 SHA-256 识别；每个数据库引用保留独立逻辑路径，通过硬链接复用相同内容，
  避免删除一条引用破坏其他记录。
- 孤儿清理使用个人/演示空间引用并集；导出、备份、加密、诊断文件、JPEG/PNG 编码和视频哈希
  离开 MainActor，并传播取消。

### 2.8 Agent、带练与低频页面

- `AgentSystemProjectionHost` 只观察非终态或 cursor 落后的 Job；每个 Job 使用 sequence/high-water
  mark 增量投影，不再拼接全部字段生成字符串 revision。
- 删除一条 Session 或待处理 Job 时沿 session/turn/job/message/trace ID 定向读取，不再先取全表。
- 带练的 active Session/Performance/Set/Effort 改为关系和 ID 谓词；倒计时由 5 Hz 降到 1 Hz。
- 设置根页不读取 LLM Keychain、不刷新模型目录、不计算 Trace 总数；语言模型配置和执行日志进入
  目的页后再加载，日志每页 30 条。
- 语音识别器和音频引擎只在用户第一次使用语音后创建；训练视频指纹异步计算并有界缓存。

## 3. 缓存与懒加载最终边界

| 对象 | 边界 | 失效/限制 |
| --- | --- | --- |
| Coach 消息查询 | 当前 Session 初始 10 + 1 哨兵，到顶每次 +10 | Session 切换重新从 10 开始 |
| 已查看消息渲染 | 消息 ID + 原始正文/Turn/附件/位置，最多 64 项 | 只由可见气泡写入；字段变化覆盖；内存警告清空 |
| 长流文本 | 稳定冻结块 + 最多 256 字符可变尾块 | 结束时才合并完整正文 |
| Markdown/AttributedString | 文本内容，4 MB + 4 MB 成本上限 | 内存警告清空 |
| 图片 | 文件身份 + 修改指纹 + 目标像素，48 MB | 内存警告、空间切换、文件变化 |
| Insights/Coach/训练快照 | 业务 ID、时间范围、时区、相关实体 revision | 仅相关保存标脏；不可持有 SwiftData 模型对象 |
| 视频性能指纹 | performance ID + 路径 + 大小 + 修改时间，32 项 | 文件变化换 key；内存警告清空 |

缓存只保存不可变纯值或处理后的图像，不成为业务事实来源，也不跨 `ModelContext` 保存 SwiftData
模型。用户纠偏后的最终规则是“访问后才缓存”，不是启动时为所有 Session 预热。

## 4. 性能测试数据

### 4.1 Release 真机核心数据

| 场景 | 改造前/基线 | 本轮结果 | 结论 |
| --- | --- | --- | --- |
| 长流 35 秒总 CPU | `6.047 s` | `0.998 s` | `-83.5%` |
| 长流 35 秒主线程 CPU | `6.004 s` | `0.950 s` | `-84.2%` |
| 流式 5 秒后主线程单核 | `16.785%` | `2.643%` | 15 秒后仍为 `2.649%`，没有随正文增长反弹 |
| 长流 Animation Hitches | 修复前 Time Profiler 定位到文本/布局热点 | actual hitch 0；`>33 ms` 潜在延迟 0 | 36.28 秒热状态全程 `Nominal` |
| 四 Tab 30 轮 | 旧版同路径潜在延迟 p95 `164.636 ms`，但不是同一 signpost 口径 | 120/120 完成；p50 `63.480 ms`，p95 `82.731 ms`，max `100.921 ms` | 当前 `<100 ms` p95 门禁通过 |
| 返回 Coach | 无同口径 signpost 基线 | 30 次 p50 `74.509 ms`，p95 `98.877 ms`，max `100.921 ms` | p95 通过，单次 max 略高于 100 ms |
| Session 30 轮 | 无同口径基线 | 60/60 完成；p50 `92.454 ms`，p95 `354.505 ms`，max `357.702 ms` | `<200 ms` 门禁失败，明确延期 |

四 Tab 各方向结果：

| 目标 Tab | 样本 | p50 | p95 | max |
| --- | ---: | ---: | ---: | ---: |
| 训练 | 30 | 72.114 ms | 83.661 ms | 89.260 ms |
| 进展 | 30 | 51.241 ms | 54.704 ms | 57.844 ms |
| 设置 | 30 | 60.082 ms | 65.094 ms | 66.721 ms |
| 教练 | 30 | 74.509 ms | 98.877 ms | 100.921 ms |

### 4.2 冷启动方向性数据

| 指标 | 旧版 30 次 | 当前 27 个完整样本 | 变化 | 证据等级 |
| --- | ---: | ---: | ---: | --- |
| 初始化→首帧 p50 | 151.780 ms | 149.647 ms | `-1.4%` | 方向性；after 少 3 个完整生命周期 |
| 初始化→首帧 p95 | 180.079 ms | 162.684 ms | `-9.7%` | 方向性 |
| 初始化→foreground-active p50 | 560.485 ms | 421.462 ms | `-24.8%` | 方向性 |
| 初始化→foreground-active p95 | 608.506 ms | 486.797 ms | `-20.0%` | 方向性 |

after 的启动间隔与旧版不完全相同，且只得到 27 个完整生命周期；不能当作严格 30 次同条件最终
结论，也不能与 Tab signpost 或 Animation Hitches 的口径混算。

### 4.3 自动化与质量门禁

- `v0.0.12 (16)` 发布候选最终 `make verify` 通过：Server 30 个测试通过，1 个 PostgreSQL 环境测试
  按既有规则跳过；iOS 595 XCTest + 7 Swift Testing 通过，0 失败，构建成功。
- 发布整理已把最终真机 harness 的 Session/滚动通知适配器和非观察可见性状态移出
  `CoachView`；当前 `make check` 全部通过，测试基础设施不再突破 1,900 行 SwiftLint 门禁。
- 压力夹具覆盖 10,000 条消息、5,000 条业务记录和 1,000 个媒体引用。
- `make perf-check` 阻断 Root 无界查询、渲染路径同步图片 I/O、启动 repair、字符串 revision、
  全局动画抑制和长流正文回退到即时布局。
- Release Simulator 10 轮/40 次 Tab 预检 p50 59 ms、p95 61 ms、max 63 ms；只用于路径预检，
  不替代真机结果。

## 5. 性能实现上的踩坑

### 5.1 把“保留 View”误解成“零处理缓存”

TabView 可以保留导航栈和状态，但重新可见仍会触发 SwiftUI diff、布局、文本测量和必要的动态属性
读取。正确目标不是让切换路径绝对零工作，而是让工作有界、只与可见内容相关并低于预算。

### 5.2 用关闭动画伪装性能

全局 `UIView.setAnimationsEnabled(false)` 让 Simulator 看起来像“单帧替换”，但真机出现选中反馈
延迟、样式异常和交互不自然，而且 Coach 的真实布局成本没有减少。该实现已删除；今后不得用视觉
抑制代替 workload reduction。

### 5.3 第一次长流分块只完成了一半

稳定文本块消除了全文字符串反复构造，但内层即时 `VStack` 仍会在尾块变化时测量所有冻结块。
只有继续改为 `LazyVStack`、固定纵向尺寸并把尾块收紧到 256 字符，CPU 才真正下降 84.2%。

### 5.4 只看消息数量，忽略单条消息的结构复杂度

故障 Session 只有 12 条消息。真正成本是一张十项饮食卡同时创建几十个 `TextField`。性能排查必须
同时记录“行数”和“每行控件/布局复杂度”，不能把“大 Session”简单等价为“消息很多”。

### 5.5 缓存边界一度表述错误

不能为所有 Session 预热，也不能缓存 SwiftData 模型对象。最终边界是：仅已经访问且真正进入可见
懒栈的消息写入有界纯值缓存；未打开 Session、未滚到的历史和未出现的记录卡不缓存。

### 5.6 `Task.yield()` 只能让路，不能消除工作

本轮多处用 `Task.yield()` 避开 selection/导航提交帧，这是调度手段，不是根因修复。只有同时把
查询改为有界、派生搬到后台、控件改为按需创建时才有实际收益；单独堆 `yield` 会把卡顿延后而不是
消除。

### 5.7 Session 页面身份仍然过重

`.id(activeSessionID)` 能保证分页状态在 Session 切换时重置，但代价是整个聊天页面身份失效。
当前纯值缓存只能复用解析结果，不能复用已访问 Session 的 ScrollView/View 生命周期。60 次真机
样本 p95 `354.505 ms` 说明这一边界仍需重新设计；本轮按要求停止，没有继续修复。

## 6. 自动化测试踩坑

### 6.1 没有先复盘既有失败产物

`profile-device-tab-loop.sh` 依赖物理设备 XCUITest Runner。前一天已经留下
`XCTRunnerDaemonSession` 初始化断言崩溃，仍再次运行，浪费了构建和等待时间。以后任何重跑前先
检查上一份 manifest、xcresult 和 crash log，已知基础设施故障不得当作新尝试重复踩坑。

### 6.2 XCUITest Runner 与 App 失败必须分开

本次 `SomaUITests-Runner` 在建立连接前以 code 74 退出，栈位于
`+[XCTRunnerDaemonSession sharedSession]`。这是测试运行器故障，不是 Soma 闪退，也不能产生任何
性能结论。报告和脚本必须把 runner failure、App crash、trace invalid 和 budget failure 分开。

### 6.3 build setting 不等于测试进程环境变量

Simulator 预检尝试通过 `TEST_RUNNER_...` build setting 跳过 profiler-ready 等待，但变量没有按预期
进入测试进程，导致测试停在等待通知；`xcodebuild -quiet` 又隐藏了进度。环境传递必须通过经过验证的
xctestrun/launchEnvironment 路径，并为等待增加明确日志和截止时间。

### 6.4 安装、启动、解锁和交互验收是四件事

`make install-device` 成功只能证明签名和安装；锁屏可能阻止启动，启动成功也不证明触摸交互通过。
脚本后来增加 CoreDevice 锁屏预检，锁定时在编译和 Instruments 之前退出，避免三分钟空等和空
trace。

### 6.5 设备 ID 体系容易混用

`xctrace`/Xcode destination 使用设备 UDID，部分 `devicectl` 输出同时包含 CoreDevice UUID。
脚本必须在入口解析并记录所用 ID，不能靠人工从不同命令复制后假设它们等价。

### 6.6 按进程名附着存在发现竞态

`devicectl launch` 返回时 App 已启动，但 xctrace 的按名称进程发现可能尚未刷新，连续出现
`Cannot find process matching name: Soma`。最终改为从 CoreDevice 精确读取本次 PID，再让 xctrace
按 PID 附着；分析阶段仍按 `Soma` 进程名过滤。

### 6.7 录制次数不等于交互样本数

`SOMA_PROFILE_RUNS` 是独立 Trace 数，`SOMA_PROFILE_INTERACTION_ROUNDS` 才是同一 Trace 内的交互
轮数。Tab 30 轮必须得到恰好 120 个完整 interval、每个目标 30 个；Session 30 轮必须得到恰好
60 个。缺 begin/end、被中断或多一个样本都应失败，不能拿录制时长代替样本数。

### 6.8 Trace 文件存在不等于 Trace 有效

Simulator xctrace 曾产生几十 KB 空壳并不退出。正式脚本必须有总超时、检查 TOC、检查 `<run>` 与
`<data>`、导出目标 schema，并在 manifest 中记录 `record_failed`、`timed_out`、`invalid_trace`、
`analysis_failed` 等不同状态。

### 6.9 自动化驱动本身会污染被测路径

XCUITest 查询长聊天的完整 Accessibility 子树会让主线程构造大量语义文本。旧脚本后来改为预先解析
坐标并只注入点击；最终真机 harness 更进一步，通过显式环境变量在 App 内驱动 selection，同时用
内存虚构数据隔离个人数据。

代价也必须说明：最终 Tab 数据测量的是“程序写入 selection 到内容可见”，不包含真实手指触摸识别；
Session 数据测量的是“选择 Session 到内容可见”，不包含打开抽屉和点击行的耗时。两者适合稳定比较
App 渲染路径，但不能替代最终人工触摸手感验收。

### 6.10 分析器信息仍不够

Session 分析器当前只输出总体分布，没有按“小 Session→大 Session / 大→小”拆分。它能证明 p95
失败，却不能直接指出哪一方向贡献 350 ms 长尾。下轮应先补匿名方向标签和 per-target 分布，再决定
缓存或页面身份方案，避免再次凭感觉改代码。

### 6.11 性能 harness 侵入了已经过长的生产 View

为了绕过真机 XCUITest Runner，最终 harness 通过 `NotificationCenter` 把 Session/滚动指令接入
`CoachView`。它成功得到真机数据，但也让该文件增长到 1,922 行并触发 1,900 行 SwiftLint 门禁。
这说明“测试驱动器可用”不等于“基础设施边界正确”：下轮应把性能入口收敛到独立 adapter/host，
不能继续把测试分支堆进聊天主 View。

## 7. 建议保留的测试结构

1. 静态层：`make perf-check`，阻断已知反模式。
2. 合成层：10,000 消息、5,000 记录、1,000 媒体引用和长流 200 段虚构夹具。
3. Simulator 层：功能、主题、滚动、分页、长按和路径预检，不承担 120 Hz 最终结论。
4. 真机层：Release + Time Profiler/Animation Hitches/SwiftUI/Allocations，同一交互至少 30 次。
5. 人工层：真实触摸、键盘、长按重命名、媒体、长时间流式后的热感与手感。

每次真机录制都应保存 manifest、trace TOC、导出 XML、机器可读 JSON 和失败原因。自动化脚本只复用
一套 `profile-device-performance.sh` 采集/分析核心；交互驱动可以替换，但不应复制另一套预算和
manifest 逻辑。

## 8. 未完成项与下轮起点

| 优先级 | 未完成项 | 当前证据 | 下轮第一步 |
| --- | --- | --- | --- |
| P0 | Session 切换 p95 超预算 | 60/60，p95 `354.505 ms` | 先按匿名方向拆分 signpost；审计 `.id(activeSessionID)` 与已访问 Session 生命周期 |
| P1 | SwiftUI `body` 热点未做最终真机门禁 | Simulator 不足以定论 | Release 真机 SwiftUI Instrument，同一路径 30 轮 |
| P1 | 全路径滚动 hitch | 只完成长流场景 0 hitch | 教练/训练/进展/设置分别录 Animation Hitches |
| P1 | 内存增长与泄漏 | Simulator RSS 无单调增长但不等价 | 真机 Allocations + 10 轮跨 Tab/Session/媒体 |
| P1 | 冷启动严格 before/after | after 只有 27 个完整样本 | 同间隔补齐独立 30 次，不与旧批次混算 |
| P1 | 真机完整触摸验收 | 自动化只覆盖渲染区间 | 真实个人 Session 往返、长按、单字段编辑和长流后滚动 |
| P2 | 测试基础设施收口 | XCUITest 入口在当前工具链不可靠 | 默认改用 PID 附着 harness；旧 runner 入口降级或明确禁用 |
| 已完成 | 测试基础设施收口 | Session/滚动性能 adapter 已移出 `CoachView`，`make check` 通过 | 保持独立 adapter，不再向聊天主 View 堆叠测试入口 |

本轮不继续修复上述项目，也不把它们写成已通过。下一轮应从 Session p95 失败的同一 Trace 和明确
预算开始，而不是重新做一轮无边界代码扫描。
