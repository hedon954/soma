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
                expiration()
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
