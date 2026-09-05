# ADR 0105：用显式根状态决定 Tab 再选效果

- 状态：已采纳
- 日期：2026-08-26
- 维护者：Soma maintainers
- 部分替代：[ADR 0000](../../../adr/0000-origin-through-0.0.11.md) 中“再选当前 Tab 一律回根”的交互决策
- 后续替代：[ADR 0112](../../../adr/0112-coach-scroll-and-session-behavior.md) 仅增加教练 Tab 的系统双击回尾；单次再选仍 no-op
- 上游依据：[PRD 047](../prd/047-root-aware-tab-reselection.md)；[BUG 0040](../../../bugs/0040-hidden-coach-subtree-tab-invalidation.md)

## 背景

SwiftUI `TabView` 的 selection 只表达选中值，当前 SDK 没有公开的“已选 Tab 再次点按”回调。
旧实现仅在 selection Binding 中比较相同值，既无法稳定收到真实再选事件，也无法区分当前导航栈
是否在根页。教练专用通知又把无意义的点击扩大成抽屉、页面和滚动副作用。

## 决策

- 保持原生 SwiftUI `TabView`、四个持久根子树和独立导航栈。
- 用一个非 Observation、`@MainActor` 的 `AppTabNavigationState` 保存当前选中 Tab 及三个非教练
  Tab 的根状态；读取只发生在点击决策时，不触发根视图刷新。
- 设置页从显式 `NavigationStack` path 上报根状态；训练和进展在根内容出现/消失时上报，并用当前
  选中 Tab 排除“仅因切换而隐藏”的误判。
- 用窄范围 UIKit 手势桥只识别原生 `UITabBar` 上“触摸开始时已经选中”的 item，不接管
  `UITabBarController` delegate，也不阻断系统触摸；普通切换仍完全由 SwiftUI selection 处理。
- 再选效果由纯函数决定：教练永远 `.noAction`；训练、进展、设置根页为 `.noAction`，非根为
  `.resetStack`；普通切换为 `.switchTo`。

## 未选择的方案

- 不继续依赖 selection Binding 收到相同值，因为真实再选不会稳定写入新 selection。
- 不无条件更换栈 `.id`，因为根页点击不应丢失页面状态或制造重建成本。
- 不保留教练通知，也不把再选解释为滚动、关闭抽屉或收起健身房页。
- 不替换 `UITabBarController` delegate，避免干扰 SwiftUI 的系统 Tab 生命周期。

## 结果

### 正向影响

- 交互只在用户确实位于非根详情时发生，根页与教练点击没有副作用。
- 根状态是可单测的明确事实；点击桥与业务决策分离。
- 教练树继续保持稳定身份，不因再选重新查询或排版。

### 成本与限制

- iPhone 底部 `UITabBar` 需要一个只读触摸桥；系统 Tab 结构变化时必须由 UI 回归覆盖。
- 训练和进展的根显隐上报依赖 SwiftUI 导航生命周期，新增特殊导航容器时要同步根状态来源。

## 验证

- `AppTabReselectTests` 固定根/非根决策与根状态误判边界。
- `CoachTabBehaviorUITests` 固定教练再选 no-op 和非教练详情再选回根。
- `make perf-check` 禁止恢复旧通知、教练栈重建或根页无条件重建。
- `make check`、`make verify` 与标准 iPhone 浅深色模拟器回归。

## 参考

- [页面契约](../../../../.claude/skills/soma-ui-development/references/screen-contracts.md)
- [验收矩阵](../../../acceptance.md)
