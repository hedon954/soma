# ADR 0112：教练滚动与 Session 行为

- 状态：部分已替代
- 日期：2026-09-02
- 维护者：Soma maintainers
- 部分替代：[ADR 0105](../../0.0.16/adr/0105-root-aware-tab-reselection.md) 中“教练再选永远无操作”的双击子行为
- 后续修订：[ADR 0125](../../../adr/0125-eager-loaded-coach-messages.md) 已加载页改为即时 VStack，取消滑动 alignment 顶锚
- 后续替代：暂无
- 上游依据：
  - [PRD 052](../prd/052-coach-training-and-lifecycle-reliability.md)
  - [BUG 0046](../../../bugs/0046-coach-stream-scrolls-into-blank-space.md)
  - [BUG 0055](../../../bugs/0055-coach-history-scroll-repositions.md)

## 背景

零高度 bottom anchor、固定 yield 和多处 `scrollTo` 会在响应尚无正文时把可视区域推入空白；首次
进入又可能定位到用户消息起点。模型命名同时带来额外调用与不稳定标题。

## 决策

- 以最后一条 AI 消息真实尾部为滚动目标；内容 revision 和布局测量共同驱动一个 tail-follow
  状态。内容不足视口时贴顶，用户主动上滑后暂停，发送新消息或双击教练再恢复。
- 首次进入、切换 Session 和从其他 Tab 返回，在最后 AI 消息布局完成后定位尾部。单次再选教练仍
  no-op；仅系统双击教练触发回尾，不重建导航栈。
- Session 默认标题由 `startedAt` 与业务时区确定性格式化为 `MM月dd日 - 周X`。迁移统一重命名
  旧 Session；升级后允许手动改名和恢复日期标题，且不修改 `updatedAt`。

## 未选择的方案

- 不用固定 sleep/yield 等待 SwiftUI 布局，不保留模型标题服务。
- 不把单次再选教练改为回底，以免打断正在阅读历史消息的用户。

## 结果

滚动行为由可测量状态而非时序猜测决定，标题无模型成本；双击识别需要一个不拦截系统触摸的窄
UIKit 手势桥。

## 验证

- 零 token、首 token、Markdown 增长、键盘、短/长会话、首次定位、单击 no-op 和双击回尾测试。
- 日期标题覆盖业务时区、跨日、迁移、手动改名与排序不变。
