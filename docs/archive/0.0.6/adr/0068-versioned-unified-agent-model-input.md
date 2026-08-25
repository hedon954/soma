# ADR 0068：版本化统一 Agent 模型输入由设备生成

- 状态：已采纳
- 日期：2026-08-15
- 维护者：Soma maintainers
- 后续替代：[ADR 0069](0069-layered-agent-prompt-skill-middleware-and-typed-tools.md) 升级分层 Prompt、Skill 快照和 Tool v3 输入契约
- 上游依据：
  - [PRD 029](../prd/029-unified-local-remote-agent-model-input.md)
  - [BUG 0018](../../../bugs/0018-remote-agent-model-input-divergence.md)
- 下游落地：[Agent Job 与远程执行协议](../../../engineering/agent-job-protocol.md)

## 背景

本地 `AIService` 组装完整 ReAct Prompt、历史、Skills 和 Tool，而 Server Provider 另有简化
System Prompt、扁平上下文和独立时限。两条实现同时演进后，远程模式已经不再是 Backend 切换，
而成为行为不同的第二个 Agent。

## 决策

1. `AgentModelInputEnvelope` 是发送给任意聊天 Provider 的唯一版本化事实，固定消息、媒体 ID、
   Skill 快照、完整 Tool 定义、初始 Tool 集合和运行参数。
2. `AgentModelInputBuilder` 仅在设备端组装 Envelope；本机把它转换为 SDK 消息，远端将它和媒体
   upload 绑定一同提交。Server 只能验证、解析与转发，禁止重建 Prompt。
3. Envelope 同时携带完整固定 Tool 目录与本轮初始暴露集合。Server 只转发当前集合；成功
   `expand_tool_group` 后从同一份目录扩大集合，不使用 Server 自己的描述或参数 Schema。
4. Server 固定注册表只承担安全校验和设备执行分类，不作为 Provider Tool 定义来源。
5. 远程 Worker 把每个模型 step 的 assistant 文本与全部原生 `tool_calls` 原子记入 Event 历史；
   runtime Tool 就地完成，业务 Tool 全部持久化后等待设备，结果齐备才续跑。
6. 缺失或不支持的 Envelope 直接拒绝。删除旧 Prompt 和兼容降级，避免再次形成双重事实来源。

## 未选择的方案

- 不让 Server 复制 Swift 的 Prompt/Skill/Tool 文本。
- 不比较两端生成的字符串后继续维护两个 Builder；结构上只允许一个 Builder。
- 不把 `load_skill` 交给设备，因为远端已经持有本 Job 明确授权的 Skill 快照。

## 结果

### 正向影响

- Backend 只影响执行位置与凭据，不影响模型输入语义。
- 自定义 Prompt/Skill、选择性历史媒体、并行调用和恢复消息都可直接对照同一 Envelope。
- `make check` 可静态阻止 Server 再出现 Agent Prompt 文案或绕开统一输入源。

### 成本与限制

- 远程 Job payload 比旧的扁平上下文更完整；隐私披露和 TTL 必须覆盖 Prompt 与 Skill 文本。
- Swift Tool Schema 变化必须和 Server 安全注册表同步，但 Provider 定义始终以 Envelope 为准。
- 当前没有跨版本兼容降级；协议不匹配时要求更新 App 或 Server。

## 验证

- `RemoteAgentExecutionTests` 验证自定义 Prompt、消息角色、Skill、Tool 集合和运行参数提交。
- `Server/test/server.test.ts` 验证 runtime Skill、并行设备 Tool 和结果齐备后续跑。
- `scripts/check-agent-model-input-parity.rb` 禁止 Server Prompt 文案并要求两条路径共用 Builder。
- 完整门禁：`make verify`。

## 参考

- [Agent Job 协议](../../../engineering/agent-job-protocol.md)
- [Prompt 来源目录](../../../engineering/prompt-source-catalog.md)
