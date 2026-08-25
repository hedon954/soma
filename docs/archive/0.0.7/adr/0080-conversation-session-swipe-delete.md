# ADR 0080：对话历史抽屉支持左滑删除聊天图

- 状态：已采纳
- 日期：2026-08-18
- 维护者：Soma maintainers
- 部分替代：
  - [ADR 0022](../../0.0.1/adr/0022-user-controlled-conversation-sessions.md) 中「当前仍不支持删除」Session
  - [ADR 0015](../../0.0.1/adr/0015-daily-conversation-session-lifecycle.md) 中「未来删除 Session 需要新的删除决策」
- 后续替代：暂无
- 上游依据：
  - [PRD 004](../../0.0.1/prd/004-soma-current-product.md) 的当前产品基线与历史抽屉
  - [PRD 008](../../0.0.1/prd/008-coach-continuity-and-adaptive-models.md) 的可继续 Session 抽屉

## 背景

历史抽屉已经能新建和继续对话，但 Session 不能删除。用户误开的空对话、过期闲聊会一直留在
列表里。ADR 0022 明确推迟删除；ADR 0015 要求未来删除必须单独决定级联范围，因为 Session
与消息没有 SwiftData relationship，误用级联会删掉聊天或留下孤儿 Job、Trace 和媒体。

删除对话不能当成删除身体事实。训练、饮食、身体记录和健身房是可审查业务数据，即使它们的
`sourceSessionID` 指向被删对话，也必须保留。

## 决策

1. 历史抽屉 Session 行使用系统尾随左滑删除（`swipeActions`、`allowsFullSwipe: true`、红色
   垃圾桶），无障碍标签为「删除对话」。列表改为 `List`，以便原生滑动生效。
2. 删除只清理该 Session 的**聊天图**：`ConversationSession`、同 `sessionID` 的
   `CoachMessage` / `AgentJob` / `ConversationCompactionSummary`，以及这些 Job/Turn 的
   `PersistentAgentEvent`、`AgentTrace`、`AgentMutationReceipt`。
3. **不删除** `WorkoutEntry`、`MealEntry`、`BodyEntry`、健身房、动作定义，以及训练
   `WorkoutSession` 与带练事实。业务记录上的 `sourceSessionID` 可以继续指向已删除会话。
4. 该 Session 存在非终态 `AgentJob`（非 succeeded/failed/cancelled），或处理器正在处理该
   `sessionID` 时，拒绝删除并弹出用户可见提示，不做部分删除。
5. 若删除的是当前 Session：激活剩余 Session 中 `updatedAt` 最新者；若已无 Session，则按
   `ConversationSessionController.createSession` 的空会话复用规则创建新的空 Session。删除
   非当前 Session 后抽屉保持打开，便于连续删除。
6. 聊天/Job 媒体仅在剩余快照不再引用时回收，复用 `PersonalDataStore.reclaimMedia` 与
   `PersonalDataSnapshot.referencedMediaPaths`。仍挂在饮食、训练、身体、健身房或剩余消息/
   Job 上的共享文件必须保留。
7. 删除规则放在 Services（`ConversationSessionDeletion`），不由 View 复制，Models 不引用
   Services。Controller 只在删除当前 Session 后激活回退会话。
8. 抽屉打开时，关闭手势只接受从遮罩层开始的左滑（`.global` 下 `startLocation.x` 大于抽屉
   宽度），避免抢走行内左滑删除。

合并、分享和跨设备同步 Session 仍不在范围。

## 未选择的方案

- SwiftData cascade relationship：ADR 0015 已排除；误删 Session 可能不可恢复地带走聊天。
- 删除时级联业务记录：破坏「可审查记录独立于聊天」和 missing-is-nil 之外的既有事实。
- 在途 Job 静默取消后删除：会造成部分写入、气泡与处理器状态不一致。
- 继续用 `ScrollView` 自定义滑动：无法得到系统红色全滑删除，也与健身房/历史列表不一致。

## 结果

### 正向影响

- 对话历史可以按系统习惯清理，而不擦掉已经落下的训练、饮食和身体记录。
- 在途处理被明确拒绝，避免半删除的聊天图。

### 成本与限制

- 删除后业务记录的 `sourceSessionID` 可能悬空；审查仍以记录自身为准，不要求会话仍存在。
- 暂存、欠费或正在回复的对话必须先结束或从队列处理，才能删除。
- 最后一个空 Session 被删除后会立即出现一个新的空 Session，列表不会变成「完全没有对话」。

## 验证

- `ConversationSessionDeletionTests`：删除聊天图、保留业务记录、当前 Session 回退、非终态
  Job 拒绝、仅回收未被引用的聊天媒体。
- `make check`、`make verify`。
- 模拟器检查抽屉左滑删除、遮罩左滑关闭、删除非当前项后面板保持打开。

## 参考

- [ADR 0022：由用户控制可继续的对话 Session](../../0.0.1/adr/0022-user-controlled-conversation-sessions.md)
- [ADR 0015：按自然日解析当前对话 Session](../../0.0.1/adr/0015-daily-conversation-session-lifecycle.md)
- [ADR 0061：会话抽屉同时保留可见时间按钮与边缘手势](../../0.0.5/adr/0061-discoverable-conversation-session-entry.md)
