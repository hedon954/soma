# ADR 0045：LLM 失效时本地暂存并在恢复后补偿消费

- 状态：已采纳
- 日期：2026-08-05
- 维护者：Soma maintainers
- 部分替代：[ADR 0027](../../0.0.1/adr/0027-required-ai-configuration-and-send-gate.md) 的“无 Key 时不落盘并跳转设置”发送前门禁
- 后续替代：
  - [ADR 0062](../../0.0.5/adr/0062-user-resumed-llm-interruption-barrier.md) 将明确欠费从自动补偿中分离为人工恢复 FIFO 屏障
  - [ADR 0092](../../0.0.11/adr/0092-react-internal-retry-and-user-controlled-recovery.md) 将所有已越过 ReAct Loop 的失败改为人工恢复，删除网络、供应商、配置与计时器自动补偿
- 下游落地：[Agent Job 与远程执行协议](../../../engineering/agent-job-protocol.md)
- 关联：
  - [PRD 021](../prd/021-llm-staging-explicit-configuration-and-input-suggestions.md)
  - [ADR 0031](../../0.0.1/adr/0031-durable-agent-jobs-event-log-and-projections.md)

## 背景

[ADR 0027](../../0.0.1/adr/0027-required-ai-configuration-and-send-gate.md) 规定标准档 API Key 是发送前提：
没有 Key 时点击发送不创建任何事实，直接打开设置。这条决策解决的是“不要制造注定失败的
消息和伪真值”，在首次配置场景仍然正确。

但 Soma 的记录场景发生在训练现场。Key 过期、额度用尽、供应商 5xx 或临时限流都发生在
用户正在连续记录的时刻。此时把用户挡在配置页，等于让训练现场的记录窗口直接丢失——而
[ADR 0031](../../0.0.1/adr/0031-durable-agent-jobs-event-log-and-projections.md) 已经把发送、执行与 UI 投影
拆成持久 Job 与 Event，队列本身完全有能力承接这段延迟。

同样的问题出现在串行执行上：`isProcessing` 为真时发送键失效，用户必须等上一条回复完成
才能记录下一组。队列本来就是 FIFO，没有理由把排队压力转嫁给用户。

## 决策

1. 发送不再以“LLM 当前可用”为前提。用户消息、媒体引用、上下文快照与 `AgentJob` 仍在
   同一事务中持久化；事务成功后才清空输入区，事务失败则保留草稿和附件。
2. `AgentJob` 增加 `staged` 状态：已持久化、可运行，但当前没有可用的 LLM 执行位置。
   `staged` 属于可运行态，由既有 FIFO 领取逻辑消费，不需要第二套队列。
3. 失败分类由确定性分类器 `LLMOutageClassifier` 决定，且只有三种处置：
   - `retryNetwork`：传输层错误（`URLError` / `NSURLErrorDomain` / SDK 超时），
     沿用既有 `waitingForNetwork` 与短退避；
   - `stage`：缺少凭据、地址无效、鉴权失败（401/403）、限流（429）、
     服务端错误（5xx）与 408/409/425 等可恢复状态；
   - `fail`：请求本身非法（400/404/413/422）、模型明确不支持多模态、媒体无法解析等
     重试不会改变结果的错误，保留既有终态与手动重试。
4. 进入 `staged` 时写入一条 `staged` 语义 Event，并按 `2^n` 秒指数退避、上限 5 分钟设置
   `nextRetryAt`。缺少配置这类“等待用户操作”的原因不设退避，靠配置变更信号唤醒。
5. 补偿消费的触发点固定为：App 启动、回到前台、LLM 配置变更、上一条任务结束、
   退避计时到期。补偿按 `createdAt` 先进先出，并保持全局串行。
6. LLM 配置变更通过 `Notification.Name.llmConfigurationDidChange` 广播：保存 API Key、
   切换小模型启用状态与离开「LLM 配置」页时各发一次。逐字符编辑地址或模型不广播——
   用半截配置发起请求只会把 Job 推进无谓的退避。App 根层订阅后触发补偿，
   Service 不直接持有 View，View 也不编排队列。
7. 暂存不改变业务写入语义：同一 `turnID` 的 Tool 写入仍由 Receipt 幂等收敛为一次；
   暂存期间不产生任何解析结果、AI 观察或统计值。
8. UI 只呈现产品语义：消息显示“已暂存，恢复后自动继续”，输入区显示暂存条数与配置入口。
   不展示状态机名称、退避秒数或内部分类结果。
9. 首次配置引导保留：从未配置过标准档 Key 时，发送仍然提示去「LLM 配置」，
   区别是消息已经落盘暂存，而不是被丢弃。

## 未选择的方案

- 保持 ADR 0027 的硬门禁：配置正确性得到保证，但把供应商抖动的代价转嫁给训练现场。
- 无 Key 时用本地规则解析：会产生伪真值，违反 truth over completeness，
  与 ADR 0027 拒绝本地分析器的理由一致。
- 复用 `waitingForNetwork` 表达 LLM 失效：网络可达但供应商拒绝时提示“等待网络”是错误
  归因，用户会去检查 Wi-Fi 而不是去检查 Key 和额度。
- 为暂存新建独立 outbox 表：与既有 Job/Event 事实重复，投影、游标与恢复都要写两遍。
- 无限退避重试所有失败：非法请求会永久占用队列头并持续消耗额度。
- 让服务器代管暂存：暂存内容包含用户原始输入与媒体引用，属于身体业务数据，
  不能默认离开设备。

## 结果

### 正向影响

- 训练现场的记录不再被供应商状态阻塞；连续发送按 FIFO 排队而不是被拒绝。
- LLM 恢复后的补偿是自动的，用户不需要理解重试语义或逐条点击。
- 失败归因对用户可解释：网络问题、配置问题与请求问题走三条不同路径。
- 队列压力可见（暂存条数），不会静默堆积。

### 成本与限制

- 状态机新增一个状态与一类 Event，投影、迁移与测试都要覆盖。
- 长时间供应商故障会让暂存持续累积；Soma 只提供计数与手动清理，不自动丢弃用户记录。
- 暂存队列只在本机，清除个人数据会连同未消费消息一起清除。
- 本地暂存仍不能绕过 iOS 挂起：App 被终止时不执行，回到前台才继续。

## 验证

- 单元测试覆盖 `LLMOutageClassifier` 的三类处置与边界状态码（401/403/408/429/500/400/404）。
- 单元测试覆盖 `staged` 的合法与非法状态迁移，以及 `releaseStagedJobs` 只在服务可用时解锁。
- 无 Key 连续发送三条：三条 Job 全部落盘且为 `staged`，没有 Trace、没有业务记录。
- 配置有效 Key 后不重启 App：三条按 `createdAt` 顺序执行，Receipt 保证不重复写入。
- 供应商返回 429 后：Job 进入 `staged` 且 `nextRetryAt` 落在退避窗口内，上限不超过 5 分钟。
- 供应商返回 400：Job 进入 `failed` 并保留手动重试，不进入暂存循环。

## 参考

- [PRD 011](../../0.0.1/prd/011-durable-agent-jobs-remote-continuity.md)
- [PRD 021](../prd/021-llm-staging-explicit-configuration-and-input-suggestions.md)
- [ADR 0008](../../0.0.1/adr/0008-app-scoped-conversation-processing.md)
- [ADR 0031](../../0.0.1/adr/0031-durable-agent-jobs-event-log-and-projections.md)
- [ADR 0037](../../0.0.1/adr/0037-backend-transparent-streaming-and-notification-wake.md)
