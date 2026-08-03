import UIKit

@MainActor
final class WorkoutInterfaceOrientationPolicy {
    static let shared = WorkoutInterfaceOrientationPolicy()

    private(set) var isGuidedWorkoutActive = false
    private var orientationObserver: NSObjectProtocol?

    var supportedOrientations: UIInterfaceOrientationMask {
        Self.supportedOrientations(
            isGuidedWorkoutActive: isGuidedWorkoutActive
        )
    }

    static func supportedOrientations(
        isGuidedWorkoutActive: Bool
    ) -> UIInterfaceOrientationMask {
        isGuidedWorkoutActive
            ? [.portrait, .landscapeLeft, .landscapeRight]
            : .portrait
    }

    static func requestedOrientation(
        for deviceOrientation: UIDeviceOrientation
    ) -> UIInterfaceOrientationMask? {
        switch deviceOrientation {
        case .portrait, .portraitUpsideDown:
            .portrait
        case .landscapeLeft:
            .landscapeRight
        case .landscapeRight:
            .landscapeLeft
        case .faceUp, .faceDown, .unknown:
            nil
        @unknown default:
            nil
        }
    }

    func setGuidedWorkoutActive(_ isActive: Bool) {
        let didChange = isGuidedWorkoutActive != isActive
        isGuidedWorkoutActive = isActive
        guard didChange || isActive else { return }
        if isActive {
            installOrientationObservationIfNeeded()
        } else {
            removeOrientationObservation()
        }

        var requestedOrientations = isActive
            ? Self.requestedOrientation(for: UIDevice.current.orientation)
            ?? supportedOrientations
            : .portrait
        #if DEBUG
            if isActive,
               ProcessInfo.processInfo.environment["SOMA_GUIDED_FORCE_LANDSCAPE"] == "1"
            {
                requestedOrientations = .landscapeRight
            }
        #endif
        updateApplicationOrientation(requestedOrientations)
    }

    private func installOrientationObservationIfNeeded() {
        guard orientationObserver == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      isGuidedWorkoutActive,
                      let requested = Self.requestedOrientation(
                          for: UIDevice.current.orientation
                      )
                else {
                    return
                }
                updateApplicationOrientation(requested)
            }
        }
    }

    private func removeOrientationObservation() {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
            self.orientationObserver = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
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
