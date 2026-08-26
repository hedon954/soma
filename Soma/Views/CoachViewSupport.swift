import SwiftUI

enum CoachSheet: Identifiable {
    case media
    case pendingQueue
    case quickCapture(CaptureEntryRequest)

    var id: String {
        switch self {
        case .media:
            "media"
        case .pendingQueue:
            "pending-queue"
        case let .quickCapture(request):
            "capture-\(request.id)"
        }
    }
}

/// 教练 Tab 是否为当前选中项。由 RootView 写入一次布尔环境值，只有实时转写
/// 观察者和激活滚底驱动这两枚叶子读取；教练子树的其余部分不因 Tab 切换重算，
/// `@Query` 也不会随选中态变化重建。
private struct CoachTabIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var coachTabIsActive: Bool {
        get { self[CoachTabIsActiveKey.self] }
        set { self[CoachTabIsActiveKey.self] = newValue }
    }
}

extension Notification.Name {
    /// 再次点按已选中的「教练」Tab：不重建对话树，收起抽屉与健身房页并滚到最新消息。
    static let coachTabReselected = Notification.Name(
        "Soma.coachTabReselected"
    )
    /// 发送链路发现缺少必需 API Key 时，请求 RootView 打开 LLM 配置 sheet。
    /// 用通知替代逐层闭包，避免教练子树携带每次渲染都变化的入参。
    static let coachRequiresAIConfiguration = Notification.Name(
        "Soma.coachRequiresAIConfiguration"
    )
}

/// 流式滚动节流的可变状态。5 Hz 的滚动 tick 只改写这个引用类型的字段，
/// 不触发 SwiftUI 失效；真正的界面更新仍由实时回复叶子承担。
@MainActor
final class CoachLiveScrollThrottle {
    var lastScrollAt = Date.distantPast
    var task: Task<Void, Never>?
}

/// Tab 显隐只决定是否允许刷新后台建议，不属于界面状态。
/// 使用非 Observation 引用，避免每次回到 Coach 都先触发一次无内容变化的 body。
@MainActor
final class CoachVisibilityState {
    var isVisible = false
    var autoScrollGate = CoachMessageAutoScrollGate()
    let liveScroll = CoachLiveScrollThrottle()
}
