import UIKit

@MainActor
protocol BackgroundExecutionLease: AnyObject {
    var isActive: Bool { get }
    func begin(expiration: @escaping @MainActor () -> Void)
    func end()
}

@MainActor
final class UIKitBackgroundExecutionLease: BackgroundExecutionLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    var isActive: Bool {
        identifier != .invalid
    }

    func begin(expiration: @escaping @MainActor () -> Void) {
        end()
        identifier = UIApplication.shared.beginBackgroundTask(
            withName: "Soma.AgentJob"
        ) { [weak self] in
            Task { @MainActor in
                // 系统已经要求收口时，先归还 lease，再做持久化和取消。
                // 不能让 SwiftData save 或繁忙的 MainActor 延长系统等待窗口。
                self?.end()
                expiration()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
