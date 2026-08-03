import CoreGraphics
import Foundation

enum GuidedWorkoutPresentationMode: Equatable {
    case compact
    case expandedCapture
}

struct GuidedWorkoutPresentationState: Equatable {
    private(set) var mode = GuidedWorkoutPresentationMode.compact

    init(mode: GuidedWorkoutPresentationMode = .compact) {
        self.mode = mode
    }

    mutating func expand() {
        mode = .expandedCapture
    }

    mutating func collapse() {
        mode = .compact
    }

    mutating func cameraStateChanged(_ state: WorkoutCameraState) {
        if state == .recording {
            mode = .expandedCapture
        }
    }

    mutating func phaseChanged(_ phase: GuidedWorkoutPhase) {
        if phase != .setInProgress {
            mode = .compact
        }
    }
}

enum WorkoutCaptureLayout {
    static func previewAspectRatio(isLandscape: Bool) -> CGFloat {
        isLandscape ? 16 / 9 : 9 / 16
    }

    static func compactPreviewWidth(
        availableWidth: CGFloat,
        isLandscape: Bool
    ) -> CGFloat {
        let proposed = availableWidth * (isLandscape ? 0.18 : 0.31)
        let minimum: CGFloat = isLandscape ? 132 : 120
        let maximum: CGFloat = isLandscape ? 176 : 148
        return min(max(proposed, minimum), maximum)
    }

    static func landscapeControlWidth(availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth * 0.24, 214), 280)
    }

    static func landscapeCameraShare(availableWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 36
        let columnSpacing: CGFloat = 14
        let cameraWidth = availableWidth
            - horizontalPadding
            - columnSpacing
            - landscapeControlWidth(availableWidth: availableWidth)
        return max(cameraWidth / availableWidth, 0)
    }

    static func portraitCameraHeight(
        availableWidth: CGFloat,
        availableHeight: CGFloat
    ) -> CGFloat {
        min(
            availableWidth / previewAspectRatio(isLandscape: false),
            availableHeight * 0.52
        )
    }
}

enum WorkoutCameraSurfacePresentation: Equatable {
    case loading(String)
    case visible
    case failed(String)

    static func resolve(
        cameraState: WorkoutCameraState,
        isPreviewReady: Bool,
        previewIssueMessage: String?,
        recordingErrorMessage: String?
    ) -> WorkoutCameraSurfacePresentation {
        if let recordingErrorMessage {
            return .failed(recordingErrorMessage)
        }
        if let previewIssueMessage {
            return .failed(previewIssueMessage)
        }
        if case let .unavailable(message) = cameraState {
            return .failed(message)
        }
        switch cameraState {
        case .idle, .requestingPermission:
            return .loading("相机准备中…")
        case .previewing, .recording:
            return isPreviewReady
                ? .visible
                : .loading("正在连接相机画面…")
        case .unavailable:
            preconditionFailure("已在上方处理")
        }
    }
}

struct GuidedSetCountdownClock: Equatable {
    static let duration: TimeInterval = 3

    let startedAt: Date

    var deadline: Date {
        startedAt.addingTimeInterval(Self.duration)
    }

    func remaining(at date: Date) -> Int {
        max(Int(ceil(deadline.timeIntervalSince(date))), 0)
    }

    func delay(at date: Date) -> TimeInterval {
        max(deadline.timeIntervalSince(date), 0)
    }

    func isDue(at date: Date) -> Bool {
        date >= deadline
    }
}
