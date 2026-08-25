# ADR 0032：以匿名设备身份提供可选远程 Agent 执行

- 状态：已采纳
- 日期：2026-07-31
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0001](0001-local-first-dual-data-spaces.md) 的“不建设后端”绝对边界
  - [ADR 0003](0003-native-streaming-react-tool-calling.md) 的 ReAct 只由 App 编排
  - [ADR 0008](0008-app-scoped-conversation-processing.md) 的 App 进程是唯一执行位置
- 后续替代：[ADR 0037](0037-backend-transparent-streaming-and-notification-wake.md) 将前台正常路径改为通知驱动流式事件，分页补拉仅用于恢复
- 上游依据：[持久 Agent Job、事件流与 Live Activities 调研](../../../research/2026-07-31-durable-agent-jobs-live-activities.md)
- 下游落地：[Agent Job 与远程执行协议](../../../engineering/agent-job-protocol.md)
- 关联：[PRD 011](../prd/011-durable-agent-jobs-remote-continuity.md)

## 背景

本地持久 Job 可以消除页面耦合并在回前台后恢复，但 App 被 iOS 挂起或终止时无法继续运行
SSE 和 ReAct。网络不稳定还要求服务器在接受 Job 后成为远程执行与事件的可靠事实来源。

完整账户和云端业务数据库会破坏 Soma 的个人、本地优先定位；服务器也无法直接访问本地
SwiftData、HealthKit 和 ThisDeviceOnly Keychain。

## 决策

1. 定义 `AgentExecutionBackend`，本地与远程实现共享 submit、events、cancel 和 tool result
   语义。View 与业务模型不感知执行位置。
2. 远程持续执行默认关闭，由用户在 AI 服务设置中明确开启；单次任务可以选择仅本机。
3. 不建立用户名、密码或跨设备业务账户。每次安装生成匿名设备 ID 和不可导出签名私钥，
   服务端只保存公钥、推送 token 和任务授权。
4. 参考服务器架构采用：
   - TypeScript HTTP/SSE API；
   - PostgreSQL 保存设备、Job、Event、幂等键和事务 Outbox；
   - 独立 Worker 原子领取 Job；
   - 对象存储保存临时媒体；
   - APNs Provider 更新通知和 Live Activity。
5. PostgreSQL 是远程 Job/Event 的事实来源；Redis 或内存队列不能成为正确性依赖。
6. 用户自带 Provider API Key 不上传服务器。远程任务只使用 Soma 管理的 Provider 凭据与
   配额；BYOK 任务继续本地执行。
7. 服务器只接收当前 Job 明确需要的输入、媒体和上下文快照，不镜像完整身体业务数据库。
8. 远程安全 Tool 可由 Worker 执行；本地数据查询、mutation、HealthKit 和沙盒媒体 Tool
   形成持久 `tool_request`，Job 进入 `waitingForDevice`。
9. 设备执行本地 Tool 前重新验证固定 Schema、Turn、取消状态和权限，随后用稳定
   `toolCallID` 返回幂等结果。
10. 网络采用至少一次投递：
    - `clientJobID` 去重提交；
    - Event sequence 支持断线补拉；
    - Tool Result 和取消请求幂等；
    - 本地 mutation Receipt 保证副作用不重复。
11. 远程内容终态确认后 24 小时内删除，最长保留 7 天；非内容安全元数据最长 30 天。
12. 服务器不成为训练、饮食、身体、健身房和个人媒体的长期事实来源。

## 未选择的方案

- 永远只在设备执行：无法解决 App 被挂起或终止后的持续运行。
- 建立完整账户和云端身体数据库：超出当前用户目标并扩大隐私边界。
- 上传用户 BYOK：把设备 Keychain 秘密变成服务器长期秘密。
- 服务器假装执行本地 Tool：无法读取真实本地数据且会制造双重事实。
- 仅使用 Provider background response：多供应商不一致，且无法完成本地 Tool handoff。
- 以 Redis 队列作为唯一 Job 事实：事务创建、事件和幂等状态容易分裂。

## 结果

### 正向影响

- 纯远程步骤可以在 App 终止后继续。
- 不稳定网络可以通过 Outbox、幂等 ACK 和 Event cursor 恢复。
- 无人类账户与本地业务真值继续保留。
- 服务器技术栈与 iOS View、Tool 和 SwiftData 解耦。

### 成本与限制

- 需要 Soma 管理模型成本、滥用控制、App Attest/设备鉴权和 APNs 凭据。
- Job 遇到本地 Tool 时仍会等待设备，不能伪装为已完成。
- 服务器能看到任务明文才能调用模型；传输和静态加密不是端到端不可见。
- 卸载会失去匿名设备私钥；远程临时数据依赖最长 7 天 TTL 清除。

## 验证

- 相同 `clientJobID` 在 ACK 丢失和并发提交时只返回一个远程 Job。
- 错误设备、公钥签名重放、过期 token 和跨设备 Job 访问被拒绝。
- API/Worker 重启不丢 Job、Event 或等待中的 Tool Request。
- SSE 断线后按 sequence 完整补拉；重复 Tool Result 不重复副作用。
- 远程关闭、单次仅本机和服务故障均能降级。
- 内容日志扫描、对象存储 TTL、终态确认删除和设备撤销通过安全测试。
- 纯远程 Job 在 App Force Quit 后完成；本地 Tool Job 诚实进入等待并在设备返回后继续。

## 参考

- [PRD 011](../prd/011-durable-agent-jobs-remote-continuity.md)
- [OpenAI Webhook Events](https://platform.openai.com/docs/api-reference/webhook-events)
- [OpenAI API Data Controls](https://platform.openai.com/docs/models/default-usage-policies-by-endpoint)
- [Apple Remote Notification Server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)
