# ADR 0016：Turn、Attempt 与足迹成功投影

- 状态：部分已替代
- 日期：2026-07-30
- 部分替代：
  - [ADR 0005](0005-trace-span-event-observability.md) 的“一条消息一条 Trace”和“不支持重试”
  - [ADR 0014](0014-agent-turn-ordered-event-cards.md) 的“一条用户消息仍对应一条 Trace”
  - [ADR 0015](0015-daily-conversation-session-lifecycle.md) 的同名约束
- 后续替代：
  - [ADR 0027](0027-required-ai-configuration-and-send-gate.md) 替代本地分析器 Attempt
  - [ADR 0048](../../0.0.3/adr/0048-loop-checkpoint-and-same-bubble-resume.md) 修订「中断后续跑等同新 Attempt」的展示语义

## 背景

失败重试要求复用同一条用户原始表达，同时保留每次失败的诊断证据。如果把重试实现为再次
发送消息，会重复用户气泡、媒体和足迹；如果覆盖旧 Trace，又会破坏可审查性。已经成功的
Tool 写入还可能在新 ReAct Loop 中再次执行。

## 决策

- 一次用户发送定义为稳定 Turn。`CoachMessage.turnID` 把该用户消息与所有 Agent Attempt
  消息关联起来。
- 一次处理尝试定义为 Attempt；Agent 回复消息保存递增 `attemptNumber`。
- 每个远程 Attempt 创建独立 `AgentTrace`，Trace 保存相同 `turnID` 与 Attempt 序号。
- 重试只新增 Agent Attempt，不新增用户消息；原始媒体从 `MediaAttachmentReference` 指向的
  App 沙盒文件恢复。
- 每个 Attempt 继续使用 ADR 0014 的有序 Event Cards，不覆盖此前 Attempt。
- Turn 的足迹资格由“存在至少一个成功 Attempt”确定，不新增另一份 Feed 数据和媒体所有权。
- 失败、取消和运行中的 Turn 留在聊天，但不进入足迹。
- 标准档未配置 API Key 时由 ADR 0027 在发送前阻止，不创建本地分析器 Attempt；已经进入
  处理的远程 Attempt 继续以同一状态规则参与足迹判断。

## 跨 Attempt 幂等

- 新增本地 `AgentMutationReceipt`，使用 `turnID + 规范化 Tool Call signature` 作为稳定键。
- 只有成功的 mutation Tool Call 写入回执；查询、Skill 和失败调用不写回执。
- 新 Attempt 再次遇到相同成功写入时返回首次结果，不重复执行本地 mutation。
- 回执只保存 Tool 结果和签名，不保存媒体 Base64、API Key 或 Authorization。
- 已成功 Tool 写入不因最终回复失败而回滚，也不会被 UI 描述为失败。

## 旧数据

- 启动修复按 Session 和时间顺序给旧消息建立 Turn：
  - 每条用户消息开始新 Turn；
  - 后续教练消息在下一条用户消息前归入该 Turn；
  - 已有 Trace 状态优先；旧本地回复只在没有失败证据时迁移为成功。
- 迁移不删除或复制消息、媒体和 Trace。

## 未选择的方案

- 重试时重新发送用户消息：会重复原始事实和足迹。
- 把旧 Trace 改回运行中：会丢失失败证据。
- 只在内存中跨 Attempt 去重：App 重启后会重复写入。
- 新建独立 Footprint 模型并复制媒体：产生双重所有权和同步漂移。

## 结果

- 一条用户表达可以拥有多次可审查尝试，但足迹最多出现一次。
- 当前“一条消息一条 Trace”调整为“一次远程 Attempt 一条 Trace”。
- 删除单条 Trace 不删除业务回执；诊断日志和业务幂等拥有不同生命周期。
