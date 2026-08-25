# 持久化 Agent 任务、事件流与 Live Activities 调研

- 日期：2026-07-31
- 状态：已转化为正式 PRD、ADR 与工程协议
- 适用范围：Soma 远程 Agent、后台恢复、聊天事件投影、通知与灵动岛
- 下游落地：
  - [PRD 011](../archive/0.0.1/prd/011-durable-agent-jobs-remote-continuity.md)
  - [ADR 0031](../archive/0.0.1/adr/0031-durable-agent-jobs-event-log-and-projections.md)
  - [ADR 0032](../archive/0.0.1/adr/0032-optional-remote-agent-execution.md)
  - [ADR 0033](../archive/0.0.1/adr/0033-live-activity-agent-job-projection.md)

## 结论

用户提出的“任务队列 → ReAct Executor → 事件队列 → UI 按游标消费”方向是正确的，但要把
架构可靠性与 iOS 后台执行权限分开：

1. **持久化任务与事件流值得做**：它能让 UI、ReAct、聊天记录、Trace、Live Activity 和通知
   解耦，支持页面切换、崩溃恢复、重试与多消费者投影。
2. **本机队列不能绕过 iOS 挂起**：任务存在 SwiftData 中不等于它正在执行。App 进程被挂起
   后，本机 Executor、SSE 和本地 Tool 都会停止。
3. **Live Activity 不是后台执行器**：它是系统管理的展示面。App 有运行时间时可以本地更新；
   App 被挂起或终止后，只能由服务器通过 ActivityKit Push 更新。
4. **真正持续执行需要服务器任务队列**：微信式体验依赖服务器保存任务和结果，再由 APNs
   通知设备。对于 Soma，这会触及本地 Tool、API Key、健康数据和无账户边界。
5. **正式方向采用双层可靠性**：本机持久任务与 Outbox 负责发送前可靠性、有限后台执行和
   恢复；可选 Soma Server 负责被接受后的持续执行、事件游标和远程 Live Activity 更新。
   本地 Tool 无法在设备挂起时越权执行，必须进入 `waitingForDevice`。

推荐架构：

```text
用户发送
  → 持久化 Turn + MediaReference + AgentJob(queued)
  → Local Outbox / AgentExecutionBackend
       ├─ Local Runner → 本地 ReAct / Tool
       └─ Soma Server → 远程 ReAct
                         ↕ waitingForDevice Tool handoff
  → 按 sequence 同步 AgentEvent
       ├─ ChatProjector
       ├─ TraceProjector
       ├─ LiveActivityProjector
       └─ NotificationProjector
```

本机模式的产品承诺应是：

> 短任务切后台后尽力完成；系统暂停前保存状态；返回 Soma 后自动继续。

本机模式不能承诺：

> App 被系统挂起或终止后，本地 ReAct 仍无限持续运行。

远程模式可以让纯远程步骤继续，但遇到 SwiftData、HealthKit 或沙盒媒体 Tool 时必须等待设备。

## 微信为什么看起来一直在线

微信是闭源产品，无法从公开资料确认每一项内部实现。以下判断是依据 iOS 平台约束和消息产品
的可观察行为作出的架构推断，不是对微信源码的声明。

### 普通文字、图片和语音消息

消息产品通常采用：

```text
发送方 App
  → 消息服务器持久化
  → 接收方离线邮箱 / 消息日志
  → APNs 通知
  → 接收方按同步游标拉取消息
```

用户按下“发送”后，客户端只需要在有限后台时间内把消息交给服务器。只要服务器已经接受，
之后的投递、重试、离线保存和通知都不依赖发送方 App 继续运行。

接收方 App 也不需要永久维持自己的 socket。Apple 的 APNs 与系统进程维持设备连接；服务器
有新消息时发送远程通知。用户打开 App 后，再从服务器同步权威消息状态。Apple 官方也以消息
服务作为远程通知的典型例子。

后台静默推送只是一种“有新数据，请刷新”的提示，不是可靠消息队列。Apple 明确说明它可能
延迟、合并、限流或不投递。因此消息本体仍必须保存在服务器，不能只存在推送 payload 中。

### 微信语音和视频通话

真实 VoIP 可以使用 PushKit 唤醒或启动 App，并必须通过 CallKit 呈现系统通话体验。通话建立
后，音频会话和对应后台模式支持持续通信。

PushKit 不能用于普通 Agent 任务。Apple 明确把它限制在真实 VoIP、文件提供者等专用场景，
现代 iOS 还要求 VoIP Push 对接 CallKit。

### 对 Soma 的启示

微信体验的核心不是“客户端队列永不停止”，而是：

- 服务器是任务和消息事实来源；
- APNs 是提醒设备来同步的通道；
- 客户端 UI 是服务器事件日志的投影；
- 专用后台能力只用于符合平台定义的场景。

## 视频软件为什么能继续

视频 App 看起来在后台继续工作，实际依赖多个专用系统机制：

| 场景 | 真正继续工作的组件 | iOS 机制 | 能否用于 Agent |
| --- | --- | --- | --- |
| 后台听视频声音 | 系统音频与 App 播放会话 | Audio Background Mode | 不能冒用 |
| 小窗播放视频 | AVKit / AVFoundation 媒体管线 | Picture in Picture | 不能冒用 |
| 离线下载 | 系统网络守护进程 | Background URLSession Download | 只适合文件 |
| 后台上传视频 | 系统网络守护进程 | Background URLSession Upload from file | 只适合文件 |
| 视频通话 | 通话服务器、音频会话、CallKit | VoIP / Audio / PiP | 只适合真实通话 |

PiP 和后台音频允许的是媒体播放，不是任意 Swift 代码。后台 `URLSession` 可以让系统在 App
挂起或终止后传输文件，但不能在收到半截 SSE 后运行模型决策、执行本地 Tool，再发起下一轮
请求。

`BGProcessingTask` 也不是即时任务队列。它由系统选择运行时机，通常适合维护、数据处理和
延迟工作；用户刚发送一条聊天消息后，不能依赖它立即启动。

## 对“任务队列 + 事件游标”方案的判断

### 正确之处

当前 Soma 已经具备一部分基础：

- `ConversationProcessingService` 位于 App 生命周期，而不是 `CoachView`；
- Turn、Attempt、Trace、Tool Receipt 已有稳定 ID；
- Agent Event 会投影为聊天 Event Card；
- `CoachView` 通过 SwiftData `@Query` 读取持久化消息；
- mutation Tool 已支持跨 Attempt 幂等。

但当前仍有明显耦合：

1. `submit` 返回成功时，用户消息和 Agent 任务尚未在同一个同步事务中持久化；
2. 在途任务只存在 `processingTask` 内存属性中；
3. ReAct messages、当前步骤和恢复状态主要存在内存；
4. 实时 UI 仍依赖 `ConversationProcessingService.liveEventRevision`；
5. Event Card 存在 `CoachMessage` 的编码数组中，不是独立、可顺序读取的事件日志；
6. `ConversationProcessingContext` 由 `CoachView` 临时拼装，App 启动或回前台时无法独立重建；
7. 系统终止后只能把运行中 Trace 标记失败，不能重新领取任务。

持久 Agent Job 可以解决这些问题。

### 不应该“消费后立即删除”

用户提出的游标是正确方向，但事件不能由聊天 UI 消费后直接删除，因为同一事件可能同时被：

- 聊天页面；
- Trace；
- Live Activity；
- 完成通知；
- 数据修复；
- 导出和问题诊断；
- App 重启后的重放。

建议分成两层：

1. **持久事件日志**：保存有业务意义的状态变化，作为可恢复事实；
2. **进程内实时总线**：传递高频文本增量，供当前 UI 低延迟显示。

每个持久消费者维护自己的 cursor，但读取不代表删除。任务结束后，可以在所有投影完成的前提
下压缩事件：

- token delta 不逐 token 落库；
- 把短时间内的文字增量合并成文本片段或阶段性快照；
- 保留 Tool、Skill、Attempt 状态和最终文本；
- 原始网络包不作为业务事件保存；
- Trace 按现有隐私规则保留必要诊断信息。

这与 Matrix 消息协议的 `next_batch` / `since` 模式类似：客户端用游标增量同步事件，但事件
事实仍由服务器持有，而不是被一个 UI 消费者删除。

## 建议的数据模型

### `AgentJob`

```text
AgentJob
  id
  turnID
  dataSpace
  state(queued / running / waitingForForeground / succeeded / failed / cancelled)
  activeAttemptID
  providerSnapshot
  modelSnapshot
  contextSnapshot
  nextEventSequence
  resumeReason
  createdAt / updatedAt
```

Job 只引用已经持久化的用户消息和 `MediaAttachmentReference`，不复制原始媒体或 API Key。
Provider 与 model 可以保存发送时快照；API Key 仍只从 ThisDeviceOnly Keychain 读取。

### `AgentEvent`

```text
AgentEvent
  id
  jobID
  attemptID
  sequence
  kind(job / model / skill / tool / text / output / error)
  phase(started / updated / completed / failed / cancelled / suspended)
  payload
  createdAt
```

`jobID + sequence` 必须唯一。追加事件、更新 Job 状态和保存 Tool Receipt 需要明确事务边界，
避免“Tool 已写入但任务状态仍停在调用前”。

### `AgentConsumerCursor`

```text
AgentConsumerCursor
  consumerID(chat / trace / liveActivity / notification)
  jobID
  lastSequence
  updatedAt
```

第一版不一定需要把 cursor 做成公开 SwiftData 模型。Chat 和 Trace 可以在事件追加时同步生成
物化投影；Live Activity 和通知保留轻量 cursor 即可。

## 执行模型

### 提交

用户发送后，先完成一个持久化事务：

1. 把媒体复制到 Soma 沙盒；
2. 创建用户 `CoachMessage` 和稳定 Turn；
3. 保存发送时上下文快照；
4. 创建 `AgentJob(state: queued)`；
5. 保存成功后才清空输入框和附件；
6. 唤醒 `AgentJobRunner`。

这能消除当前“UI 已清空，但 Task 还没来得及持久化用户消息”的窗口。

### 领取与执行

`AgentJobRunner` 由 App 根层持有，但不直接依赖聊天 View：

1. 只领取 `queued` Job；
2. 创建新 Attempt，并把 Job 原子更新为 `running`；
3. 取得有限 `BackgroundExecutionLease`；
4. 执行 ReAct；
5. 把有意义的阶段追加为 `AgentEvent`；
6. Tool mutation 继续使用 `AgentMutationReceipt`；
7. 成功、失败、取消或后台时间用尽时保存终态并释放租约。

第一版保持全局串行执行。持久队列不等于需要并发运行多个 Agent；串行可以继续保护对话顺序、
本地 ModelContext 和 Tool 写入语义。以后即使允许连续发送，也应按 Conversation Session
保持 FIFO。

### 暂停与恢复

不尝试恢复一条已经断开的 SSE：

1. 后台时间到期前把当前 Attempt 结束为 `suspended`；
2. Job 进入 `waitingForForeground`；
3. 保留已经完成的 Event 和 Tool Receipt；
4. App 回到前台后创建新 Attempt；
5. 新 Attempt 从用户原文和持久媒体重新运行；
6. 已成功写入由 Receipt 返回原结果，不重复执行。

如果 Job 仍处于正常 `running` 且后台租约没有到期，回前台不能再创建第二个 Attempt。

### UI 投影

聊天 UI 不需要自己轮询并删除队列。更适合：

- `@Query` 读取 `CoachMessage` 和 `AgentJob` 物化状态；
- Job Runner 追加事件时由 `ChatProjector` 更新同一个 Agent Message；
- 当前 App 内的高频文字增量通过 `AsyncStream` 直达 UI；
- 定时或遇到 Tool/Span 边界时保存合并后的部分文本；
- 页面重建后从持久投影恢复，再接上实时总线。

这样 UI 消失、Tab 切换或 View 重建都不影响执行，UI 也不拥有任务生命周期。

## 能否真正切后台一直运行

### 方案 A：本机持久队列

能力：

- App 内任意页面切换不中断；
- 进入后台后，在系统授予的有限时间内继续；
- 被挂起前保存“等待前台恢复”；
- 回前台或下次打开 App 后自动继续；
- 不引入服务器和账户；
- 本地 Tool、数据库和 API Key 边界保持不变。

限制：

- App 被挂起后不执行；
- Force Quit 后不执行；
- Live Activity 无法在没有本地运行时间时继续获得新状态；
- 完成时间超过后台租约时，只能等用户回来。

这是所有模式都必须先完成的设备基础，但不是持续执行的最终上限。

### 方案 B：模型供应商后台任务

OpenAI Responses API 已提供 background response、状态轮询和完成 webhook。这说明“提交任务，
稍后读取结果”的服务端模式是成熟做法。

它只能覆盖部分 Soma 场景：

- 供应商替 App 完成一次长模型推理；
- App 回来后按 response ID 读取结果；
- 若有自己的服务器，可以接 webhook 并发送 APNs。

它不能直接接管当前多供应商本地 ReAct：

- 不是所有 OpenAI-compatible Provider 都支持同一后台协议；
- 自定义 function tool 仍需要客户端返回本地 Tool 结果；
- webhook 需要一个公网服务器，不能直接回调 iPhone；
- OpenAI background mode 会为了轮询暂存响应，不兼容 Zero Data Retention；
- 本地训练记录仍要等 App 恢复后才能审查和写入。

它更适合“纯分析、无中间本地 Tool”的长任务，例如一次视频复盘或计划草案，不适合作为所有
聊天消息的统一基础。

### 方案 C：Soma 服务器任务队列

App 被挂起或终止后仍持续执行、持续更新灵动岛并最终通知时，任务事实必须放到服务器：

```text
iPhone 提交 AgentJob
  → Soma Server 执行并保存 Event Log
  → APNs / ActivityKit Push 更新状态
  → iPhone 按 cursor 同步事件
  → 本地投影与审查
```

这与消息系统、Temporal 等 durable execution 平台的思想一致：工作流历史存在长期运行的服务
中，Worker 中断后可以从事件历史恢复。

但它会改变 Soma 的产品定义：

- 需要远程设备身份、任务鉴权和撤销；
- 用户健康文本、媒体和上下文会进入 Soma Server；
- 用户自己的 Provider API Key 不能直接从设备 Keychain 安全地供服务器长期使用；
- 服务器无法读取本地 SwiftData 或可靠执行本地 Tool；
- 若把数据库也镜像到服务器，就不再是当前无账户、本地优先产品；
- 若服务器只生成 Tool Proposal，本地记录仍要等 App 恢复后才能真正写入。

因此，“真正后台 Agent”不是一个网络层小改动。本结论已由 PRD 011 和 ADR 0031—0027
明确授权为可选能力；本地业务数据仍不迁移为服务器事实。

## Live Activities 与灵动岛

### 可以做什么

Live Activity 很适合表达一个用户主动发起、持续一段时间的 Agent Job：

```text
已排队
  → 模型正在响应
  → 正在读取动作历史
  → 已完成 2 个操作
  → 正在整理回复
  → 已完成 / 等待返回 Soma
```

Apple HIG 把任务进度、健身活动和少量暂停/取消操作列为合适场景。Soma 已有 Widget Extension，
可以在同一 Extension 中增加 `ActivityConfiguration`。

建议呈现：

| 表面 | 内容 |
| --- | --- |
| 灵动岛紧凑态 | Soma 标记 + 当前阶段，不展示用户健康文本 |
| 灵动岛展开态 | 当前阶段、最近一至两个重要 Event、打开 Soma |
| 锁屏 | “Soma 正在处理”或“等待返回 Soma”，默认隐藏动作、体重、饮食等敏感内容 |
| 完成 | 更新为“已完成”，随后结束 Live Activity；按用户通知权限发送完成提醒 |

不要展示虚假的百分比。ReAct 可能在任意一轮结束，最多八轮不是完成度。可以展示阶段、已完成
Tool 数和当前状态。

一个 Job 只对应一个 Live Activity。如果未来允许多条消息排队，同一个 Live Activity 显示
“1 个处理中，2 个等待”，不要为每条队列消息占用一个灵动岛活动。

### 不能做什么

- Live Activity 不会让 `AgentJobRunner` 获得额外后台时间；
- Live Activity Extension 自己不能访问网络；
- 本地 App 被挂起后，不能因为灵动岛还显示就继续消费 SSE；
- 没有服务器时，ActivityKit Push 不存在；
- 不能把每个 token 或每个内部 Span 都高频推到灵动岛；
- 用户可能在系统设置中关闭 Live Activities，产品必须正常降级。

如果使用本机队列，Live Activity 状态必须诚实：

- 后台租约仍有效：`正在处理`；
- 租约到期、App 即将挂起：`等待返回 Soma 继续`，并设置合理 `staleDate`；
- 回前台恢复：`继续处理`；
- 完成：最终状态后结束。

### 是否每条消息都启动

不建议所有短文本消息无条件启动。快速开始又立即结束会造成灵动岛闪烁，也可能让用户关闭
整个 App 的 Live Activities。

建议：

1. 用户在设置中允许“在锁屏和灵动岛显示 Agent 任务”；
2. 视频分析、训练计划生成、批量优化等明确长任务自动启动；
3. 普通文本任务默认只在 App 内显示；
4. 后续如果真实数据证明普通消息也经常需要后台等待，再扩大范围；
5. 任何情况下都允许用户关闭 Live Activity，不影响 Job 本身。

由于本地 App 通常只能在前台启动 Live Activity，不能等用户已经切后台很久后再临时决定启动。
若未来采用服务器，可使用 push-to-start 和 ActivityKit Push 完成远程启动与更新。

## 产品体验判断

这套体验会明显更好，但提升主要来自“状态不会丢”和“用户知道发生了什么”，不是来自灵动岛
本身：

1. 用户发送后输入立即清空，因为 Turn 和 Job 已经持久化；
2. 离开聊天页面不会影响任务；
3. 切后台后，短任务继续完成；
4. 系统不再允许执行时，明确显示等待，而不是永久转圈或静默失败；
5. 回到 Soma 自动续跑，不要求用户理解重试；
6. 完成后用 Live Activity 或通知提醒；
7. 聊天、Trace、灵动岛读取同一份 Job/Event 事实，不会互相漂移。

最大的 UX 风险是把“灵动岛仍显示”误解为“Agent 仍在本机运行”。状态文案必须准确，不能用
持续旋转动画掩盖已经被系统暂停的任务。

## 推荐开发次序

以下只表达依赖和验证顺序。

### 0. 产品与架构决策

1. 新增 ADR，定义 `AgentJob`、`AgentEvent`、投影和恢复语义；
2. 修订 ADR 0008：App 生命周期持有 Executor，但不承诺系统挂起后仍执行；
3. 明确先完成本机持久队列，并通过统一 Backend 协议接入可选 Soma Server；
4. 明确 Live Activity 是投影，不是执行来源；
5. 定义锁屏健康信息的默认隐藏规则。

### 1. 持久化提交

1. 建立 `AgentJob`；
2. 用户消息、媒体引用和 Job 在清空输入框前持久化；
3. 把 `ConversationProcessingContext` 构建移出 `CoachView`；
4. App 启动时能够发现 queued 与 waiting Job。

验收门禁：发送被接受后即使立刻终止 App，用户消息和待执行 Job 仍存在。

### 2. Job Runner

1. 建立串行 `AgentJobRunner`；
2. 原子领取任务并创建 Attempt；
3. 接入 `BackgroundExecutionLease`；
4. 成功、失败、取消和到期路径统一释放；
5. 保留现有 Tool Receipt 幂等。

验收门禁：App 内页面切换、锁屏和回前台不会创建两个 Executor 或重复业务记录。

### 3. 事件日志与投影

1. 建立带单调 sequence 的 `AgentEvent`；
2. Chat、Trace 从同一事件源生成投影；
3. 高频文本使用内存总线与合并快照；
4. 投影消费者使用 cursor，不消费删除；
5. 终态后执行可验证的事件压缩。

验收门禁：页面销毁重建后事件顺序一致；任何 Tool 成功状态都能追溯到业务写入回执。

### 4. 自动暂停与恢复

1. 后台租约到期前进入 `waitingForForeground`；
2. 回前台创建新 Attempt；
3. App 重启时恢复待执行 Job；
4. 用户取消和普通前台错误不自动复活；
5. 已完成 Tool 在恢复后只返回首次结果。

验收门禁：后台中断不会永久显示运行中；恢复不会生成第二条训练记录。

### 5. Live Activity

1. 在现有 Widget Extension 增加 ActivityKit；
2. 建立 `LiveActivityProjector`；
3. 实现紧凑、最小、展开和锁屏状态；
4. 默认隐去敏感健康内容；
5. 支持完成、失败、等待恢复和用户关闭；
6. 无灵动岛、权限关闭和系统限制时正常降级。

验收门禁：Live Activity 状态与 Job 一致；App 被挂起时不谎称仍在执行；结束后及时清理。

### 6. 通知

1. 用户授权后发送本地完成通知；
2. Live Activity 已经清晰提示时避免重复提醒；
3. 点击通知或 Live Activity 深链到对应 Turn；
4. 通知内容默认不包含动作、体重、饮食或媒体描述。

### 7. 远程执行与设备 Tool handoff

1. 建立匿名设备身份、任务鉴权和幂等提交；
2. 先验证无本地 Tool 的纯远程任务；
3. 建立 `waitingForDevice`、固定 Tool Request 与幂等 Tool Result；
4. 接入 APNs 与 ActivityKit Push；
5. 落实健康数据、媒体、Provider 凭据和留存策略；
6. 保持无用户账户、本地业务真值和可关闭远程执行。

## 参考

### Apple 后台执行与消息

- [Choosing Background Strategies for Your App](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)
- [Extending your app’s background execution time](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)
- [Setting up a remote notification server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)
- [Pushing background updates to your App](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)
- [Responding to VoIP Notifications from PushKit](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit)

### Apple 媒体与 Live Activities

- [Configuring your app for media playback](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback)
- [Adopting Picture in Picture in a Custom Player](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-custom-player)
- [ActivityKit](https://developer.apple.com/documentation/activitykit/)
- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Starting and updating Live Activities with ActivityKit push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- [Human Interface Guidelines: Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)

### 类似架构

- [Matrix Client-Server Sync](https://spec.matrix.org/v1.13/client-server-api/)
- [Temporal Durable Execution](https://docs.temporal.io/)
- [OpenAI Webhook Events](https://platform.openai.com/docs/api-reference/webhook-events)
- [OpenAI API Data Controls](https://platform.openai.com/docs/models/default-usage-policies-by-endpoint)
