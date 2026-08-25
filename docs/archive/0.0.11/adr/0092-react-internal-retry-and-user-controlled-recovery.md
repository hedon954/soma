# ADR 0092：三次 ReAct 内部退避与 Loop 外人工恢复

- 状态：已采纳
- 日期：2026-08-23
- 维护者：Soma maintainers
- 部分替代：[ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 的网络/供应商/配置自动补偿、每步最多一次重试，以及只把明确欠费设为人工屏障的范围
- 上游依据：[PRD 042](../prd/042-user-controlled-recovery-message-feedback-and-action-art.md)、[BUG 0029](../../../bugs/0029-visible-failure-keeps-retrying-and-stale-error.md)
- 下游落地：[Agent Job 与远程执行协议](../../../engineering/agent-job-protocol.md)

## 背景

瞬态网络和供应商故障需要短暂恢复能力，但当前实现把恢复分散在模型步骤、Job 失败分类、远程事件流、
前台恢复、配置通知和 retry task。错误一旦已经显示，外层自动恢复会制造额外请求，并让失败文案与
后来的成功结果同时留在聊天中。

## 决策

1. 仅本地 `consumeAgentStepWithRetry` 与远程 Worker 的同级 provider model-step 可以对瞬态模型
   步骤自动重试。前提是本次请求尚未产生可见文字或完整 Tool Call 增量，避免复制半截回复和副作用。
2. 每个模型步骤最多重试三次，退避为 1、2、4 秒；初始调用加三次重试最多四个 request attempt。
3. 可重试信号限定为连接/超时、408/409/425、非欠费 429 与 5xx。缺 Key、无效地址、401/403、
   明确欠费、请求非法和已产生可见增量不在 Loop 内重试。
4. 直接视频首次瞬态失败且尚无可见增量时，本地和远程均可在同一三次预算内切为关键帧；App 不再
   收到远程失败事件后另行提交第二个自动 fallback Job。远程直传任务在一次明确授权的提交中同时
   上传有界关键帧，供 Worker 在预算内切换；这些帧与原视频使用相同保留和清理边界。
5. 错误越过 ReAct Loop 后，无论本地还是远程，Job 进入 `waitingForUser` 或等价人工恢复状态。
   启动、回前台、网络恢复、配置通知与定时器都不得自动释放。
6. 用户点按失败卡右侧的重试图标时释放原 Job 并复用 `responseMessageID`。开始 Attempt 先删除旧 error、
   cancelled 和 running 投影，清除失败文案，只保留成功 step 与 checkpoint 文本。
7. 后续 Job 继续按 FIFO 暂存，不得越过人工屏障。

## 结果

- 瞬态故障仍有确定且有界的内部恢复机会；用户看到失败后不会再发生隐式成本或状态跳变。
- 三次退避增加最坏 7 秒内部等待；Trace 记录 request attempt 和退避序号用于回溯。
- `waitingForNetwork` 仅作为旧数据兼容状态存在，不能被 runner 自动领取，手动重试可以释放。
