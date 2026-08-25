# PRD 029：本地与远程 Agent 模型输入完全统一

- 状态：已实施；部署后端到端与真机授权文案待维护者确认
- 日期：2026-08-15
- 修订自：
  - [PRD 004](../../0.0.1/prd/004-soma-current-product.md) 的远程发送内容与当前产品隐私基线
  - [PRD 011](../../0.0.1/prd/011-durable-agent-jobs-remote-continuity.md) 的远程 ReAct、设备 Tool handoff 与临时内容边界
  - [PRD 025](../../0.0.4/prd/025-trusted-context-direct-video-and-reviewable-meals.md) 的本地/远程上下文等价要求
  - [PRD 027](../../0.0.5/prd/027-reliable-efficient-react-and-in-context-review.md) 的稳定 Prompt、按意图 Tool 暴露与并行调用要求
- 上游依据：[BUG 0018](../../../bugs/0018-remote-agent-model-input-divergence.md)
- 下游落地：[ADR 0068](../adr/0068-versioned-unified-agent-model-input.md)
- 后续修订：[PRD 030](030-agent-prompt-skill-context-and-tool-v3.md) 升级 Envelope、Skill 快照和 Tool v3 契约

## 背景

远程 Worker 曾自行构造一段简化 System Prompt，并把历史压成“最小上下文”字符串。它没有收到
设备当前保存的自定义 Prompt、完整 Skill 快照、原生历史消息与媒体绑定；运行时 Tool 被错误交给
设备，并行 `tool_calls` 只保留第一项。这让同一个用户 Turn 因执行位置不同而产生不同理解和副作用。

## 用户结果

用户选择本机执行或后台持续处理时，模型看到的有效输入必须相同。远程模式只改变任务在哪里继续，
不能改变 Soma 的身份、规则、上下文、Skills、Tool 能力、并行语义或恢复历史。

## 当前要求

1. iOS 是模型输入的唯一组装方。每次 Turn 生成版本化 `AgentModelInputEnvelope`，包含：
   - 完整 system、历史 user/assistant 与当前 user 消息序列；
   - 每条消息的稳定媒体 ID；
   - 当前有效 Skill 快照；
   - 固定 Tool 完整定义、初始暴露集合与 Schema 版本；
   - `tool_choice`、并行调用、ReAct 步数和 20/40/60 秒、3/5/10 分钟时限策略。
2. 本机 Provider 直接消费该 Envelope；远程 Client 原样编码同一 Envelope，并只把媒体 ID 绑定到
   临时 upload ID。Server 不得拥有另一套 Prompt 文案、摘要格式、Tool 描述或默认超时。
3. Server 按提交顺序重建原生消息；首轮后只清除历史视觉 parts 并保留与本机一致的文字占位。
4. `load_skill` 是运行时 Tool：远端用设备提交的 Skill 快照就地执行，
   不进入 `waitingForDevice`。读取或写入业务事实的 Tool 仍必须交给设备执行。
5. 同一模型 step 返回多个 `tool_calls` 时必须全部持久化。所有设备 Tool Result 到齐前 Job 保持
   `waitingForDevice`；续跑时按原 assistant 调用顺序追加 `role=tool` 结果。
6. Server 收到缺失、未知或自相矛盾的 Envelope、媒体绑定或 Tool 边界时必须拒绝任务，不能降级为
   旧的简化 Prompt。

## 数据与隐私

- 远程持续执行继续默认关闭，并在首次开启时明确披露：当前消息、有界会话历史、所选媒体、当前
  有效 Prompt、Skills 与 Tool 契约会被发送到用户配置的 Soma Server。
- 自定义 Prompt 与 Skill 可能包含用户编辑文本，只能随明确启用的具体 Job 临时发送；不得进入
  普通日志，不成为服务器默认配置或跨 Job 资料库。
- BYOK、Keychain、SwiftData 数据库、未选媒体、原始坐标和 thinking/reasoning 不进入 Envelope。
- 业务记录仍以设备固定 Tool 的审查结果为事实；终态 ACK 后 24 小时内清理内容，硬上限 7 天。

## 验收

- 自动化门禁证明本地与远程都调用同一个 Builder，Server Provider 不含 Agent Prompt 文案。
- 自定义 Prompt、历史角色顺序、Skill 内容、Tool 定义、暴露集合、步数与时限可在远程请求中逐项
  对照设备生成值。
- 两个并行设备 Tool 以任意结果到达顺序完成时，不丢调用、不提前续跑，最终消息按调用顺序恢复。
- `load_skill` 使用本次提交的自定义内容并形成 Skill Span，不产生设备 Tool Request。
- 本机/远程分别用同一虚构 Turn 完成一次无 Tool、一次 Skill、一次并行读 Tool 和一次 mutation
  handoff；结果语义与事件顺序一致。

## 非目标

- 不让 Server 获取 BYOK 或直接访问 SwiftData。
- 不把远程 Job 变成聊天、Prompt 或 Skills 的云同步。
- 不承诺不同 Provider 模型本身产生逐字相同的自然语言。
