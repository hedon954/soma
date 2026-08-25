# PRD 022：ReAct 可靠性与上下文感知

- 状态：已实现，部分修订；待真机验收
- 后续修订：
  - [PRD 024](../../0.0.4/prd/024-chat-agent-feedback-tool.md) 为工具组新增当前 Turn 产品反馈能力
  - [PRD 025](../../0.0.4/prd/025-trusted-context-direct-video-and-reviewable-meals.md) 收敛上下文、Tool Schema 与首增量恢复策略
  - [PRD 027](../../0.0.5/prd/027-reliable-efficient-react-and-in-context-review.md) 收敛 step 续跑、固定 Loop 时间、分层超时、按意图 Tool 与稳定 Prompt 前缀
  - [PRD 032](../../0.0.7/prd/032-default-full-tools-and-selected-skill-subset.md) 取消按信号预选工具组：未选 Skill 注册完整当前协议 Tool
- 日期：2026-08-05
- 修订自：
  - [PRD 004](../../0.0.1/prd/004-soma-current-product.md) 的 Agent 处理与本地摘要边界
  - [PRD 008](../../0.0.1/prd/008-coach-continuity-and-adaptive-models.md) 的会话投影与长上下文策略
  - [PRD 011](../../0.0.1/prd/011-durable-agent-jobs-remote-continuity.md) 的本地中断恢复语义
- 下游落地：
  - [ADR 0047](../adr/0047-deterministic-context-pack-and-cross-turn-facts.md)
  - [ADR 0048](../adr/0048-loop-checkpoint-and-same-bubble-resume.md)
  - [ADR 0049](../adr/0049-normalized-idempotency-and-business-dedup.md)
  - [ADR 0050](../adr/0050-per-turn-tool-group-exposure-and-parallel-calls.md)
- 关联决策：
  - [ADR 0047](../adr/0047-deterministic-context-pack-and-cross-turn-facts.md)
  - [ADR 0048](../adr/0048-loop-checkpoint-and-same-bubble-resume.md)
  - [ADR 0049](../adr/0049-normalized-idempotency-and-business-dedup.md)
  - [ADR 0050](../adr/0050-per-turn-tool-group-exposure-and-parallel-calls.md)

## 背景

本机 ReAct 在真实使用中暴露三类可靠性问题：

1. **上下文感知不足**：模型每轮只看到两行本地摘要和十轮纯文字，看不到近期训练趋势、
   计划进度、本会话已写入记录 ID，历史轮的工具结果也被丢弃。
2. **中断恢复差**：后台租约或进程中断后总是新建 Attempt 从 step 1 重跑；已持久化的
   tool span 账本没有用于续跑。
3. **去重脆弱**：幂等键依赖完整 JSON 字面量，同义字段或类型差异会绕过回执；跨轮重复
   描述缺少业务级识别。

同时，每 token 双滚动动画、历史视频重复抽帧、21 个工具 Schema 全量发送和串行
`tool_calls` 放大了延迟与供应商 prefill 成本。

## 用户结果

- 用户描述训练、饮食或趋势问题时，教练能基于本机确定性摘要与可查询聚合作答，
  而不是反复空查或猜。
- 处理被系统中断后，同一条回复气泡从中断步骤继续，已成功的工具写入不重复发生。
- 用户重复说同一组训练数据时，Agent 会提示疑似重复并给出既有记录 ID，而不是静默多写。
- 常见记录路径更短：更少工具 Schema、可并行写入、流式滚动不再卡顿。

## 产品规则

1. 本地摘要改为有预算的确定性上下文包（近 7/28 天训练、肌群组数、最近训练日、
   当前计划、进行中带练、饮食与体重趋势、本会话近期写入）。缺失字段保持不写。
2. `query_user_data` 支持时间范围与聚合（day/week/muscle_group/exercise ×
   sets/volume/calories/frequency）。
3. 历史投影保留最近十轮全文，并附加近期工具写入事实；十轮以外只保留确定性意图 digest。
4. 本地 ReAct 在每个 step 边界落检查点；中断后复用同一条 CoachMessage 续跑，
   不递增 `attemptNumber`。真正失败或用户手动重试才新开 Attempt。
5. 写工具幂等键使用规范化语义签名；回执走 pending → committed / failed。
6. 跨 Turn 业务键命中时返回「疑似重复 + 既有 ID」，不静默合并。
7. 每轮工具注册整轮固定，并行 `tool_calls`，本地仍顺序执行。按信号预选工具组由
   [PRD 032](../../0.0.7/prd/032-default-full-tools-and-selected-skill-subset.md) 替代为：未选 Skill 注册
   完整当前协议 Tool，选中 Skill 只注册绑定子集。

## 数据与隐私

- 新增：Job 检查点字段、视频抽帧缓存（`Library/Caches`）、MutationReceipt 状态字段。
- 不新增远程数据流；缓存与检查点留在设备。
- Trace metadata 继续观测 `cached_prompt_tokens`、`time_to_first_delta_ms`、
  `projection_ms`，不含媒体内容或密钥。

## 明确不在范围

- LLM 生成的滚动摘要。
- 静默跨轮合并业务记录。
- 改变远程 Job 协议或服务器事实来源。
- 为工具选择引入独立小模型路由器。

## 验收

- 同 session 连续两轮 system+tools 前缀在未展开工具组时保持字节稳定。
- 租约过期后同气泡续跑，已 committed 的 mutation 不重复写。
- `exercise` 与 `exercise_name` 等同义签名互相命中回执。
- 跨 Turn 相同深蹲组次返回疑似重复且只保留一条 WorkoutEntry。
- `make verify` 通过；真机对照首字耗时、投影耗时与缓存命中。
