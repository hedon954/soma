import Foundation
import OSLog

enum AppPerformanceEvent: String, CaseIterable {
    case launchMigration = "launch_migration"
    case foregroundRecovery = "foreground_recovery"
    case rootMaintenance = "root_maintenance"
    case rootVisible = "root_visible"
    case tabTransition = "tab_transition"
    case sessionTransition = "session_transition"
    case tabContentVisible = "tab_content_visible"
    case screenDataLoad = "screen_data_load"
    case derivedSnapshot = "derived_snapshot"
    case imageLoad = "image_load"
    case agentFirstDelta = "agent_first_delta"
    case agentProjection = "agent_projection"
    case agentMarkdownParse = "agent_markdown_parse"
    case agentCompletedRender = "agent_completed_render"

    fileprivate var signpostName: StaticString {
        switch self {
        case .launchMigration: "Soma Launch Migration"
        case .foregroundRecovery: "Soma Foreground Recovery"
        case .rootMaintenance: "Soma Root Maintenance"
        case .rootVisible: "Soma Root Visible"
        case .tabTransition: "Soma Tab Transition"
        case .sessionTransition: "Soma Session Transition"
        case .tabContentVisible: "Soma Tab Content Visible"
        case .screenDataLoad: "Soma Screen Data Load"
        case .derivedSnapshot: "Soma Derived Snapshot"
        case .imageLoad: "Soma Image Load"
        case .agentFirstDelta: "Soma Agent First Delta"
        case .agentProjection: "Soma Agent Projection"
        case .agentMarkdownParse: "Soma Agent Markdown Parse"
        case .agentCompletedRender: "Soma Agent Completed Render"
        }
    }
}

/// 会话切换只记录匿名的开始/完成区间；Session ID 只在内存里用于配对，
/// 不写入 signpost、日志或性能报告。
@MainActor
final class CoachSessionTransitionCoordinator {
    private var pending: (UUID, AppPerformanceInterval)?

    func begin(from current: UUID?, to incoming: UUID) {
        guard current != incoming else { return }
        if let (_, existing) = pending {
            AppPerformance.end(existing, detail: "result=interrupted")
        }
        pending = (
            incoming,
            AppPerformance.begin(
                .sessionTransition,
                detail: "from=current,to=selected"
            )
        )
    }

    func contentDidBecomeVisible(_ sessionID: UUID) {
        guard let (target, interval) = pending, target == sessionID else { return }
        AppPerformance.end(interval, detail: "result=visible")
        pending = nil
    }
}

struct AppPerformanceInterval {
    fileprivate let event: AppPerformanceEvent
    fileprivate let id: OSSignpostID
}

/// 引用本身由 Root 的 `@State` 保持稳定，内部变化不参与 SwiftUI Observation。
/// Tab 点击路径因此只为真正的选中态写一次 SwiftUI 状态。
@MainActor
final class AppTabTransitionCoordinator {
    private var pending: (AppTab, AppPerformanceInterval)?

    func begin(from current: AppTab, to incoming: AppTab) {
        if let (_, existing) = pending {
            AppPerformance.end(existing, detail: "result=interrupted")
        }
        pending = (
            incoming,
            AppPerformance.begin(
                .tabTransition,
                detail: "from=\(current.performanceName),to=\(incoming.performanceName)"
            )
        )
    }

    func contentDidBecomeVisible(_ tab: AppTab) {
        AppPerformance.event(
            .tabContentVisible,
            detail: "tab=\(tab.performanceName)"
        )
        guard let (target, interval) = pending, target == tab else { return }
        AppPerformance.end(
            interval,
            detail: "result=visible,tab=\(tab.performanceName)"
        )
        pending = nil
    }
}

enum AppPerformance {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "top.hedon.soma",
        category: .pointsOfInterest
    )

    @discardableResult
    static func begin(
        _ event: AppPerformanceEvent,
        detail: String = ""
    ) -> AppPerformanceInterval {
        let id = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: event.signpostName,
            signpostID: id,
            "%{public}s",
            detail
        )
        return AppPerformanceInterval(event: event, id: id)
    }

    static func end(
        _ interval: AppPerformanceInterval,
        detail: String = ""
    ) {
        os_signpost(
            .end,
            log: log,
            name: interval.event.signpostName,
            signpostID: interval.id,
            "%{public}s",
            detail
        )
    }

    static func event(
        _ event: AppPerformanceEvent,
        detail: String = ""
    ) {
        os_signpost(
            .event,
            log: log,
            name: event.signpostName,
            "%{public}s",
            detail
        )
    }
}
