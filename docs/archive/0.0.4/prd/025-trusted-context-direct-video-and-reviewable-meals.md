# PRD 025：可信对话上下文、直传视频与可审查饮食

- 状态：已采纳，已实施；真机交互验收待维护者确认
- 日期：2026-08-11
- 修订自：
  - [PRD 004](../../0.0.1/prd/004-soma-current-product.md) 的跨日 Session、历史媒体、Tool 卡片和饮食记录基线
  - [PRD 005](../../0.0.1/prd/005-conversation-sessions-and-send-feedback.md) 的自然日 Session 边界
  - [PRD 008](../../0.0.1/prd/008-coach-continuity-and-adaptive-models.md) 的用户控制 Session 和多模态上下文边界
  - [PRD 011](../../0.0.1/prd/011-durable-agent-jobs-remote-continuity.md) 的远程上下文与流式体验边界
  - [PRD 020](../../0.0.3/prd/020-gui-simplification-and-progressive-disclosure.md) 的 Agent 过程卡与记录详情呈现
  - [PRD 022](../../0.0.3/prd/022-react-reliability-and-context-awareness.md) 的上下文包与 Tool 暴露边界
- 后续修订：
  - [PRD 027](../../0.0.5/prd/027-reliable-efficient-react-and-in-context-review.md) 固定 Loop 时间戳、重构分层超时，并将可审查卡扩展为最新回复原位 CRUD
  - [PRD 029](../../0.0.6/prd/029-unified-local-remote-agent-model-input.md) 把上下文等价扩展为完整 Prompt、Skills、Tool 和恢复消息等价
  - [PRD 030](../../0.0.6/prd/030-agent-prompt-skill-context-and-tool-v3.md) 修订滚动摘要、强类型 CRUD、业务日和发生时间语义
  - [PRD 036](../../0.0.9/prd/036-meal-sugar-and-glycemic-speed-estimate.md) 增加可审查总糖和非诊断的餐食组成升糖速度估算
  - [PRD 033](../../0.0.7/prd/033-message-metadata-shortcut-crud-and-reviewable-meal-cards.md) 把饮食结果卡改为
    可编辑菜品拆解卡加只读派生汇总卡，并把记录时间收敛到钟点
- 上游依据：
  - [BUG 0011](../../../bugs/0011-meal-correction-misattributed-media.md)
  - [BUG 0012](../../../bugs/0012-direct-video-and-first-delta-timeout.md)
- 下游落地：
  - [ADR 0055](../adr/0055-hybrid-daily-conversation-sessions.md)
  - [ADR 0056](../adr/0056-trusted-selective-multimodal-context.md)
  - [ADR 0057](../adr/0057-direct-video-capability-and-observable-fallback.md)
  - [ADR 0058](../adr/0058-first-delta-deadline-and-bounded-retry.md)
  - [ADR 0059](../adr/0059-precise-tools-and-reviewable-meal-items.md)
- 关联决策：[ADR 0055](../adr/0055-hybrid-daily-conversation-sessions.md)、[ADR 0056](../adr/0056-trusted-selective-multimodal-context.md)、[ADR 0057](../adr/0057-direct-video-capability-and-observable-fallback.md)、[ADR 0058](../adr/0058-first-delta-deadline-and-bounded-retry.md)、[ADR 0059](../adr/0059-precise-tools-and-reviewable-meal-items.md)

## 背景

真实饮食记录暴露出一组相互放大的问题：重新进入 App 后仍停在上一天 Session；本机和远程
Agent 看到的历史不一致；当前图片与历史图片一起进入请求后，模型和合并规则可能修改错误记录；
视频直传路径仍提前抽帧并重复上传；请求没有首增量时限；读取 Tool 返回过多内容；成功饮食
只表现为多张过程卡和重复文字，缺少一眼可审查的结果。

## 用户结果

1. 重新进入前台时，Soma 自动进入今天的会话；用户仍可在本次前台生命周期中主动继续旧会话。
2. 教练可靠理解消息发送时间、当前时间与设备时区，本地和远程执行使用同一份有界上下文。
3. 当前媒体优先且不会被历史媒体冒充；明确回指时只恢复最近匹配媒体。
4. 支持直接视频的模型收到规范化完整视频；降级为关键帧时明确告知并可在 Trace 审查。
5. 文字、图片和直传视频在首响应过慢时自动取消并最多重试一次，界面显示恢复状态。
6. Tool 精确查询、分页并只返回所需字段；训练、饮食和身体使用一个通用 CRUD Tool。
7. 饮食回复展示一张可进入详情编辑的结果卡，未知营养保持未知，食物项可逐项审查。

## 产品规则

- Session 以设备 `Calendar` 的自然日为自动边界；重复 foreground 不制造多个空 Session。
- 一条 Turn 在提交时冻结 Session。手动选择旧 Session 后，本次前台期间不被发送前检查抢走；
  再次进入前台恢复自动按日解析。
- 系统注入消息提交时间、Attempt 开始时间、时区、UTC offset、日期与星期，用户提示不能覆盖。
- 最近历史最多十个完整来回且受约 6,000 token 预算约束；本轮有媒体时不附历史媒体；明确回指
  最多恢复一个历史 Turn，比较最多两个。
- 新图片默认创建新记录；只有当前消息明确补充或纠正紧邻的唯一记录时才更新。歧义时询问，
  不写入。
- 文字、图片/关键帧、直接视频的首增量门槛分别为 8、10、20 秒；首文字或 Tool Call 增量算
  首响应。每个模型步骤最多重试一次，流空闲 30 秒、单步骤总时限 180 秒。
- 饮食热量与宏量营养均可为空；只有完整食物项才可确定性汇总。用户编辑值优先，来源必须保留。
- Agent 过程默认折叠；成功饮食以稳定记录 ID 驱动结果卡，不解析最终回复猜记录。

## 数据与隐私

- `AgentTurnContextEnvelope` 只包含当前任务所需的可信时间、确定性业务摘要、最近会话文字、
  短事实引用及被选择的媒体。远程持续执行仍默认关闭，只有用户启用后才发送。
- 远程上下文从“当前消息 + 摘要”扩大为有界最近会话文字；触发条件仍是用户主动发送并启用远程
  模式。Server 只随 Job 保留到既有清理时点，不成为业务事实来源。
- 直接视频只发送规范化副本；Trace 只保存模式、字节数、帧数、耗时和错误类别，不保存路径、
  Base64、真实内容或 Authorization。
- `MealItem` 与营养来源只保存在对应本地数据空间，并进入既有备份、导出与清除边界。

## 明确不在范围

- 不为未验证的模型或网关宣称完整视频支持。
- 不新增账户、诊断、云端身体数据库、通用代码 Tool 或 Keep 风格品牌/快捷入口。
- 不使用 LLM 生成不可审查的滚动事实摘要，也不无限发送完整 Session。

## 验收

- 跨日、前台、手动旧 Session、跨午夜发送和数据空间隔离均有确定性测试。
- 本地/远程同一 Turn 得到等价的可信时间、历史文字与事实引用；历史媒体选择符合规则。
- 直接视频首请求不含关键帧；失败后才抽帧并标记降级；无视觉输入时显式失败。
- 8/10/20 秒 TTFT、一次重试、30 秒 idle、180 秒总时限和取消传播有虚拟时钟测试。
- Tool v1 可兼容回放，v2 新请求只暴露 13 个 Tool，并验证分页、字段投影和过滤。
- 旧饮食迁移无数据丢失，未知值不显示为 0；结果卡和编辑页通过模拟器浅色/深色、Dynamic Type
  与 VoiceOver 检查。
