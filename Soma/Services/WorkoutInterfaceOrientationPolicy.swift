import UIKit

@MainActor
final class WorkoutInterfaceOrientationPolicy {
    static let shared = WorkoutInterfaceOrientationPolicy()

    private(set) var isGuidedWorkoutActive = false

    var supportedOrientations: UIInterfaceOrientationMask {
        isGuidedWorkoutActive
            ? [.portrait, .landscapeLeft, .landscapeRight]
            : .portrait
    }

    func setGuidedWorkoutActive(_ isActive: Bool) {
        guard isGuidedWorkoutActive != isActive else { return }
        isGuidedWorkoutActive = isActive
        var requestedOrientations = supportedOrientations
        #if DEBUG
            if isActive,
               ProcessInfo.processInfo.environment["SOMA_GUIDED_FORCE_LANDSCAPE"] == "1"
            {
                requestedOrientations = .landscapeRight
            }
        #endif
        updateApplicationOrientation(requestedOrientations)
    }

    private func updateApplicationOrientation(
        _ requestedOrientations: UIInterfaceOrientationMask
    ) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            let controller = windowScene.windows
                .first(where: \.isKeyWindow)?
                .rootViewController
            controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
            windowScene.requestGeometryUpdate(
                .iOS(interfaceOrientations: requestedOrientations)
            ) { _ in
                // 系统方向锁定或场景切换时保持当前布局，训练仍可继续。
            }
        }
    }
}
