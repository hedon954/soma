# BUG 0040：教练子树随任意 Tab 交互整体重算，双击教练整页重建

- 状态：已修复，模拟器与真机回归通过
- 发现日期：2026-08-26
- 影响范围：教练页内容稍多时，所有 Tab 切换动画掉帧；双击「教练」Tab 出现整页重渲染并
  重新查询；切回教练不显示最新消息；长流式期间整页仍按 5 Hz 失效
- 上游依据：用户真机反馈；[性能审计 2026-08-24](../engineering/performance-audit-2026-08-24.md)
  已定位“返回 Coach 长尾在 AttributeGraph/布局/文本测量”但未收口
- 下游落地：[PRD 047](../prd/047-root-aware-tab-reselection.md)；
  [ADR 0105](../adr/0105-root-aware-tab-reselection.md)；
  [性能优化经验教训（2026-08-26）](../engineering/performance-optimization-lessons-2026-08-26.md)

## 症状

1. 教练会话内容增多后，训练↔进展↔设置这类与教练无关的 Tab 切换也明显卡顿，切换动画掉帧。
2. 双击（再选）「教练」Tab 时整页可见地重建：滚动位置丢失、气泡重新排版、数据重新查询。
3. 从其他 Tab 切回教练时列表停在旧位置，不显示最新消息。
4. 长流式回复期间，整页随投影 tick 周期性失效，而设计意图是只更新实时回复叶子。

## 根因

三个独立机制互相叠加，全部指向“隐藏或无关的视图被连带失效”：

1. **每次 Root 失效都级联进教练子树。** `CoachRootTab` 携带 `Binding<RootSheet?>`、
   `isActive: selectedTab == .coach` 和每次重建的闭包。SwiftUI 对非 `Equatable` 视图按
   逐字段反射比较决定是否重算 body，闭包与 Binding 字段必然比较失败，因此 RootView 任意
   一次 state 变化（包括与教练无关的 Tab 切换、开关 sheet）都会沿
   `CoachRootTab → CoachView → CoachSessionPage → CoachSessionView` 重新求值，重建
   `@Query` 包装并重新 diff 全部已挂载气泡。教练内容越多，这笔隐藏成本越大，Tab 切换
   动画帧预算被隐藏子树吃掉。
2. **再选「教练」用栈身份重建实现回根。** `tabStackIDs[.coach] = UUID()` 更换 `.id()`
   等于销毁再重建整棵导航树：@State 全部丢失、`@Query` 重建、全部消息重新排版。教练子树
   内唯一的推入导航只有健身房页（`showsGyms`），完全不需要整树重建即可回根。
3. **流式滚动节流状态是 `@State`。** `lastLiveScrollAt`/`liveScrollTask` 每个 5 Hz 滚动
   tick 都被写入，把“只更新实时回复叶子”的设计重新放大成整页失效；
   `CoachLiveAutoScrollDriver` 在 Tab 隐藏时也仍订阅 `liveEventRevision` 并安排滚动。

## 修复

- `CoachRootTab` 只保留稳定引用入参；Tab 激活态改由 `\.coachTabIsActive` 环境值下发，
  整棵教练子树中只有实时转写观察者与新的 `CoachTabActivationDriver` 两枚叶子读取。
  “需要 AI 配置”从闭包链改为 `.coachRequiresAIConfiguration` 通知，由 RootView 打开
  设置 sheet。Tab 切换自此不再重算教练子树、不再重建查询。
- [PRD 047](../prd/047-root-aware-tab-reselection.md) 后续把再选规则收口为根感知行为：教练
  再选始终 no-op，不再发通知、收起页面或滚动；训练、进展、设置只在非根详情时回根。
- 切换到教练 Tab 时，`CoachTabActivationDriver` 触发一次无动画滚底，列表回到最新消息。
- 滚动节流状态迁入非 Observation 的 `CoachVisibilityState.liveScroll` 引用；
  `CoachLiveAutoScrollDriver` 增加激活态门控，隐藏 Tab 完全停止订阅流式 revision，
  再入时补一次滚底；高频路径上的 `@State` 布尔写入全部加等值守卫。
- `CoachBubble` 实现 `Equatable`（消息对象身份 + 渲染 flags，闭包不参与）并以
  `.equatable()` 挂载，父层 state 变化（输入草稿、处理标志）不再重排历史气泡；消息内容
  变化仍由 SwiftData Observation 在气泡自身依赖上精确失效。
- 第二轮收口输入与查询侧的同类放大：草稿、附件、语音、快捷与建议选择迁入
  `CoachComposerState`（`@Observable` 引用），会话页 body 不读任何输入区字段，打字与
  听写 partial 只重渲染输入区；语音识别对重复 partial 做等值守卫；教练页 `AgentJob`
  查询排除成功终态，流式期间每次 Job 保存不再物化整页陈旧历史。

## 回归门禁

- `make perf-check`：教练根不得携带 per-render 入参；`tabStackIDs[.coach]` 不得恢复；
  `\.coachTabIsActive` 环境键、根感知再选路径、Equatable 气泡与非 Observation 节流
  持有者必须存在；`CoachView` 不得重新出现 `isTabActive` 参数或 `@State` 节流字段。
- `AppTabReselectTests`：普通切换、四个根页 no-op、教练非根 no-op 与三个非教练 Tab 非根回根。
- `CoachBubbleEquatableTests`：闭包不参与等价；消息身份与渲染 flags 参与失效。
- `CoachComposerStateTests`：听写合成、建议失配、发送收口与附件上限。
- `CoachTabBehaviorUITests`（`SomaPerformance` scheme，与既有教练分页/长流 UI 回归同套）：
  切回教练自动回到最新消息；再点教练保持阅读位置和分页，设置详情再点设置才回根
  （等待首轮分页稳定后保持实际消息数），以此证明会话页未被销毁重建；Tab 通过无障碍元素点按，
  不依赖设备尺寸坐标。
- 手工验收（见 `docs/acceptance.md` 教练段落）：切走再切回教练自动显示最新消息；再点
  「教练」保持当前页面与滚动；训练、进展、设置只在详情页再点回根；长流式期间切换保持流畅。

## 验证

- `make check` 与 `make verify` 通过：622 项 XCTest、7 项 Swift Testing 及 31 项 Server 测试
  通过，1 项依赖数据库 URL 的 Server 测试按预期跳过。
- `CoachTabBehaviorUITests` 的三个当前行为分别通过：切回教练显示最新消息；教练再选保持阅读
  位置与已加载分页；设置详情再选设置回到根页。
- Release 0.0.15 (19) 真机 Time Profiler 单轮复验通过：10 轮共 40/40 个 Tab 切换样本，
  p50 `64.213 ms`、p95 `76.677 ms`、最大值 `92.220 ms`，低于 `100 ms` 预算；无中断或
  未配对 signpost。证据位于 `build/performance/device-harness-tabs/run-20260826-225714-97808/`
  （本地产物，不进入 Git）。
- 用户最近两个真实 Session 的只读真机复验完成：往返 3 轮共 6/6 次切换，p50
  `142.172 ms`、p95/最大值 `160.873 ms`，低于 `200 ms` 预算；35 秒 Animation Hitches
  内完成跨两个 Session 的 12 次长内容滚动，actual hitch 为 0，`>=33 ms` 潜在交互延迟为 0。
  录制只包含匿名区间，不包含 Session ID、标题、正文或截图。
- 上述真实数据与虚构夹具证据满足本次验收，不再追加重复采样。
