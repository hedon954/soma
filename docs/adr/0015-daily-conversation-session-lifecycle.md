# ADR 0015：在进入前台时按自然日解析当前对话 Session

- 状态：已被 [ADR 0022](0022-user-controlled-conversation-sessions.md) 替代
- 日期：2026-07-30
- 维护者：Soma maintainers
- 后续替代：
  - [ADR 0016](0016-conversation-turn-attempt-and-footprint-projection.md) 修订 Turn/Attempt 关系
  - [ADR 0022](0022-user-controlled-conversation-sessions.md) 替代每日自动切换和只读历史边界
  - [ADR 0055](0055-hybrid-daily-conversation-sessions.md) 恢复自动按日解析并保留显式继续旧会话

## 背景

教练消息目前只有时间戳，没有稳定的会话边界。仅在 UI 中按日期插入分隔线，无法限制
Agent 上下文，也无法表达“重新进入 App 后开始今天的新谈话”。如果只把当前 Session ID
保存在内存或 `UserDefaults`，消息和 Session 还可能在崩溃、数据空间切换或旧数据迁移后
失配。

本次还需要保证发送后收起输入焦点并滚到底部，但不能把固定延迟或 View 生命周期 Task
当作正确性条件。

## 技术调研

- SwiftUI 的 `scenePhase` 表达 Scene 进入 `active`、`inactive` 和 `background`，适合把
  “重新进入 App”定义为重新进入前台，而不是依赖某个页面是否重建。
- SwiftData 的 `@Model`、`Schema` 和 `@Query` 支持把 Session 作为独立持久化事实，并让
  SwiftUI 随消息关联变化刷新。新增模型与可空 `sessionID` 允许旧数据先打开，再执行应用层
  归档。
- `FocusState` 可以由发送状态显式撤销文本框焦点；`ScrollViewReader` 的
  `ScrollViewProxy.scrollTo` 应从发送动作或 `onChange` 调用，并指向始终存在的稳定底部
  锚点。

## 决策

- 新增 `ConversationSession` SwiftData 模型，持久化 `id`、开始时间、最近活动时间和本地
  标题。
- `CoachMessage` 增加可空 `sessionID`。不建立 SwiftData relationship，避免 Session
  删除规则意外级联聊天或让消息迁移依赖双向关系。
- App 根层持有 `ConversationSessionController`，并在以下时机解析当前 Session：
  - 数据空间根 View 首次建立；
  - Scene 从后台重新进入 `active`。
- 解析使用设备 `Calendar.startOfDay(for:)`：
  1. 先把所有旧版无 Session 消息按自然日归档；
  2. 最新消息属于今天时复用其 Session；
  3. 否则复用今天已存在的空 Session；
  4. 仍不存在时创建今天的新 Session。
- `ConversationProcessingService` 接收已解析的 Session，并给同一次提交产生的用户消息与
  Agent Attempt 写入相同 `sessionID`；Turn/Attempt 关系由 ADR 0016 定义。
- 当前聊天、对话引导和 Agent 最近消息摘要只读取当前 Session；历史 Session 通过独立的
  只读入口查看。
- 发送被处理服务接受后立即撤销输入焦点、清空草稿和附件，并触发一次布局后的底部滚动。
  所有后续消息和 Agent Event 更新继续滚到永远存在的 `"bottom"` 锚点。

## 未选择的方案

- 只按日期在一个消息流里加分隔线：没有真正隔离 Agent 上下文。
- 每到午夜定时强制切 Session：可能拆断仍在前台进行的用户谈话和 Agent Turn。
- 只用 `UserDefaults` 保存当前 Session：不能与数据空间中的消息组成可审查事实。
- 用固定 `sleep` 等待键盘或消息布局：设备性能变化会造成竞态。
- 把 Session 做成消息的级联 relationship：误删 Session 时可能不可恢复地删除聊天历史。

## 结果

### 正向影响

- 跨天回到 Soma 时获得清晰的新谈话，上下文不会无意携带上一天聊天。
- Session 和消息跨重启保留，旧数据可确定性归档。
- 发送后的焦点与滚动行为由状态变化驱动，文字和媒体走同一条路径。

### 成本与限制

- 旧版同一天内如果实际上存在多次独立谈话，因为没有历史边界证据，只能归入同一个
  Session。
- 当前规则只在进入前台时切分；持续前台跨午夜仍沿用原 Session。
- 如果未来允许用户删除 Session、跨设备同步或恢复后台 Agent，需要新的删除、同步与冲突
  决策。

## 验证

- 单元测试覆盖旧消息迁移、跨天新建、当天复用、空 Session 去重和一次提交共享
  `sessionID`。
- 运行 `make verify`。
- 模拟器检查发送文字/图片/视频后的键盘、底部滚动、流式卡片和历史会话。

## 参考

- [PRD 005](../prd/005-conversation-sessions-and-send-feedback.md)
- [ADR 0008](0008-app-scoped-conversation-processing.md)
- [ADR 0014](0014-agent-turn-ordered-event-cards.md)
- [Apple：ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase)
- [Apple：Preserving your app’s model data across launches](https://developer.apple.com/documentation/swiftdata/preserving-your-apps-model-data-across-launches)
- [Apple：FocusState](https://developer.apple.com/documentation/swiftui/focusstate)
- [Apple：ScrollViewReader](https://developer.apple.com/documentation/swiftui/scrollviewreader)
