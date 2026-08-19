import Foundation
import SwiftUI

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
        } else {
            mode = .compact
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

    static func portraitCameraRegionHeight(
        availableHeight: CGFloat,
        headerHeight: CGFloat,
        controlsHeight: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        max(
            availableHeight - headerHeight - controlsHeight - spacing * 2,
            0
        )
    }
}

struct PortraitGuidedCaptureLayout: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        let resolved = proposal.replacingUnspecifiedDimensions()
        guard subviews.count == 3, proposal.height == nil else {
            return resolved
        }
        let rowProposal = ProposedViewSize(width: resolved.width, height: nil)
        let headerHeight = subviews[0].sizeThatFits(rowProposal).height
        let cameraHeight = subviews[1].sizeThatFits(rowProposal).height
        let controlsHeight = subviews[2].sizeThatFits(rowProposal).height
        return CGSize(
            width: resolved.width,
            height: headerHeight + cameraHeight + controlsHeight + spacing * 2
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        guard subviews.count == 3 else { return }
        let rowProposal = ProposedViewSize(width: bounds.width, height: nil)
        let headerSize = subviews[0].sizeThatFits(rowProposal)
        let controlsSize = subviews[2].sizeThatFits(rowProposal)
        let cameraRegionHeight = WorkoutCaptureLayout.portraitCameraRegionHeight(
            availableHeight: bounds.height,
            headerHeight: headerSize.height,
            controlsHeight: controlsSize.height,
            spacing: spacing
        )
        let cameraProposal = ProposedViewSize(
            width: bounds.width,
            height: cameraRegionHeight
        )

        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: rowProposal
        )
        subviews[1].place(
            at: CGPoint(
                x: bounds.midX,
                y: bounds.minY + headerSize.height + spacing
                    + cameraRegionHeight / 2
            ),
            anchor: .center,
            proposal: cameraProposal
        )
        subviews[2].place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY),
            anchor: .bottomLeading,
            proposal: rowProposal
        )
    }
}

enum GuidedWorkoutDisplayText {
    static func expandedActionTitle(
        exerciseName: String?,
        targetText: String
    ) -> String {
        let name = exerciseName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = name.flatMap { $0.isEmpty ? nil : $0 } ?? "当前动作"
        let inlineTarget = targetText.replacingOccurrences(of: " × ", with: "、")
        return "\(resolvedName)（\(inlineTarget)）"
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
        case .idle, .requestingPermission, .configuring, .startingSession,
             .startingRecording:
            return .loading(cameraState.message)
        case .previewing, .recording:
            return isPreviewReady
                ? .visible
                : .loading("正在连接相机画面…")
        case .unavailable:
            preconditionFailure("已在上方处理")
        }
    }
}

enum GuidedCameraSurfacePlacement: Equatable {
    case hidden
    case phasePictureInPicture
    case setHero

    static func resolve(
        phase: GuidedWorkoutPhase,
        cameraState: WorkoutCameraState,
        isStarting: Bool,
        sessionIsActive: Bool
    ) -> GuidedCameraSurfacePlacement {
        guard sessionIsActive,
              isStarting || cameraState != .idle
        else { return .hidden }
        switch phase {
        case .setInProgress:
            return .setHero
        case .ready, .exerciseIntroduction, .preSetCountdown,
             .setConfirmation, .resting:
            return .phasePictureInPicture
        case .sessionReview, .completed:
            return .hidden
        }
    }
}

struct GuidedRecordingControlPresentation: Equatable {
    enum Intent: Equatable {
        case start
        case cancelStarting
        case stop
    }

    let intent: Intent
    let systemImage: String
    let accessibilityLabel: String
    let hint: String
    let isEnabled: Bool

    static func resolve(
        surfaceIsVisible _: Bool,
        isRecording: Bool,
        isStarting: Bool,
        canStart: Bool,
        errorMessage: String?
    ) -> GuidedRecordingControlPresentation {
        if isStarting {
            return GuidedRecordingControlPresentation(
                intent: .cancelStarting,
                systemImage: "xmark.circle.fill",
                accessibilityLabel: "取消开启录像",
                hint: "点击取消本次开启",
                isEnabled: true
            )
        }
        if isRecording {
            return GuidedRecordingControlPresentation(
                intent: .stop,
                systemImage: "stop.circle.fill",
                accessibilityLabel: "停止当前录像",
                hint: "点击停止并保存当前录像",
                isEnabled: true
            )
        }
        return GuidedRecordingControlPresentation(
            intent: .start,
            systemImage: "video.badge.plus",
            accessibilityLabel: "录制当前组",
            hint: errorMessage.flatMap { $0.isEmpty ? nil : $0 }
                ?? "点击启动相机并录制当前组",
            isEnabled: canStart
        )
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
