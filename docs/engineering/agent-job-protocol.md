# Agent Job 与远程执行协议

- 状态：已实现协议
- 协议版本：1
- 日期：2026-07-31
- 上游依据：
  - [ADR 0031](../archive/0.0.1/adr/0031-durable-agent-jobs-event-log-and-projections.md)
  - [ADR 0032](../archive/0.0.1/adr/0032-optional-remote-agent-execution.md)
  - [ADR 0033](../archive/0.0.1/adr/0033-live-activity-agent-job-projection.md)
  - [ADR 0037](../archive/0.0.1/adr/0037-backend-transparent-streaming-and-notification-wake.md)
  - [ADR 0045](../archive/0.0.3/adr/0045-llm-outage-staging-and-compensating-drain.md)
  - [ADR 0062](../archive/0.0.5/adr/0062-user-resumed-llm-interruption-barrier.md)
  - [ADR 0068](../archive/0.0.6/adr/0068-versioned-unified-agent-model-input.md)
  - [ADR 0092](../adr/0092-react-internal-retry-and-user-controlled-recovery.md)
- 关联：
  - [PRD 011](../archive/0.0.1/prd/011-durable-agent-jobs-remote-continuity.md)
  - [PRD 029](../archive/0.0.6/prd/029-unified-local-remote-agent-model-input.md)

本文固定 iOS 本地 Outbox、服务器 Job/Event、匿名设备鉴权、本地 Tool handoff、APNs 与
Live Activity 的协议。实现可以替换部署平台，但不能改变幂等、游标、隐私和真值边界。

## 系统拓扑

```text
iOS
  Local Turn + AgentJob + Outbox
        │ HTTPS / SSE
        ▼
API Service ─── PostgreSQL(Job/Event/Outbox)
        │                    │
        │                    ▼
        │                Agent Worker ── Model Provider
        │                    │
        ├── Object Storage ◀─┤
        │                    │ tool_request
        ▼                    ▼
APNs / ActivityKit       iOS Local Tool
```

PostgreSQL 是远程任务事实来源。SSE、APNs、`LISTEN/NOTIFY` 和 Live Activity 都是可重建传输
或投影；`NOTIFY` 只负责唤醒，丢失后仍以数据库 cursor 恢复。

## 一致性模型

- 本地发送：Turn、媒体引用、Job 与 Outbox item 原子保存。
- 网络请求：至少一次投递。
- 服务端提交：`deviceID + clientJobID` 唯一。
- Event：`serverJobID + sequence` 唯一，sequence 只增不减。
- Tool Request：`serverJobID + toolCallID` 唯一。
- 本地 mutation：`turnID + normalizedToolSignature` 由 Receipt 幂等。
- 产品效果：依靠稳定 ID 和幂等收敛为一次，不宣称传输恰好一次。

## 状态机

### 本地 Job

```text
localQueued
  → uploading
  → awaitingServerAck
  → remoteAccepted
  → syncing
  → completed | failed | cancelled | expired

localQueued
  → localRunning
  → waitingForForeground
  → localRunning | failed | cancelled

localQueued | localRunning
  → staged
  → localQueued | localRunning | failed | cancelled

localRunning | waitingForForeground
  → waitingForUser
  → localQueued | failed | cancelled
```

`staged` 表示 Job 已持久化但被队首恢复条件阻塞；它本身不可由 FIFO 自动领取。发送前发现缺少
凭据或执行位置时仍可暂存，避免丢失用户输入。模型执行开始后，瞬态故障只在 ReAct 模型步骤内部
执行三次 1/2/4 秒退避；错误一旦越过 Loop，本地与远程 Job 都进入 `waitingForUser`。App 启动、
回到前台、配置变化、网络恢复和定时器都不得释放；后续 Job 继续 staged 且不能越过队首，只有用户
重试或删除屏障才能继续。`waitingForNetwork` 仅保留旧数据兼容，不能由 runner 自动领取。
判定规则见 [ADR 0092](../adr/0092-react-internal-retry-and-user-controlled-recovery.md)。

远程 Worker 在单个 provider model-step 内也只使用同一组三次退避；直传视频失败时若已有关键帧，
在这组三次预算内切换媒体模式。Worker 发出 terminal error event 后，App 不得创建自动 fallback Job。

### 服务端 Job

```text
accepted
  → queued
  → running
  → waitingForDevice
  → running
  → completed | failed | cancelled | expired
```

只有上述边允许迁移。终态后的迟到请求返回当前终态，不得把 Job 改回运行。

## iOS 持久模型

### `AgentJob`

必要字段：

- `id`：本地稳定 `clientJobID`；
- `turnID`、`sessionID`、`dataSpaceID`；
- `executionMode`: local/remote；
- `state`、`activeAttemptID`；
- `serverJobID`；
- `provider/model/context` 发送时快照；
- `lastServerSequence`、`lastProjectedSequence`；
- `resumeReason`、`lastErrorCode`；
- `lastCompletedStep`、`loopCheckpointData`：本地 ReAct step 边界检查点；有检查点时
  中断恢复复用 `responseMessageID` 指向的同一条回复气泡，且不递增 `attemptNumber`；
- `createdAt/updatedAt`。

不得保存 API Key、Authorization 头或媒体 Base64。

### `AgentEvent`

- `id`、`jobID`、`attemptID`；
- `sequence`；
- `kind`: job/model/skill/tool/text/output/error；
- `phase`: started/updated/completed/failed/cancelled/suspended；
- 版本化 payload；
- `createdAt`。

服务器 Event 使用服务器 sequence；本地执行使用独立本地 sequence namespace。一个 Job 在选定
execution mode 后不同时运行两种 backend。

### `AgentConsumerCursor`

消费者至少包括 chat、trace、liveActivity、notification 和 remoteSync。读取不删除 Event。
Chat/Trace 可以把 cursor 实现为投影版本，而不是公开 UI 模型。

## 匿名设备身份

1. 首次启用远程持续执行时生成随机 `deviceID` 和 P-256 签名密钥。
2. 私钥使用不可导出 Keychain/Secure Enclave 能力保存；服务器只保存公钥。
3. 注册采用一次性 challenge，签名内容包含 challenge、deviceID、bundle ID、协议版本和时间。
4. 服务端验证签名与可选 App Attest 证明后签发短期 access token 和 rotation token。
5. 每个请求绑定 deviceID、时间、nonce 和 body digest，拒绝超时与重放。
6. APNs device token 与 ActivityKit token 只属于该匿名设备和具体环境。
7. 用户关闭远程执行时撤销 token；卸载后旧身份不可恢复，远程内容依赖 TTL 清除。

匿名身份不代表匿名网络。服务器和模型 Provider 仍可能看到 IP，必须在隐私说明中披露。

## HTTP API

所有响应包含 `protocolVersion`、`requestID` 和服务器时间。错误使用稳定 code 与用户可恢复
提示，不返回堆栈或业务内容。

### 设备

```text
POST /v1/device-registration-challenges
POST /v1/devices
POST /v1/device-tokens/refresh
DELETE /v1/device-data
```

`DELETE /v1/device-data` 撤销当前设备全部非终态 Job、删除可删除内容并安排对象存储清理。

### 媒体

```text
POST /v1/uploads
POST /v1/uploads/{uploadID}/complete
DELETE /v1/uploads/{uploadID}
```

- API 返回短期、限定大小和 content type 的上传 URL。
- iOS 从已落入沙盒的文件使用 background `URLSession` 上传。
- Worker 只读取已完成、digest 匹配并归属当前 device 的 upload。
- 不允许服务器根据用户 URL 抓取任意资源，避免 SSRF。
- 上传未关联 Job 或超过 TTL 时自动清除。

### Job

```text
POST /v1/agent-jobs
GET  /v1/agent-jobs/{serverJobID}
POST /v1/agent-jobs/{serverJobID}/cancel
POST /v1/agent-jobs/{serverJobID}/ack
```

提交请求包含：

- `clientJobID`、`turnID`、`sessionID`；
- `protocolVersion`；
- `modelInput: AgentModelInputEnvelope v2`：设备已组装的 system/history/current 消息、Skill
  元数据与内容快照、可选 `selectedSkillID`、仅当轮有效的 Tool 定义与名称、步数与时限；
- `mediaBindings[{id,uploadID}]` 与已完成 `uploadIDs`；消息只引用稳定 media ID，Provider 适配器
  在最后一刻换成短期下载 URL；
- `allowedDeviceTools` 名称清单及逐项对应的
  `allowedDeviceToolSchemas[{name,schemaVersion}]`；两份清单必须一一对应；
- 允许的固定远程 runtime Tool 只取 Envelope 当前暴露集合中的 `load_skill`；
- Live Activity preference。

Server 必须拒绝缺失 Envelope、媒体绑定不闭合、Tool 目录与执行边界不一致的提交。不存在旧
`text + contextSnapshot` 请求的兼容 Prompt。

请求头 `Idempotency-Key` 必须等于 `clientJobID`。相同 key 与相同 body digest 返回同一 Job；
相同 key 但不同 digest 返回 `idempotency_conflict`。

ACK 只确认设备已经持久化到某个 `throughSequence`，不是消费删除指令。

### Event

```text
GET /v1/agent-jobs/{serverJobID}/events?after={sequence}&limit={n}
GET /v1/agent-jobs/{serverJobID}/events/stream?after={sequence}
```

补拉响应：

```json
{
  "jobID": "server-job-id",
  "events": [
    {
      "id": "event-id",
      "sequence": 42,
      "kind": "tool",
      "phase": "completed",
      "payloadVersion": 1,
      "payload": {}
    }
  ],
  "nextSequence": 42,
  "terminal": false
}
```

SSE 是相同 Event 的实时视图。断线、App 重建或 sequence 缺口始终回到补拉端点。

前台正常路径在补齐 cursor 后持续消费 SSE；Event transaction 提交后通过 PostgreSQL
`NOTIFY` 唤醒 SSE 查询，不固定 sleep。`text/updated` payload 至少包含稳定 `itemID` 和
`delta`，`text/completed` 使用相同 `itemID` 结束本段；`output/completed` 保存完整 answer，
用于终态校正而不是再次拼接文字。

### 本地 Tool handoff

```text
POST /v1/agent-jobs/{serverJobID}/tool-results
```

`tool_request` Event 包含：

- `toolCallID`；
- 固定 `toolName`；
- `schemaVersion`（新请求为 v2；迁移期仍接受持久化 v1 调用）；
- 版本化 arguments；
- 是否 mutation；
- request expiry。

iOS 执行前检查：

- Job 与 Turn 仍存在且未取消；
- Tool 名称和 Schema 是 App 固定支持版本；
- 参数没有本地文件路径、密钥或越权数据空间；
- mutation 尚无成功 Receipt；
- 需要前台或用户授权的系统能力已经满足。

Tool Result 以 `toolCallID` 幂等。相同 ID 与相同 digest 返回首次结果；不同 digest 冲突。
结果只返回模型继续所需的最小字段。

## Worker 执行

1. API 在一个 PostgreSQL transaction 中创建 Job、accepted Event 和 Outbox row，并在 commit
   时通知等待中的 Worker 与 Event stream。
2. Worker 通过行锁/lease 原子领取 queued Job；健康路径由通知唤醒，低频 timeout 只恢复丢失
   通知、进程重启和过期 lease。
3. 每次 lease 包含 owner、epoch 和过期时间；失去 lease 的 Worker 不得继续追加 Event。
4. 模型每轮使用 Envelope 指定的原生流式 Tool Calling、`tool_choice=auto`、并行调用、步数与
   20/40/60 秒首增量、3/5/10 分钟活动预算。首段文本立即追加，后续文本按自然边界、48 字符
   阈值或 80ms 窗口合并；有完整 Tool Call 批次后才持久化。
5. Worker 先持久化 assistant 文本与全部原生 `tool_calls`。当 Envelope 明确暴露时，
   `load_skill` 使用其中 Skill 快照就地执行。业务 Tool 全部进入 `waitingForDevice`。
6. 并行 Tool Result 可任意顺序幂等到达；最后一个结果到达前保持等待，齐备后按原调用顺序重建
   `assistant.tool_calls` 与 `role=tool` 消息，再创建新 lease 继续。
7. 成功、失败、取消和过期在同一 transaction 写终态 Job 与 Event。
8. 崩溃恢复只读取已提交 Event 和 Tool Result，不重用进程内半成品。

服务端保存的是可继续的消息/Tool 历史，不保存或展示模型私有 thinking。

## Context 与 Provider

- 远程模式使用 Soma 管理的 Provider 凭据，凭据只在服务器 secret manager。
- 用户 BYOK 永不进入 Job payload、数据库、对象存储或日志。
- iOS 使用唯一 `AgentModelInputBuilder` 生成本地与远程模型输入。Server Provider 不保存任何
  Agent Prompt 文案，也不改写消息顺序、Skill 内容、Tool 描述或运行参数。
- `AgentTurnContextEnvelope v3` 在设备冻结原始 Turn 时间、Session businessDate、时区和
  `defaultOccurredAt`，并投影为条件业务上下文、最近十个完整 user-assistant 对、滚动替代摘要与
  确定性媒体选择，再进入 `AgentModelInputEnvelope v2`；较早成功写入不重复长 Tool observation。
- 会话压缩只在 ReAct Loop 前发生；小模型失败后回退标准模型，再失败使用确定性 digest。iOS 在
  本地和远程提交前都投影同样的压缩 Chat 事件，Worker 不重新压缩或改写 Prompt。
- `GET /v1/capabilities` 在媒体准备前返回远程 Provider 是否启用已验证直传视频；直传时只上传
  规范化 MP4，非直传模型只上传关键帧，同一 Provider 请求不同时包含视频和帧。
- Job 输入显式携带 `mediaMode=text|images|keyframes|direct_video` 与
  `requestAttempt=1|2`。直传首请求失败时 Server 不重复直传，而是返回带实际媒体模式和请求序号的
  失败 Event；设备随后才抽取并上传关键帧，以稳定的第二个 `clientJobID` 在同一设备 Attempt/Trace
  内完成唯一重试。第二次请求不得再由 Server 内部重试。
- 需要最新数据库事实时请求分页设备 Tool，不静默上传整个数据库。
- Provider request ID 可以进入非内容诊断；Authorization 和请求正文不得进入普通日志。
- Provider background mode 只可作为纯分析适配器，不能取代 Soma Job 和 Tool 协议。

## Live Activity 与 APNs

```text
PUT    /v1/agent-jobs/{serverJobID}/live-activity-token
DELETE /v1/agent-jobs/{serverJobID}/live-activity-token
```

- token 与 job/device/environment 绑定，加密存储。
- payload 只包含通用状态、操作数、队列数、时间戳和 schema version。
- sequence 或 timestamp 旧于已发送状态时不再推送。
- 终态发送最终 ContentState 后结束 Activity 并删除 token。
- APNs 失败不改变 Job；`Unregistered` 等永久错误立即删除 token。
- App 打开后以 Event Log 修正 Live Activity，不以推送为事实来源。

## 错误代码

至少固定：

| code | 含义 | 客户端行为 |
| --- | --- | --- |
| `offline` | 本地无网络 | 保持 Outbox |
| `unauthorized_device` | 设备身份失效 | 停止上传并重新注册 |
| `protocol_unsupported` | 协议不兼容 | 不远程执行，提示更新 |
| `idempotency_conflict` | 同 key 不同内容 | 停止并记录故障 |
| `upload_incomplete` | 媒体未完成 | 继续/重试上传 |
| `provider_unavailable` | 模型服务不可用 | 服务端退避重试或失败 |
| `waiting_for_device` | 需要本地 Tool | 同步 Tool Request |
| `tool_schema_unsupported` | App 不支持 Tool | 更新 App 或失败 |
| `job_cancelled` | 已取消 | 投影终态 |
| `job_expired` | 超过保留期 | 投影过期，可新建 Turn |

错误信息不得包含健康内容、模型请求正文、对象存储路径或凭据。

## 保留与清除

| 数据 | 正常清除 | 硬上限 |
| --- | --- | --- |
| Job 输入/Event 内容 | 终态且设备 ACK 后 24 小时内 | 创建后 7 天 |
| 上传媒体 | 终态后 24 小时内 | 上传后 7 天 |
| Tool Request/Result 内容 | 终态 ACK 后 24 小时内 | 创建后 7 天 |
| APNs/Activity token | 终态、失效或撤销立即删除 | Job 7 天 |
| 非内容安全元数据 | 不适用 | 30 天 |

删除任务使用事务 tombstone + 对象存储异步清理。数据库行删除成功但媒体清理失败时继续重试；
清理日志只包含对象 ID 和错误类别。

## 可观测性

服务器允许记录：

- request/job/event ID；
- 状态、耗时、重试数、错误类别；
- Provider、模型 ID 和 Token 用量；
- payload 字节数与媒体类型。

禁止记录：

- 用户原文、健康上下文和 Tool arguments/results；
- 上传 URL、对象存储签名、Authorization；
- APNs/Activity token；
- 模型完整输入输出；
- IP 与健康内容拼接的长期分析日志。

问题诊断需要内容时必须由用户在设备上主动导出经过脱敏的单个 Job 诊断包。

## 测试合同

### iOS 单元与集成

- 本地事务、Outbox、状态机、cursor、Event reducer；
- App 重启、后台 lease、重复 ACK、取消竞态；
- Tool Schema、Receipt、跨数据空间和 projection；
- SSE block 解码、远端 text delta 持久重放和终态不重复拼接。
- 自定义 Prompt/Skill、消息角色、Tool 目录、初始集合、步数与时限的远程提交对照。

### 服务端

- API transaction、Worker lease/epoch、进程崩溃恢复；
- 重复 submit、重复 Tool Result、Event gap、取消/完成竞态；
- Provider 原生流、文本 chunk 顺序，以及 Job/Event/Tool Result 即时唤醒；
- runtime Skill 不产生设备请求；并行 Tool 全部持久化、结果齐备后才续跑；
- 错误设备、签名重放、越权 Job、上传 digest/大小/type；
- TTL、终态 ACK、对象清理与内容日志扫描。

### 端到端

- 无网发送后恢复；
- ACK 返回前断网；
- SSE 任意 sequence 断开；
- Wi-Fi/蜂窝切换；
- App Home、锁屏、系统挂起和 Force Quit；
- 纯远程完成；
- 等待本地 Tool 后恢复；
- APNs 丢失、重复、乱序与 token 失效；
- 关闭远程执行、主动清除与 7 天过期。
