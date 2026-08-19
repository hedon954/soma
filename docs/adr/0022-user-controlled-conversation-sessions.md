# ADR 0022：由用户控制可继续的对话 Session

- 状态：部分已替代
- 日期：2026-07-30
- 维护者：Soma maintainers
- 替代：[ADR 0015](0015-daily-conversation-session-lifecycle.md) 的每日自动切换和只读历史边界
- 后续替代：
  - [ADR 0055](0055-hybrid-daily-conversation-sessions.md) 恢复自动按日解析并保留当前前台生命周期内的手动覆盖
  - [ADR 0061](0061-discoverable-conversation-session-entry.md) 恢复可见时间按钮并保留抽屉手势
  - [ADR 0080](0080-conversation-session-swipe-delete.md) 落地历史抽屉左滑删除对话聊天图，并明确不删除业务记录

## 背景

ADR 0015 通过自然日解决了无限聊天和上下文串联问题，但现在历史 Session 需要像真实对话
一样重新进入并继续发送。若仍在每次进入前台时按日期重置当前 Session，用户刚选择的旧会话
会被生命周期事件抢走，Session 也不再是用户能理解和控制的谈话边界。

## 决策

- Session 边界改为用户主导，不再因午夜、冷启动或重新进入前台自动创建新 Session。
- 每个数据空间持久化自己的当前 `sessionID`。该 ID 有效时恢复它；失效时选择最近活动的
  Session；仍不存在时建立唯一空 Session。
- 左边界右滑打开隐藏式 Session 抽屉，教练页不保留历史时钟图标。VoiceOver 通过自定义操作
  获得等价入口。
- “新对话”建立并激活 Session；若当前 Session 为空则复用，避免空记录堆积。
- 点击历史 Session 直接激活原聊天与 Composer，不再进入只读 Transcript。
- 一条 Turn 在提交时固定 `sessionID`。用户可以在处理期间查看其他 Session，但 Event、
  Trace 和最终回复始终写回原 Session。
- `ConversationProcessingService` 继续保持全 App 同时一个在途 Turn；处理结束前其他 Session
  不能发送。
- ADR 0015 的旧消息按自然日归档迁移、Session 标题、本地持久化、稳定底部滚动和不使用固定
  sleep 等约束继续有效。

## 未选择的方案

- 保留每日自动新建：会与用户选择旧 Session 继续对话冲突。
- 历史只读、继续时复制为新 Session：割裂上下文并制造重复聊天证据。
- 每个 Session 各自并发 Agent：会扩大当前 App 级 Task、写入幂等和 UI 状态边界。
- 保留常驻图标作为备用入口：与本版减少主界面低频控件的目标相反。

## 结果

### 正向影响

- Session 成为稳定、可继续、由用户理解的谈话边界。
- 历史入口退出高频视觉层级，但仍支持手势和无障碍访问。
- Agent 上下文可以严格以当前 Session 为边界。

### 成本与限制

- 不熟悉边缘手势的用户需要一次发现过程。
- Session 激活状态需要按演示/个人空间隔离并处理失效 ID。
- 当前仍不支持合并或并发处理多个 Session；对话删除见 [ADR 0080](0080-conversation-session-swipe-delete.md)。

## 验证

- 测试首次创建、空 Session 复用、显式新建、跨启动恢复、数据空间隔离和失效 ID 回退。
- 在途 Turn 期间切换 Session，确认所有 Event 只写回原 Session。
- 模拟器和真机验证左边缘手势、纵向滚动冲突、VoiceOver 操作和安全区。

## 参考

- [PRD 008](../prd/008-coach-continuity-and-adaptive-models.md)
- [ADR 0008](0008-app-scoped-conversation-processing.md)
- [ADR 0015](0015-daily-conversation-session-lifecycle.md)
