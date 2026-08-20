import Foundation

enum AppTabReselect {
    /// 再点已选中的 Tab 才换栈身份，从而 pop 到该 Tab 根页面；换到别的 Tab 保持原子栈。
    static func stackID(
        selected: AppTab,
        incoming: AppTab,
        current: UUID
    ) -> UUID {
        selected == incoming ? UUID() : current
    }
}
