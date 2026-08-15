# ADR 0056：可信时间与选择性多模态上下文

- 状态：已采纳
- 日期：2026-08-11
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0024](0024-session-context-projection-and-compaction.md) 中默认重新附加窗口内历史媒体的边界
  - [ADR 0047](0047-deterministic-context-pack-and-cross-turn-facts.md) 中以长 Tool observation 作为跨轮事实摘要的边界
- 后续替代：
  - [ADR 0063](0063-step-resume-fixed-loop-time-and-deadline-hierarchy.md) 改为只保存 UTC 时间戳与时区标识，并让整个 Loop 复用冻结开始时间
  - [ADR 0070](0070-reviewable-rolling-session-compaction.md) 允许在 Loop 前生成可审查的滚动 LLM 摘要
- 上游依据：
  - [PRD 025](../prd/025-trusted-context-direct-video-and-reviewable-meals.md)
  - [BUG 0011](../bugs/0011-meal-correction-misattributed-media.md)

## 背景

本地历史、结构化摘要、Tool observation 与历史媒体同时注入，既重复 token，又让“这个图片”
可能指向错误画面。远程 Job 只收到摘要，和本地执行的上下文语义不同。

## 决策

1. `TrustedTurnContext` 由系统生成，包含 Turn 时间、Attempt 时间、时区、offset、日期和星期。
2. 本地与远程统一使用版本化 `AgentTurnContextEnvelope`，冻结确定性业务摘要、最近会话文字和短
   事实引用；Attempt 时间在每次模型请求时刷新。
3. 历史最多十个完整来回，并按约 6,000 token 预算从新到旧选择，不拆开一个来回。
4. 当前 Turn 有媒体时不附历史媒体；明确单指回指最近一个，比较最多两个。媒体仍挂在原历史
   user 消息，绝不进入当前 Tool 媒体归因。
5. 跨轮事实只保存操作、类型、记录 ID、短标题和时间；精确内容由分页查询 Tool 读取。
6. 远程授权披露增加“最近会话文字”，Server 沿用 Job 最小保留与清理策略。

## 未选择的方案

- 默认重发视觉额度内全部历史媒体：容易误归因且增加准备延迟。
- LLM 滚动摘要：无法保证业务事实和时间语义。

## 结果

### 正向影响

- “今天/刚才/这张图”有稳定事实来源，本地和远程上下文可验证一致。

### 成本与限制

- 明确回指识别使用有限的确定性词表；复杂歧义仍需要模型询问用户。

## 验证

- 固定 Clock、token 预算、媒体回指、本轮媒体优先、本地/远程 envelope 等价测试。

## 参考

- [PRD 025](../prd/025-trusted-context-direct-video-and-reviewable-meals.md)
