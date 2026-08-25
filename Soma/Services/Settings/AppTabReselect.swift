enum AppTabReselect {
    enum Effect: Equatable {
        case switchTo(AppTab)
        case resetStack(AppTab)
    }

    /// 普通切换只提交一次 selected Tab；只有再点当前 Tab 才允许写栈身份。
    /// 这样不会为了写回同一个 UUID 额外触发 Root 失效。
    static func effect(
        selected: AppTab,
        incoming: AppTab
    ) -> Effect {
        selected == incoming ? .resetStack(incoming) : .switchTo(incoming)
    }
}
