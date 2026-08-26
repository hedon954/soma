enum AppTabReselect {
    enum Effect: Equatable {
        case switchTo(AppTab)
        case resetStack(AppTab)
        case restoreCoachRoot
    }

    /// 普通切换只提交一次 selected Tab。再点当前 Tab 时，教练页发一次
    /// 「回根」通知（收起抽屉/健身房页并滚到最新消息），不重建对话树；
    /// 其余 Tab 保持既有的栈身份重建回根语义。
    static func effect(
        selected: AppTab,
        incoming: AppTab
    ) -> Effect {
        guard selected == incoming else { return .switchTo(incoming) }
        return incoming == .coach ? .restoreCoachRoot : .resetStack(incoming)
    }
}
