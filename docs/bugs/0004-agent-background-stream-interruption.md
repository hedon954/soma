# BUG 0004：App 进入后台后 Agent 流式执行中断

- 状态：已定位，修复方案已采纳，待实现
- 发现日期：2026-07-31
- 影响范围：远程 Agent 的 SSE、ReAct 多轮调用、本地 Tool 执行和最终回复
- 下游落地：
  - [PRD 011](../prd/011-durable-agent-jobs-remote-continuity.md)
  - [ADR 0031](../adr/0031-durable-agent-jobs-event-log-and-projections.md)

## 症状

用户发送消息后，如果按 Home、锁屏或切换到其他 App，远程 Agent 的流式输出停止，后续 Tool
和最终回复可能不再执行。重新进入 Soma 后，当前 Attempt 可能仍显示执行中，也可能在网络
超时后显示失败。

只在 Soma 内从“教练”切到“进展”不会复现。`ConversationProcessingService` 已由 App 根层
持有，这只解决了 SwiftUI View 生命周期问题，没有取得 iOS 后台执行时间。

## 根因

当前链路是：

```text
CoachView
  → ConversationProcessingService.processingTask
  → AIService.runAgent
  → SwiftOpenAI.startStreamedChat
  → URLSession.shared.bytes
  → SSE 增量
  → 本地 Tool
```

机制上有四个缺口：

1. `ConversationProcessingService` 使用普通 Swift `Task`，开始 Agent Attempt 时没有调用
   `UIApplication.beginBackgroundTask`。
2. `RootView` 收到 `.background` 时只触发 `DataManagementCoordinator` 自动备份；备份单独
   申请了后台执行时间，Agent 没有。
3. SwiftOpenAI 4.5.0 在 Apple 平台默认通过 `URLSession.shared.bytes(for:)` 读取 SSE。这是
   依赖 App 进程持续运行的数据流，不是由系统守护的后台文件上传或下载任务。
4. 一轮 ReAct 的 `messages`、当前步骤和工具结果主要保存在内存。App 被挂起后不能继续消费
   SSE 或执行本地 Tool；如果连接在此期间关闭，当前代码只能失败。App 被终止后，
   `DataIntegrityRepair.finalizeInterruptedAgentTraces` 会把运行中 Attempt 标记为失败，但
   不会自动恢复。

iOS 允许普通 App 在退到后台后运行很短的收尾代码，随后会挂起进程。Apple 要求需要完成的
前台任务在开始时申请有限的后台执行时间，并在到期处理器中停止或延后。这个时间由系统决定，
不能被当成无限后台运行能力。

因此，这不是给 `URLSession` 增加超时或重试次数就能解决的问题。即使网络连接还存在，进程
被挂起时也无法执行下一轮本地 Tool。

## 修复

修复分成三个连续闭环，并由
[ADR 0031](../adr/0031-durable-agent-jobs-event-log-and-projections.md) 修订
[ADR 0008](../adr/0008-app-scoped-conversation-processing.md) 的后台边界。

完整的持久任务、事件投影、类似系统与 Live Activity 评估见
[持久化 Agent 任务、事件流与 Live Activities 调研](../research/2026-07-31-durable-agent-jobs-live-activities.md)。

### 1. 有限后台续跑

在 `ConversationProcessingService` 接受 `submit` 或 `retry` 时、创建长任务之前，申请一个
名为 `SomaAgentTurn` 的后台执行租约：

1. 每次只允许一个有效租约，与当前在途 Attempt 一一对应；
2. Attempt 成功、失败或用户取消时立即结束租约；
3. 到期处理器先把当前 Attempt 标记为“后台时间用尽，可恢复”，保存 SwiftData，再取消网络
   Task 并结束租约；
4. `finishProcessing`、异常路径和到期路径共用幂等的释放方法，避免重复结束或泄漏；
5. 不等到 `scenePhase == .background` 才申请。Apple 明确建议在长任务开始前取得租约；
6. App 回到前台时不重新创建仍在正常执行的 Attempt。

UIKit 调用应隔离成可注入的 `BackgroundExecutionLease`，生产环境封装
`UIApplication.beginBackgroundTask`，测试使用 Fake，避免把系统状态散落到 Agent 编排中。

这个闭环可以让普通短消息在用户切后台后继续完成，但不能保证任意八轮 Agent 都在系统给定
窗口内结束。

### 2. 回前台自动恢复

不能把后台租约到期当成普通失败，也不能尝试续接已经断开的 SSE。第一版恢复使用现有
Turn/Attempt 与幂等能力：

1. 为用户 Turn 持久化 `pendingForegroundResume` 状态；
2. 后台时间用尽或 App 在后台发生可恢复网络中断时，结束当前 Attempt，保留已完成的 Event、
   Trace、媒体引用和 Tool 写入；
3. App 再次进入前台时，为同一 Turn 自动创建新的 Attempt；
4. 新 Attempt 从用户原文与本地媒体重新运行，不复用不完整的 assistant 文本或半截
   `tool_call`；
5. 已成功 mutation 继续由 `AgentMutationReceipt` 去重，因此重跑不会重复创建训练、饮食或
   身体记录；
6. 前台普通网络错误不自动无限重试，继续由用户点击重试；
7. 成功后清除待恢复状态；用户主动取消后同样清除，不能再次自动启动。

恢复入口不能继续由 `CoachView` 临时拼装上下文。应把当前 Session、数据空间、健身房、器械、
AI 配置和 `ModelContext` 的构建上移到 App/Services 边界，使 `RootView` 在 `.active` 时也能
安全恢复。

如果 App 在后台被系统终止，本地模式不会继续执行 Agent；但用户下次主动打开 Soma 后，可以
根据持久化状态创建新 Attempt。

### 3. 可选远程持续执行

[PRD 011](../prd/011-durable-agent-jobs-remote-continuity.md) 已授权通过统一
`AgentExecutionBackend` 增加可选服务器队列：

1. 本地 Outbox 以 `clientJobID` 幂等投递；
2. 服务器接受后保存 Job 与单调 Event sequence；
3. App 被终止后纯远程步骤继续执行；
4. 需要本地 Tool 时进入 `waitingForDevice`，不能越权写本地数据；
5. App 恢复后按 cursor 补齐事件并执行固定 Tool；
6. Live Activity 和通知只是投影，不能替代 Event Log。

这不是有限后台续跑的替代品。尚未到达服务器的请求仍依赖本地 Outbox，设备 Tool 仍依赖
本地恢复。

### 不采用

- **后台 `URLSession` 直接跑 SSE**：系统后台会话适合文件上传和下载，不提供多轮 SSE 消费
  后立即执行本地 Tool 的运行时。
- **`BGAppRefreshTask` / `BGProcessingTask`**：触发时间由系统决定，不适合用户刚发送消息后
  立即完成对话。
- **伪造音频、定位等 Background Mode**：与产品功能无关，违反平台用途和 Soma 的权限边界。
- **只增加网络重试**：无法解决进程被挂起，也可能在 Tool 已写入后造成重复 Attempt。

Apple 依据：

- [Extending your app’s background execution time](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)
- [Choosing Background Strategies for Your App](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)
- [Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- [URLSession](https://developer.apple.com/documentation/foundation/urlsession)

## 回归门禁

- 自动化测试或静态检查：
  - submit/retry 开始前只取得一个后台租约，所有终止路径只释放一次；
  - 到期处理器保存可恢复状态并取消在途 Task；
  - 回前台只为 `pendingForegroundResume` 的 Turn 创建一个新 Attempt；
  - 已执行 mutation 后恢复，`AgentMutationReceipt` 保证业务记录仍只有一份；
  - 用户主动取消、前台普通错误和已经成功的 Turn 不会自动重启；
  - 启动修复不再把“待前台恢复”误标为不可恢复失败。
- 手工验收：
  - 使用虚构训练文本发送延迟响应，分别按 Home、锁屏和切换其他 App；
  - 在首轮 SSE、Tool 已写入但最终回复未完成、第二轮 SSE 三个阶段切后台；
  - 在系统后台时间内完成时，回到 Soma 能看到完整结果且没有重复记录；
  - 后台时间耗尽时，回到 Soma 自动创建一个新 Attempt 并完成；
  - Wi-Fi/蜂窝切换、低电量模式和相机/媒体附件场景不产生永久“执行中”；
  - 用户主动取消后，回前台不会复活任务。
- 仍无法自动化的风险：
  - iOS 分配的后台时间受设备、系统压力和电量影响，不能承诺固定时长；
  - 不同 OpenAI-compatible Provider 对 SSE 断线的错误码和超时行为不同；
  - Force Quit 后系统不会替 App 继续执行本地 ReAct。

## 验证

本轮完成机制调查、正式 PRD/ADR 与协议设计，尚未修改运行时代码：

- 确认 `ConversationProcessingService` 为 App 根层对象，普通页面切换不会销毁 Task；
- 确认 `RootView` 进入后台时没有通知 Agent 处理服务；
- 确认现有 `beginBackgroundTask` 只用于自动备份；
- 确认 SwiftOpenAI 4.5.0 在 Apple 平台默认以 `URLSession.shared.bytes(for:)` 读取流；
- 确认当前启动修复只会把运行中 Trace 标记失败，不存在自动恢复队列；
- 固定本地 Outbox、远程 Job/Event、`waitingForDevice` 与 Live Activity 的验收边界；
- 具体 Provider 返回的 `URLError`、进入后台到中断的时间和系统剩余后台时间，待真机加入
  虚构请求诊断日志后记录。
