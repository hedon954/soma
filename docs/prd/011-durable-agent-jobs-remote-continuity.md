# PRD 011：持久 Agent Job、可选远程执行与系统进度

- 状态：已实现；远端持续性以部署后的 Server 为前提
- 日期：2026-07-31
- 修订自：
  - [PRD 003](003-streaming-react-agent.md) 的设备内 ReAct 单一执行位置
  - [PRD 004](004-soma-current-product.md) 的无后台服务边界
  - [PRD 005](005-conversation-sessions-and-send-feedback.md) 的发送持久化与后台失败边界
  - [PRD 006](006-footprints-location-and-retry.md) 的前台重试边界
  - [PRD 007](007-data-export-backup-and-erasure.md) 的远程数据清除边界
- 后续修订：暂无
- 上游依据：
  - [持久 Agent Job、事件流与 Live Activities 调研](../research/2026-07-31-durable-agent-jobs-live-activities.md)
  - [BUG 0004](../bugs/0004-agent-background-stream-interruption.md)
  - [BUG 0005](../bugs/0005-remote-agent-streaming-latency-regression.md)
- 关联决策：
  - [ADR 0031](../adr/0031-durable-agent-jobs-event-log-and-projections.md)
  - [ADR 0032](../adr/0032-optional-remote-agent-execution.md)
  - [ADR 0033](../adr/0033-live-activity-agent-job-projection.md)
  - [ADR 0037](../adr/0037-backend-transparent-streaming-and-notification-wake.md)

## 背景

当前 Agent 依赖 App 进程内的 Swift `Task`、SSE 和本地 Tool。切换 Soma 内页面不会中断，
但进入后台后 iOS 只提供有限执行时间；App 被挂起或终止后，ReAct 无法继续。网络不稳定还会
产生“服务器是否收到请求”“事件是否丢失”“重试是否重复写入”等独立问题。

产品需要把用户发送、任务执行、事件事实和 UI 投影拆开，并为可选服务器执行保留正式边界。
本地队列负责发送前和设备恢复，服务器队列负责被接受后的持续执行；两者不能互相替代。

## 用户结果

1. 用户点击发送后，原文、媒体引用、Turn 和本地 Job 先持久化，随后输入区才清空。
2. 无网络时消息显示“等待网络”，恢复后自动投递，不要求重新发送。
3. 服务端已接受的任务即使 App 被挂起或终止，也能继续执行远程步骤。
4. SSE 或网络切换中断后，客户端从事件游标补齐，不重复卡片和业务写入。
5. 需要本地 Tool 时任务显示“等待打开 Soma 完成记录”，设备恢复后继续。
6. 聊天、Trace、灵动岛、锁屏和通知读取同一份 Job/Event 事实。
7. 用户可以关闭远程持续执行，退回完全本地、可恢复但不能无限后台运行的模式。
8. 引入远程队列不改变聊天表现：前台仍逐段显示文本与 Agent 事件，有事件立即唤醒，不等待
   固定轮询周期。

## 产品承诺

Soma 对任务的承诺是：

> 发送内容先在本地可靠保存；网络恢复后会继续投递；服务器接受后任务和事件不会因 App
> 生命周期丢失；本地 Tool 副作用保持幂等。

Soma 不承诺：

- 网络永远不断；
- APNs 或后台静默推送必达；
- 设备挂起时服务器可以读取或修改本地 SwiftData、HealthKit 和沙盒媒体；
- 分布式系统“恰好一次”执行。传输采用至少一次，业务效果通过幂等达到一次。

## 执行模式

### 本地可靠模式

- 始终可用，是远程模式的基础和降级路径。
- `AgentJob`、语义 Event、上下文快照和媒体引用保存在当前 SwiftData 数据空间。
- App 获得有限后台时间时继续；到期前进入 `waitingForForeground`。
- 回前台或重新打开后为同一 Turn 创建新 Attempt。
- 不续接半条 SSE 或半次 Tool Call；已成功 mutation 由 `AgentMutationReceipt` 去重。

### 远程持续模式

- 默认关闭；用户在设置中阅读数据流说明后主动开启。
- 不建立用户名、密码、社交身份或跨设备业务数据库。
- 每次安装使用匿名设备密钥和设备 ID 鉴权；该身份只服务任务、推送和删除。
- 服务器保存 Job、Event、临时输入和必要媒体，并运行远程 ReAct Worker。
- 用户自带 Provider API Key 继续只在设备 Keychain 使用，不上传 Soma Server。
- 远程执行使用 Soma 管理的 Provider 凭据和独立配额；BYOK 任务继续走本地执行。
- 服务器不是训练、饮食、身体和健身房记录的事实来源。

### 前台实时体验等价

- 本地 Provider 流与远端 Server Event 在 Service 层归一为相同 `AgentTraceEvent`，聊天 View
  不感知执行位置。
- 远端 Provider 产生首段文字后立即形成 Event；后续 token 只在自然边界、字符阈值或短窗口
  合并后持久化，避免逐 token 写数据库。
- Job 创建、Event 追加和设备 Tool Result 提交必须通知等待中的 Worker 或 SSE；正常路径不
  使用固定一秒或两秒轮询驱动进度。
- SSE 长连接只承担低延迟传输；初始连接、重连和缺口继续使用持久 cursor 补拉，因此切换
  网络不会以牺牲流式体验换取可靠性。
- ACK、Live Activity 和 APNs 都是异步投影，不阻塞聊天文字和事件卡片显示。

## 发送与网络状态

远程任务使用以下用户可见状态：

```text
等待网络
  → 正在上传
  → 已提交
  → 处理中
  → 等待设备工具（可选）
  → 正在同步结果
  → 已完成 / 已失败 / 已取消 / 已过期
```

- `clientJobID` 在本地创建并作为幂等键；提交超时后使用同一个 ID 重试。
- 只有收到服务端 ACK 才显示“已提交”，不能把本地入队描述为服务器已收到。
- 服务端 Event 带单调 `sequence`；SSE 只负责低延迟，断线后用 `afterSequence` 补拉。
- APNs 只提示设备同步，不承载完整消息、健康内容或唯一事实。
- 用户取消是幂等请求；取消与完成竞态以服务端首个终态事件为准。

## 远程 Tool 协作

- 纯远程分析、模型推理和不访问设备数据的步骤可持续执行。
- 提交时可以包含用户明确授权的最小上下文快照，例如当前目标、场馆摘要和动作 ID/名称。
- 读取最新本地数据、写入记录、访问 HealthKit 或本地媒体的 Tool 必须由设备执行。
- 服务端追加 `tool_request` 后进入 `waitingForDevice`，保存固定 Tool 名称、Schema 版本和参数。
- 设备恢复在线后再次校验 Tool Schema、用户 Turn 与权限，再执行并返回幂等 `tool_result`。
- mutation Tool 继续写本地 `AgentMutationReceipt`；服务端重复请求不得产生第二条记录。
- 用户在等待期间取消或删除原始 Turn 时，设备不得继续执行该 Tool。

## Live Activity 与通知

- Live Activity 是 Job 的只读投影，不是执行器，也不增加后台运行时间。
- 只为用户已允许且预计较长的任务启动；普通短文本不无条件启动。
- 灵动岛和锁屏默认只显示通用阶段、已完成操作数和队列数，不展示动作、体重、饮食或媒体。
- 不展示虚假百分比；ReAct 的剩余轮数不是完成度。
- 本地执行租约到期时显示“等待返回 Soma 继续”。
- 远程执行由服务器通过 ActivityKit Push 更新和结束；推送丢失时以 App 下次同步为准。
- 完成通知与 Live Activity 避免重复提醒，点击后深链到对应 Turn。

## 数据与隐私

### 最小远程数据

每个远程 Job 只允许包含：

- 用户本次发送的文字；
- 明确选中的压缩媒体或上传文件；
- 本次执行所需的最小上下文快照；
- 固定 Tool Schema 与等待执行的 Tool 请求；
- Job、Event、错误和计费所需的非密钥元数据；
- APNs 与 ActivityKit 的设备/活动 token。

禁止包含：

- 用户自带 Provider API Key；
- SwiftData 数据库文件、Keychain 内容或完整个人历史；
- 未选择的原始媒体；
- 原始位置坐标；
- 模型 thinking/reasoning；
- 业务内容进入普通服务器访问日志。

### 保留与删除

- Job 到达终态且设备确认同步后，内容和媒体在 24 小时内清除。
- 未完成、设备长期离线或未确认的 Job 最长保留 7 天，随后进入 `expired` 并清除内容。
- 只含 Job ID、状态、时间、错误类别和用量的非内容安全元数据最长保留 30 天。
- APNs/ActivityKit token 在失效、Job 结束或设备撤销后删除。
- 用户关闭远程执行时停止新任务并可请求删除当前设备全部远程 Job。
- 主动清除个人数据时先尽力取消并删除远程 Job，再清除本地空间；离线时本地清除不被阻止，
  但必须说明远程临时数据仍按最长 7 天自动过期。
- 远程 Job 不是备份事实。恢复到新安装时只恢复本地聊天和终态投影，不接管旧安装的在途 Job。

## 设置与降级

- “后台持续处理”位于 AI 教练服务设置，不出现在聊天主界面常驻。
- 开启前说明数据会先经过 Soma Server，再进入模型 Provider，并展示保留与删除规则。
- 用户可以为单次敏感任务选择“仅在本机处理”。
- 远程服务不可用、协议版本不支持或认证失效时：
  - 尚未被服务器接受的 Job 保留本地队列；
  - 用户可选择等待或转为新的本地 Attempt；
  - 已被接受的远程 Job 不得同时启动本地副本，避免双重 Tool 副作用。
- Live Activities、通知或推送被系统关闭时，聊天同步仍能独立工作。

## 明确不在范围

- 用户名、密码、社交账号或跨设备业务数据同步；
- 把 Soma Server 建成训练、饮食、身体和媒体的长期云数据库；
- 上传用户自带 Provider API Key；
- 在服务器上模拟或绕过本地固定 Tool；
- 依赖后台静默推送作为唯一事件投递；
- 使用 VoIP、音频、定位等不匹配用途的后台模式；
- 给所有短消息无条件启动 Live Activity。

## 验收

- 本地事务成功前输入框不清空；事务成功后立即 Force Quit，Turn 和待执行 Job 仍存在。
- 无网发送显示等待网络；网络恢复后只创建一个服务端 Job。
- 服务端已创建但 ACK 丢失时，重复提交相同 `clientJobID` 返回同一个 Job。
- SSE 在任意 sequence 断开后补拉得到相同有序事件，不丢失也不重复 Event Card。
- Local/Remote 在前台使用相同的文本、Tool、错误和完成投影；远端首段文字不等待完整回答，
  Job/Event/Tool Result 到达后不叠加固定轮询延迟。
- App 被系统终止后，纯远程任务继续并在重开时同步完成结果。
- 远程任务请求本地 mutation Tool 时准确进入等待；设备恢复后只写入一条业务记录。
- 取消、完成、过期和重复 Tool Result 的竞态都有确定终态。
- 远程关闭、Server 故障、Provider 故障和协议版本不兼容均可解释和恢复。
- Live Activity 与 Job 状态一致，默认不泄露健康文本，推送丢失后可由同步纠正。
- 终态确认、7 天硬上限、清除个人数据和 token 失效均触发可验证的远程删除。
- 单元、服务端集成、断网/重连、App 重启、真机锁屏、Force Quit、Wi-Fi/蜂窝切换和隐私验收
  全部通过。
