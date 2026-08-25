# ADR 0070：可审查的滚动 Session 压缩

- 状态：已采纳
- 日期：2026-08-15
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0024](../../0.0.1/adr/0024-session-context-projection-and-compaction.md) 中十轮外不生成滚动摘要的边界
  - [ADR 0047](../../0.0.3/adr/0047-deterministic-context-pack-and-cross-turn-facts.md) 中十轮外只使用确定性意图 digest 的边界
  - [ADR 0056](../../0.0.4/adr/0056-trusted-selective-multimodal-context.md) 中不使用 LLM 滚动摘要的边界
- 后续替代：暂无
- 上游依据：[PRD 030](../prd/030-agent-prompt-skill-context-and-tool-v3.md)

## 背景

固定最近十个来回能控制请求大小，但更早的目标、限制、纠正和未完成任务只能留下关键词 digest。
直接把历史无限发送不可接受；无审查的自由文本摘要又可能把推断升级为事实。

## 决策

1. 最近十个完整 user-assistant 对继续作为原生消息；当前 Turn、未完成 Attempt、Tool 原始 JSON
   和压缩事件不计入对数。
2. 有完整对移出窗口时，压缩 Middleware 在 ReAct Loop 前调用模型；输入是已有摘要和本次移出的
   完整对，输出是完全替代旧摘要的版本化结构，不做字符串追加。
3. 摘要只保存来源 Turn、明确目标/事实/约束、决定、未解决问题、短叙述和稳定业务引用。每项
   可追溯到输入范围，不得保存 thinking 或把媒体描述伪装成重新看到画面。
4. 小模型优先；缺失或结构校验失败时使用标准模型；再次失败使用确定性 digest。压缩失败不阻塞
   当前 Turn。
5. 每次压缩形成持久派生记录和可展开 Chat 事件卡。原聊天、媒体、Trace 和业务记录永不删除。
6. 最近十对仍超上下文预算时，从最旧完整对继续并入本次压缩，直到请求可发送；不拆对、不截字。
7. 本地与远程使用设备生成的同一压缩输入、响应 Schema 和回退规则；Loop 开始后不再压缩。

## 未选择的方案

- 不静默截断单条消息，也不把摘要写成 CoachMessage 冒充原始对话。
- 不只依赖模型摘要；确定性回退和来源范围始终保留。

## 结果

### 正向影响

- 长 Session 保留连续语义，同时有界、可见、可降级。

### 成本与限制

- 十轮后可能增加一次模型调用；摘要是派生上下文而非业务事实，仍需精确 Tool 读取记录。

## 验证

- 第十一对、递归替换、两档失败、超预算、跨重启、Chat 投影和本地/远程等价测试。

## 参考

- [PRD 030](../prd/030-agent-prompt-skill-context-and-tool-v3.md)
