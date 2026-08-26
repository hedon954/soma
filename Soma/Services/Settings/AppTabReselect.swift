enum AppTabReselect {
    enum Effect: Equatable {
        case noAction
        case switchTo(AppTab)
        case resetStack(AppTab)
    }

    /// 普通切换只提交一次 selected Tab。再点当前 Tab 时，教练始终无操作；
    /// 其余 Tab 只有明确不在根页时才重建对应导航栈。
    static func effect(
        selected: AppTab,
        incoming: AppTab,
        isSelectedTabAtRoot: Bool
    ) -> Effect {
        guard selected == incoming else { return .switchTo(incoming) }
        guard incoming != .coach, !isSelectedTabAtRoot else { return .noAction }
        return .resetStack(incoming)
    }
}

/// Tab 根状态只供点击决策同步读取，不参与 SwiftUI Observation。
/// 隐藏根因普通 Tab 切换消失时保持原状态；只有当前选中根消失才表示推入了详情。
@MainActor
final class AppTabNavigationState {
    private var selectedTab: AppTab = .coach
    private var isAtRootByTab: [AppTab: Bool] = [
        .coach: true,
        .training: true,
        .insights: true,
        .settings: true
    ]

    func selectionWillChange(to tab: AppTab) {
        selectedTab = tab
    }

    func rootDidAppear(_ tab: AppTab) {
        isAtRootByTab[tab] = true
    }

    func rootDidDisappear(_ tab: AppTab) {
        guard selectedTab == tab else { return }
        isAtRootByTab[tab] = false
    }

    func setAtRoot(_ isAtRoot: Bool, for tab: AppTab) {
        isAtRootByTab[tab] = isAtRoot
    }

    func isAtRoot(_ tab: AppTab) -> Bool {
        isAtRootByTab[tab] ?? true
    }
}
