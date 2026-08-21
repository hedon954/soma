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

    mutating func cameraStateChanged(
        _: WorkoutCameraState,
        isStartingRecording _: Bool = false
    ) {}

    mutating func phaseChanged(
        _ phase: GuidedWorkoutPhase,
        expandForRecording: Bool = false
    ) {
        if phase == .setInProgress {
            if expandForRecording {
                mode = .expandedCapture
            }
        } else {
            mode = .compact
        }
    }
}

enum GuidedExpandedCaptureVisibility {
    static func isVisible(
        sessionIsActive: Bool,
        mode: GuidedWorkoutPresentationMode,
        phase: GuidedWorkoutPhase,
        cameraState: WorkoutCameraState,
        isStartingRecording: Bool
    ) -> Bool {
        guard sessionIsActive,
              mode == .expandedCapture,
              phase == .setInProgress
        else { return false }
        switch cameraState {
        case .previewing, .startingSession, .startingRecording, .recording,
             .configuring, .requestingPermission:
            return true
        case .idle, .unavailable:
            return isStartingRecording
        }
    }
}

enum WorkoutCaptureLayout {
    static func previewAspectRatio(isLandscape: Bool) -> CGFloat {
        isLandscape ? 16 / 9 : 9 / 16
    }

    static func compactPreviewSize(isLandscape: Bool) -> CGSize {
        let width: CGFloat = isLandscape ? 210 : 132
        let ratio = previewAspectRatio(isLandscape: isLandscape)
        return CGSize(width: width, height: width / ratio)
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

struct GuidedCompactCameraPreview: View {
    let camera: WorkoutCameraService
    let isLandscape: Bool
    let recordingErrorMessage: String?
    var onExpand: (() -> Void)?

    var body: some View {
        let size = WorkoutCaptureLayout.compactPreviewSize(isLandscape: isLandscape)
        let preview = WorkoutCameraSurface(
            camera: camera,
            showsSafeFrame: false,
            compact: true,
            recordingErrorMessage: recordingErrorMessage
        )
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)

        if let onExpand {
            preview
                .overlay {
                    Color.clear
                        .contentShape(
                            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                        )
                }
                .onTapGesture(perform: onExpand)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("放大相机")
                .accessibilityLabel(
                    camera.state == .recording ? "正在录制，放大相机" : "相机取景，放大相机"
                )
        } else {
            preview
        }
    }
}

enum GuidedPictureInPictureLayout {
    static let edgePadding: CGFloat = 12

    static func defaultTrailingOffset(
        containerSize: CGSize,
        previewSize: CGSize
    ) -> CGSize {
        let maxX = max((containerSize.width - previewSize.width) / 2, 0)
        return clampedOffset(
            CGSize(width: maxX - edgePadding, height: 0),
            containerSize: containerSize,
            previewSize: previewSize
        )
    }

    static func trailingFrameOrigin(
        containerSize: CGSize,
        previewSize: CGSize
    ) -> CGPoint {
        let offset = defaultTrailingOffset(
            containerSize: containerSize,
            previewSize: previewSize
        )
        return CGPoint(
            x: (containerSize.width - previewSize.width) / 2 + offset.width,
            y: (containerSize.height - previewSize.height) / 2 + offset.height
        )
    }

    static func clampedOffset(
        _ offset: CGSize,
        containerSize: CGSize,
        previewSize: CGSize
    ) -> CGSize {
        let maxX = max((containerSize.width - previewSize.width) / 2, 0)
        let maxY = max((containerSize.height - previewSize.height) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
}

struct GuidedDraggableCompactCameraPreview: View {
    let camera: WorkoutCameraService
    let isLandscape: Bool
    let recordingErrorMessage: String?
    var onExpand: (() -> Void)?
    let containerSize: CGSize
    @State private var offset: CGSize?
    @GestureState private var dragTranslation = CGSize.zero

    var body: some View {
        let previewSize = WorkoutCaptureLayout.compactPreviewSize(
            isLandscape: isLandscape
        )
        let restOffset = offset ?? GuidedPictureInPictureLayout.defaultTrailingOffset(
            containerSize: containerSize,
            previewSize: previewSize
        )
        let displayed = GuidedPictureInPictureLayout.clampedOffset(
            CGSize(
                width: restOffset.width + dragTranslation.width,
                height: restOffset.height + dragTranslation.height
            ),
            containerSize: containerSize,
            previewSize: previewSize
        )
        ZStack {
            GuidedCompactCameraPreview(
                camera: camera,
                isLandscape: isLandscape,
                recordingErrorMessage: recordingErrorMessage,
                onExpand: onExpand
            )
            .offset(x: displayed.width, y: displayed.height)
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .highPriorityGesture(
            DragGesture(minimumDistance: 8)
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    offset = GuidedPictureInPictureLayout.clampedOffset(
                        CGSize(
                            width: restOffset.width + value.translation.width,
                            height: restOffset.height + value.translation.height
                        ),
                        containerSize: containerSize,
                        previewSize: previewSize
                    )
                }
        )
        .accessibilityHint("按住可拖动预览窗")
    }
}

extension View {
    func guidedPictureInPicture(
        camera: WorkoutCameraService?,
        isLandscape: Bool,
        recordingErrorMessage: String?,
        onExpand: (() -> Void)? = nil
    ) -> some View {
        overlay {
            if let camera {
                GeometryReader { geo in
                    GuidedDraggableCompactCameraPreview(
                        camera: camera,
                        isLandscape: isLandscape,
                        recordingErrorMessage: recordingErrorMessage,
                        onExpand: onExpand,
                        containerSize: geo.size
                    )
                }
            }
        }
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
        sessionIsActive: Bool,
        isCaptureTarget: Bool
    ) -> GuidedCameraSurfacePlacement {
        guard sessionIsActive,
              isCaptureTarget,
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

enum GuidedPreviewHostSettlement {
    static func isSettled(
        currentHostID: UUID?,
        previousHostID: UUID?
    ) -> Bool {
        guard let currentHostID else { return false }
        return currentHostID != previousHostID
    }

    static func hasLivePreview(
        layerHasSession: Bool,
        cameraState: WorkoutCameraState
    ) -> Bool {
        guard layerHasSession else { return false }
        switch cameraState {
        case .requestingPermission, .configuring, .startingSession,
             .previewing, .startingRecording, .recording:
            return true
        case .idle, .unavailable:
            return false
        }
    }

    static func shouldRebuildCaptureConnections(
        cameraState: WorkoutCameraState,
        hasLivePreview: Bool = false
    ) -> Bool {
        switch cameraState {
        case .startingRecording, .recording:
            false
        case .configuring, .startingSession, .previewing:
            !hasLivePreview
        case .idle, .requestingPermission, .unavailable:
            true
        }
    }

    static func shouldReuseRunningCaptureSession(
        state: WorkoutCameraState,
        sessionIsRunning: Bool,
        sessionIsInterrupted: Bool
    ) -> Bool {
        guard sessionIsRunning, !sessionIsInterrupted else { return false }
        if case .unavailable = state {
            return false
        }
        return true
    }

    static func shouldIgnoreTransientPreviewInterruption(
        reasonCode: String,
        hasActiveAttempt: Bool,
        hasSessionOwner: Bool
    ) -> Bool {
        reasonCode == "session-interruption"
            && !hasActiveAttempt
            && hasSessionOwner
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
