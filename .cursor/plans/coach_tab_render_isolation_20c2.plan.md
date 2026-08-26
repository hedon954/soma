# 教练页与 Tab 切换性能收口（渲染隔离）

- 日期：2026-08-26
- 触发：维护者反馈教练页内容稍多即卡顿；切到教练不回到最新消息；双击「教练」Tab 整页重渲染；
  任意 Tab 切换都被教练页拖慢，切换动画掉帧。
- 授权边界：维护者明确「外显功能不变即可，此前实现与门禁基线不是绝对方针，可整体替换」。

## 调研结论（代码 + 外部最佳实践）

1. SwiftUI 对不含 `Equatable` 的 View 采用逐字段反射比较决定是否重算 body；闭包与
   `Binding` 字段必然比较失败。`CoachRootTab(sheet:isActive:transition:)` 同时携带
   Binding 与每次重建的闭包，导致 RootView 任意一次 state 变化（包括训练↔进展切换）
   都会把隐藏的教练子树整体重新求值，并重跑 `CoachSessionView.init` 中的
   `FetchDescriptor` 构造。教练内容越多，每次 Tab 切换的隐藏 diff/布局成本越大。
2. 双击当前 Tab 走 `resetStack`，用 `tabStackIDs[tab] = UUID()` 更换 `.id()` 身份，
   等于销毁并重建整棵导航树（@State 全丢、@Query 重建、全部气泡重排版）。对教练页这是
   最重的路径，而教练子树内唯一的推入导航只有 `showsGyms`，完全可以无重建回根。
3. 流式滚动节流状态 `lastLiveScrollAt`/`liveScrollTask` 是 `@State`，每次 5 Hz 滚动 tick
   都写值，把「只更新实时叶子」的设计重新放大成整页失效。
4. `CoachLiveAutoScrollDriver` 在 Tab 隐藏时仍订阅 `liveEventRevision` 并安排滚动。
5. 外部实践（Airbnb SwiftUI performance、fatbobman EquatableView、WWDC26 lazy stacks）：
   子树输入保持稳定引用/值；必要时 `Equatable + .equatable()` 显式短路；聊天列表行用
   稳定 `.id` 且行视图可跳过 diff；程序化滚动配合 `defaultScrollAnchor`。

## 方案（外显功能不变 + 两项维护者点名的行为修正）

1. `CoachRootTab` 只保留稳定引用入参（transition）。教练 Tab 激活态改走新的
   `\.coachTabIsActive` EnvironmentKey，仅由两枚叶子读取（实时转写观察者、激活滚底驱动），
   Tab 切换不再重算教练子树、不再重建 `@Query`。
2. 「需要 AI 配置」从闭包链改为 `.coachRequiresAIConfiguration` 通知，由 RootView 打开
   设置 sheet（与既有 `.prefillCoachDraft` 模式一致）。
3. `AppTabReselect.Effect` 新增 `.restoreCoachRoot`：双击教练不再改 `.id`，改为发
   `.coachTabReselected` 通知；教练页收到后关闭会话抽屉、收起健身房页（弹回根）并滚动到
   最新消息。其余三个 Tab 保留原 UUID 回根语义。
4. 新增 `CoachTabActivationDriver` 叶子：Tab 激活（env false→true）时通过既有
   `scrollRequest` 路径无动画滚动到底部，满足「切到教练自动显示最新消息」。
5. 滚动节流状态迁入非 Observation 的 `CoachVisibilityState.liveScroll`（引用类型），
   写入不再触发整页失效；冗余 `@State` 布尔写入加等值守卫。
6. `CoachLiveAutoScrollDriver` 增加 env 门控：隐藏 Tab 完全停止订阅流式 revision，
   再入时补一次滚底。
7. `CoachBubble` 实现 `Equatable`（消息对象身份 + 渲染 flags，闭包不参与）并以
   `.equatable()` 挂载；父层 state 变化（输入、处理标志）不再重排历史气泡，内容变化仍由
   SwiftData Observation 精确失效。
8. 门禁：更新 `scripts/check-performance-hotpaths.rb` 固化新基线（教练子树无
   per-selection 入参、env 键存在、双击教练不写栈 ID、节流状态非 @State、气泡 equatable），
   删除已被替代的旧断言。
9. 文档：新增 `docs/bugs/0040`（机制复盘 + 门禁），更新 bugs README、`docs/acceptance.md`
   Tab 行与教练手工验收、CHANGELOG Unreleased。

## 验证

- Linux 环境无 Xcode：运行 ruby 性能门禁、文档/仓库校验脚本、`swiftc -parse` 语法检查；
  `make verify`（构建 + 模拟器测试）由 macOS CI / 维护者本机执行。
- 单测：`AppTabReselectTests` 更新 + 教练再选新 case。
- 手工验收步骤写入 acceptance 教练段落。
