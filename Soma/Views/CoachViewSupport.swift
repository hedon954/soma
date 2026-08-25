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

/// Tab 显隐只决定是否允许刷新后台建议，不属于界面状态。
/// 使用非 Observation 引用，避免每次回到 Coach 都先触发一次无内容变化的 body。
@MainActor
final class CoachVisibilityState {
    var isVisible = false
    var autoScrollGate = CoachMessageAutoScrollGate()
}
