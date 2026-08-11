# ADR 0058：首增量截止时间与有界重试

- 状态：已采纳
- 日期：2026-08-11
- 维护者：Soma maintainers
- 部分替代：[ADR 0037](0037-backend-transparent-streaming-and-notification-wake.md) 中只约束固定轮询、不约束 Provider 首响应时限的边界
- 后续替代：暂无
- 上游依据：
  - [PRD 025](../prd/025-trusted-context-direct-video-and-reviewable-meals.md)
  - [BUG 0005](../bugs/0005-remote-agent-streaming-latency-regression.md)
  - [BUG 0012](../bugs/0012-direct-video-and-first-delta-timeout.md)

## 背景

流式请求可能已建立连接但长期没有文字或 Tool Call。连接级 180 秒 timeout 无法区分首响应慢、
流中断和本地准备慢，也无法及时恢复。

## 决策

1. 从实际 dispatch 开始计算 TTFT；首个非空文字或 Tool Call delta 算首增量。
2. 文字 8 秒、图片/关键帧 10 秒、直接视频 20 秒。每个 ReAct 模型步骤最多自动重试一次。
3. 首增量后使用 30 秒 idle watchdog 和 180 秒单步骤总时限。
4. timeout 取消底层 URLSession/fetch；Server 使用 AbortController。直传视频首响应失败时，唯一
   重试改用关键帧；其他模式按原路由重试。
5. 重试属于同一 Agent Attempt，使用独立 request span；完整 Tool Call 形成前不执行副作用。
6. Trace 分段记录准备、投影、上传、TTFT、流式与总耗时，并保存 budget、attempt 和 timeout phase。

## 未选择的方案

- 仅缩短连接 timeout：无法表达首增量和流 idle。
- 无限指数重试：增加模型成本并延迟用户恢复选择。

## 结果

### 正向影响

- 用户在可预测时间内看到首响应或明确恢复状态，慢点可归因到本地或 Provider。

### 成本与限制

- 高排队供应商可能在健康但慢时被取消；分媒体预算和单次重试控制这一取舍。

## 验证

- 虚拟时钟覆盖三档 TTFT、首 Tool delta、idle、total、取消和无重复写入。

## 参考

- [PRD 025](../prd/025-trusted-context-direct-video-and-reviewable-meals.md)
