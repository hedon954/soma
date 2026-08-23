import AVFoundation
import SwiftUI

enum GuidedWorkoutProgressSetState: Equatable {
    case pending
    case current
    case completed
    case partial
    case skipped
    case failed
}

struct GuidedWorkoutProgressExercise: Identifiable, Equatable {
    struct SetSegment: Identifiable, Equatable {
        let id: UUID
        let state: GuidedWorkoutProgressSetState
        let completionFraction: Double

        init(
            id: UUID,
            state: GuidedWorkoutProgressSetState,
            completionFraction: Double = 0
        ) {
            self.id = id
            self.state = state
            self.completionFraction = min(max(completionFraction, 0), 1)
        }
    }

    let id: UUID
    let sets: [SetSegment]

    static func completionFraction(
        set: WorkoutSet,
        efforts: [WorkoutEffort]
    ) -> Double {
        if set.status == .completed {
            return 1
        }
        guard !efforts.isEmpty else { return 0 }
        let terminalCount = efforts.count {
            $0.status == .completed
        }
        return Double(terminalCount) / Double(efforts.count)
    }
}

enum GuidedCameraStatusPresentation: Equatable {
    case preparing(String)
    case ready(String)
    case recording(String)
    case warning(String)

    static func resolve(
        cameraState: WorkoutCameraState,
        isStarting: Bool,
        isQueued: Bool,
        automaticRecordingPaused: Bool,
        statusMessage: String?
    ) -> GuidedCameraStatusPresentation? {
        if case let .unavailable(message) = cameraState {
            return .warning(
                automaticRecordingPaused ? (statusMessage ?? message) : message
            )
        }
        if isStarting
            || cameraState == .requestingPermission
            || cameraState == .configuring
            || cameraState == .startingSession
            || cameraState == .startingRecording
        {
            return .preparing(statusMessage ?? "正在启动相机，请稍候…")
        }
        if let statusMessage, !statusMessage.isEmpty,
           automaticRecordingPaused
        {
            return .warning(statusMessage)
        }
        if cameraState == .recording {
            return .recording(statusMessage ?? "正在录像。")
        }
        if cameraState == .previewing {
            return .ready(statusMessage ?? (isQueued
                    ? "相机已就绪，下一组将自动开始录像。"
                    : "相机已就绪，可随时开始录像。"))
        }
        if let statusMessage, !statusMessage.isEmpty {
            return .warning(statusMessage)
        }
        if isQueued {
            return .preparing("已预约下一组录像，正在等待相机就绪。")
        }
        return nil
    }

    var message: String {
        switch self {
        case let .preparing(message), let .ready(message),
             let .recording(message), let .warning(message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .preparing:
            "camera.aperture"
        case .ready:
            "viewfinder"
        case .recording:
            "record.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        }
    }

    var offersSettingsRecovery: Bool {
        guard case let .warning(message) = self else { return false }
        return message.contains("系统设置")
    }
}

struct GuidedWorkoutChrome: View {
    let session: WorkoutSession
    let completedExerciseCount: Int
    let exerciseCount: Int
    var progressExercises: [GuidedWorkoutProgressExercise] = []
    var isRecording = false
    var isStartingRecording = false
    var isRecordingQueued = false
    var automaticRecordingPaused = false
    var cameraState: WorkoutCameraState = .idle
    var recordingStatusMessage: String?
    var onRecord: () -> Void = {}
    var onOpenCameraSettings: () -> Void = {}
    let onPause: () -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onPause) {
                    VStack(spacing: 3) {
                        Image(systemName: session.status == .paused
                            ? "play.fill"
                            : "pause.fill")
                            .font(.headline)
                            .frame(
                                width: AppTheme.minimumTapTarget,
                                height: AppTheme.minimumTapTarget
                            )
                            .background(.thinMaterial, in: Circle())
                        Text(session.status == .paused ? "继续" : "暂停")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityLabel(session.status == .paused ? "继续训练" : "暂停训练")

                Button(action: onRecord) {
                    VStack(spacing: 3) {
                        Image(systemName: recordingSystemImage)
                            .font(.headline)
                            .frame(
                                width: AppTheme.minimumTapTarget,
                                height: AppTheme.minimumTapTarget
                            )
                            .background(.thinMaterial, in: Circle())
                        Text(recordingLabel)
                            .font(.caption2)
                    }
                }
                .foregroundStyle(
                    isRecording || isStartingRecording || isRecordingQueued
                        ? .red
                        : .green
                )
                .accessibilityLabel(recordingAccessibilityLabel)

                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 2) {
                        Text(elapsedText(at: context.date))
                            .font(.title2.bold().monospacedDigit())
                        Text("已训练")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()

                Button(action: onEnd) {
                    VStack(spacing: 3) {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .frame(
                                width: AppTheme.minimumTapTarget,
                                height: AppTheme.minimumTapTarget
                            )
                            .background(.thinMaterial, in: Circle())
                        Text("更多")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("更多训练操作")
            }

            segmentedProgress

            if let cameraStatus {
                HStack(spacing: 10) {
                    Label(cameraStatus.message, systemImage: cameraStatus.systemImage)
                        .font(.caption)
                        .foregroundStyle(cameraStatusForeground(cameraStatus))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if cameraStatus.offersSettingsRecovery {
                        Button("打开设置", action: onOpenCameraSettings)
                            .font(.caption.bold())
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    } else if case .warning = cameraStatus,
                              !isStartingRecording,
                              !isRecording
                    {
                        Button("手动重试", action: onRecord)
                            .font(.caption.bold())
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityHint("重新启动相机并预约下一组录像")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    cameraStatusBackground(cameraStatus),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var cameraStatus: GuidedCameraStatusPresentation? {
        GuidedCameraStatusPresentation.resolve(
            cameraState: cameraState,
            isStarting: isStartingRecording,
            isQueued: isRecordingQueued,
            automaticRecordingPaused: automaticRecordingPaused,
            statusMessage: recordingStatusMessage
        )
    }

    private func cameraStatusForeground(
        _ status: GuidedCameraStatusPresentation
    ) -> Color {
        switch status {
        case .warning:
            AppTheme.warning
        case .recording:
            AppTheme.destructive
        case .preparing, .ready:
            .secondary
        }
    }

    private func cameraStatusBackground(
        _ status: GuidedCameraStatusPresentation
    ) -> Color {
        switch status {
        case .warning:
            AppTheme.warningSoftTint
        case .recording:
            AppTheme.destructive.opacity(0.07)
        case .preparing, .ready:
            .secondary.opacity(0.08)
        }
    }

    @ViewBuilder
    private var segmentedProgress: some View {
        if progressExercises.isEmpty {
            ProgressView(
                value: Double(completedExerciseCount),
                total: Double(max(exerciseCount, 1))
            )
            .tint(AppTheme.success)
        } else {
            HStack(spacing: 5) {
                ForEach(progressExercises) { exercise in
                    HStack(spacing: 1.5) {
                        let segments = exercise.sets.isEmpty
                            ? [GuidedWorkoutProgressExercise.SetSegment(
                                id: exercise.id,
                                state: .pending
                            )]
                            : exercise.sets
                        ForEach(segments) { segment in
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(color(for: segment.state))
                                    if segment.completionFraction > 0,
                                       segment.state != .skipped,
                                       segment.state != .failed
                                    {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(AppTheme.success)
                                            .frame(
                                                width: proxy.size.width
                                                    * segment.completionFraction
                                            )
                                    }
                                    segmentStatusOverlay(segment.state)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(height: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("训练进度")
            .accessibilityValue(progressAccessibilityValue)
        }
    }

    private func color(
        for state: GuidedWorkoutProgressSetState
    ) -> Color {
        switch state {
        case .pending:
            Color.secondary.opacity(0.18)
        case .current:
            AppTheme.success.opacity(0.55)
        case .completed:
            AppTheme.success
        case .partial:
            Color.secondary.opacity(0.18)
        case .skipped:
            Color.secondary.opacity(0.45)
        case .failed:
            AppTheme.destructive.opacity(0.18)
        }
    }

    @ViewBuilder
    private func segmentStatusOverlay(
        _ state: GuidedWorkoutProgressSetState
    ) -> some View {
        switch state {
        case .current:
            RoundedRectangle(cornerRadius: 3)
                .stroke(AppTheme.success, lineWidth: 1.5)
        case .partial:
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .skipped:
            Image(systemName: "forward.end.fill")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(AppTheme.destructive)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .pending, .completed:
            EmptyView()
        }
    }

    private var progressAccessibilityValue: String {
        let allSets = progressExercises.flatMap(\.sets)
        let terminalSets = allSets.count {
            $0.state == .completed
                || $0.state == .partial
                || $0.state == .skipped
                || $0.state == .failed
        }
        return "已完成 \(completedExerciseCount)/\(max(exerciseCount, 1)) 个动作，已结束 \(terminalSets)/\(allSets.count) 组"
    }

    private func elapsedText(at date: Date) -> String {
        let total = max(Int(date.timeIntervalSince(session.startedAt)), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var recordingSystemImage: String {
        if isStartingRecording {
            return "xmark.circle.fill"
        }
        if isRecording {
            return "stop.circle.fill"
        }
        return isRecordingQueued ? "video.circle.fill" : "video.badge.plus"
    }

    private var recordingLabel: String {
        if isStartingRecording {
            return "取消"
        }
        if isRecording {
            return "停止"
        }
        if isRecordingQueued {
            return "已预约"
        }
        return automaticRecordingPaused ? "重试" : "录像"
    }

    private var recordingAccessibilityLabel: String {
        if isStartingRecording {
            return "取消开启录像"
        }
        if isRecording {
            return "停止当前录像"
        }
        if isRecordingQueued {
            return "取消下一动作侧录像"
        }
        if automaticRecordingPaused {
            return "手动重试录像"
        }
        return "下一动作侧开始录像"
    }
}

struct GuidedCompactSetView: View {
    let camera: WorkoutCameraService
    let exercise: ExerciseDefinition?
    let performance: ExercisePerformance?
    let performanceCount: Int
    let set: WorkoutSet?
    let sets: [WorkoutSet]
    let targetText: String
    var effortSide: WorkoutEffortSide = .none
    var isAutomaticDuration = false
    var remainingDurationSeconds: Int?
    var durationDeadlineAt: Date?
    var completionErrorMessage: String?
    let coachingNote: String
    let isLandscape: Bool
    let showsCamera: Bool
    let isRecording: Bool
    let isStartingRecording: Bool
    var isCompletingEffort = false
    let canStartRecording: Bool
    let cameraErrorMessage: String?
    let onExpandCamera: () -> Void
    let onRecord: () -> Void
    let onEdit: () -> Void
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var showsCoachingNote = false

    var body: some View {
        GeometryReader { proxy in
            if isLandscape {
                HStack(spacing: 16) {
                    hero
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    controls
                        .frame(width: WorkoutCaptureLayout.landscapeControlWidth(
                            availableWidth: proxy.size.width
                        ))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 14) {
                    hero
                        .frame(maxHeight: .infinity)
                    controls
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(performance?.exerciseName ?? "当前动作")
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                if let performance {
                    Text("动作 \(performance.order)/\(max(performanceCount, 1))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { _ in
                ExerciseArtworkView(
                    reference: exercise?.preferredActionIllustration
                        ?? BundledExerciseCatalog.fallbackActionIllustration
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .guidedPictureInPicture(
                    camera: showsCamera ? camera : nil,
                    isLandscape: isLandscape,
                    recordingErrorMessage: cameraErrorMessage,
                    onExpand: onExpandCamera
                )
            }
        }
    }

    /// 执行面以「完成本组」为唯一主操作；录像保持常驻可见，跳过留在次级菜单，
    /// 教练提示按需展开，组进度以文字呈现。
    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(setProgressText)
                            .font(.caption)
                            .foregroundStyle(AppTheme.tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppTheme.softTint, in: Capsule())
                        HStack(spacing: 6) {
                            Text(targetText)
                                .font(.system(
                                    size: isLandscape ? 28 : 30,
                                    weight: .semibold
                                ))
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                            Image(systemName: "pencil")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isCompletingEffort)
                .accessibilityLabel("本组目标 \(targetText)")
                .accessibilityHint("点击编辑本组实际次数和重量")

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsCoachingNote.toggle()
                        }
                    } label: {
                        Image(systemName: "lightbulb")
                            .font(.subheadline)
                            .frame(
                                width: AppTheme.minimumTapTarget,
                                height: AppTheme.minimumTapTarget
                            )
                            .background(.thinMaterial, in: Circle())
                    }
                    .foregroundStyle(showsCoachingNote ? AppTheme.tint : .secondary)
                    .disabled(isCompletingEffort)
                    .accessibilityLabel("教练提示")
                    .accessibilityValue(showsCoachingNote ? "已展开" : "已收起")

                    Button(action: onRecord) {
                        Image(systemName: recordingControl.systemImage)
                            .font(.subheadline)
                            .frame(
                                width: AppTheme.minimumTapTarget,
                                height: AppTheme.minimumTapTarget
                            )
                            .background(.thinMaterial, in: Circle())
                    }
                    .foregroundStyle(
                        isRecording || isStartingRecording ? .red : AppTheme.tint
                    )
                    .disabled(
                        isCompletingEffort || !recordingControl.isEnabled
                    )
                    .accessibilityLabel(recordingControl.accessibilityLabel)
                    .accessibilityHint(recordingControl.hint)

                    Menu {
                        Button(skipButtonTitle, systemImage: "forward.end", action: onSkip)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline)
                            .frame(
                                width: AppTheme.minimumTapTarget,
                                height: AppTheme.minimumTapTarget
                            )
                            .background(.thinMaterial, in: Circle())
                    }
                    .foregroundStyle(.secondary)
                    .disabled(isCompletingEffort)
                    .accessibilityLabel("本组更多操作")
                    .accessibilityHint(skipButtonTitle)
                }
            }

            if isStartingRecording {
                Text("正在开启相机，请稍候。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let cameraErrorMessage, !cameraErrorMessage.isEmpty {
                Text(cameraErrorMessage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsCoachingNote {
                Label(coachingNote, systemImage: "lightbulb.fill")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        AppTheme.insetBackground,
                        in: RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                    )
            }

            if isCompletingEffort {
                completionProgress
            } else if isAutomaticDuration {
                if let completionErrorMessage {
                    VStack(spacing: 10) {
                        Label(
                            completionErrorMessage,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        Button("重试完成并保存", action: onComplete)
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.accentEmphasis)
                            .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Label(
                            "剩余 \(durationRemaining(at: context.date)) 秒，到时自动完成",
                            systemImage: "timer"
                        )
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(AppTheme.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.softTint, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            } else {
                Button(action: onComplete) {
                    Text("完成：\(targetText)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accentEmphasis)
                .controlSize(.large)
            }
        }
    }

    private var completionProgress: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("正在保存本组…")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在保存本组")
    }

    private var setProgressText: String {
        guard let set else { return "本组目标" }
        let side = WorkoutPrescriptionFormatter.sideName(effortSide)
        let kind = set.kind == .warmup ? "热身" : "当前目标"
        return side.isEmpty ? kind : "\(side) · \(kind)"
    }

    private var recordingControl: GuidedRecordingControlPresentation {
        GuidedRecordingControlPresentation.resolve(
            surfaceIsVisible: showsCamera,
            isRecording: isRecording,
            isStarting: isStartingRecording,
            canStart: canStartRecording,
            errorMessage: cameraErrorMessage
        )
    }

    private var skipButtonTitle: String {
        let side = WorkoutPrescriptionFormatter.sideName(effortSide)
        return side.isEmpty ? "跳过本组" : "跳过\(side)"
    }

    private func durationRemaining(at date: Date) -> Int {
        guard let durationDeadlineAt else {
            return remainingDurationSeconds ?? 0
        }
        return max(Int(ceil(durationDeadlineAt.timeIntervalSince(date))), 0)
    }
}

struct GuidedExpandedCaptureView: View {
    let camera: WorkoutCameraService
    let sessionStartedAt: Date
    let performance: ExercisePerformance?
    let performanceCount: Int
    let set: WorkoutSet?
    let sets: [WorkoutSet]
    let targetText: String
    var effortSide: WorkoutEffortSide = .none
    var isAutomaticDuration = false
    var remainingDurationSeconds: Int?
    var durationDeadlineAt: Date?
    var isCompletingEffort = false
    let coachingNote: String
    let isLandscape: Bool
    let cameraErrorMessage: String?
    let onCollapse: () -> Void
    let onPause: () -> Void
    let onComplete: () -> Void
    let onEdit: () -> Void
    let onMore: () -> Void

    var body: some View {
        GeometryReader { proxy in
            if isLandscape {
                landscapeBody(availableWidth: proxy.size.width)
            } else {
                portraitBody
            }
        }
        .padding(isLandscape ? 18 : 16)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private func landscapeBody(availableWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            captureHeader
            HStack(spacing: 14) {
                cameraSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                controlPanel
                    .frame(width: WorkoutCaptureLayout.landscapeControlWidth(
                        availableWidth: availableWidth
                    ))
            }
        }
    }

    private var portraitBody: some View {
        PortraitGuidedCaptureLayout(spacing: 12) {
            captureHeader
            cameraSurface
            controlPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var captureHeader: some View {
        HStack {
            Button(action: onCollapse) {
                if isLandscape {
                    Label("收起", systemImage: "chevron.down")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                } else {
                    Image(systemName: "xmark")
                        .font(.headline.bold())
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: Circle())
                }
            }
            .foregroundStyle(.primary)
            .accessibilityHint("录像会继续")
            Spacer()
            HStack(spacing: 10) {
                Button(action: onPause) {
                    Image(systemName: "pause.fill")
                        .frame(
                            width: AppTheme.minimumTapTarget,
                            height: AppTheme.minimumTapTarget
                        )
                        .background(.thinMaterial, in: Circle())
                }
                .accessibilityLabel("暂停训练")
                .disabled(isCompletingEffort)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 7) {
                        if camera.state == .recording {
                            Circle()
                                .fill(.red)
                                .frame(width: 9, height: 9)
                        }
                        Text(elapsedText(at: context.date))
                            .font(.headline.monospacedDigit())
                    }
                }
            }
            Spacer()
            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .frame(
                        width: AppTheme.minimumTapTarget,
                        height: AppTheme.minimumTapTarget
                    )
                    .background(.thinMaterial, in: Circle())
            }
            .foregroundStyle(.primary)
            .disabled(isCompletingEffort)
            .accessibilityLabel("更多训练操作")
        }
    }

    private var cameraSurface: some View {
        WorkoutCameraSurface(
            camera: camera,
            showsSafeFrame: true,
            compact: false,
            recordingErrorMessage: cameraErrorMessage
        )
        .aspectRatio(
            WorkoutCaptureLayout.previewAspectRatio(
                isLandscape: isLandscape
            ),
            contentMode: .fit
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .bottom) {
            Text(
                "动作 \(performance?.order ?? 1)/\(max(performanceCount, 1))"
            )
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.58), in: Capsule())
            .padding(12)
        }
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: isLandscape ? 12 : 10) {
            Text(GuidedWorkoutDisplayText.expandedActionTitle(
                exerciseName: performance?.exerciseName,
                targetText: targetText
            ))
            .font(.title3.bold())
            .lineLimit(2)
            GuidedSetProgressRail(sets: sets, currentSetID: set?.id)
            Label(coachingNote, systemImage: "lightbulb.fill")
                .font(.subheadline)
                .lineLimit(isLandscape ? 2 : 3)
                .padding(isLandscape ? 10 : 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.insetBackground, in: RoundedRectangle(cornerRadius: 16))
            if !isLandscape {
                Button("编辑本组", systemImage: "pencil", action: onEdit)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.tint)
                    .buttonStyle(.plain)
                    .disabled(isCompletingEffort)
            }
            if isCompletingEffort {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在保存本组…")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, isLandscape ? 8 : 14)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在保存本组")
            } else if isAutomaticDuration {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(
                        "剩余 \(durationRemaining(at: context.date)) 秒",
                        systemImage: "timer"
                    )
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(AppTheme.tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isLandscape ? 8 : 14)
                    .background(AppTheme.softTint, in: RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Button(action: onComplete) {
                    Text(effortSide == .none
                        ? "完成本组"
                        : "完成\(WorkoutPrescriptionFormatter.sideName(effortSide))")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isLandscape ? 4 : 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accentEmphasis)
                .controlSize(.large)
            }
        }
        .padding(isLandscape ? 14 : 0)
        .background {
            if isLandscape {
                RoundedRectangle(cornerRadius: 24)
                    .fill(AppTheme.cardBackground)
            }
        }
    }

    private func elapsedText(at date: Date) -> String {
        let total = max(Int(date.timeIntervalSince(sessionStartedAt)), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func durationRemaining(at date: Date) -> Int {
        guard let durationDeadlineAt else {
            return remainingDurationSeconds ?? 0
        }
        return max(Int(ceil(durationDeadlineAt.timeIntervalSince(date))), 0)
    }
}

struct WorkoutCameraSurface: View {
    let camera: WorkoutCameraService
    let showsSafeFrame: Bool
    let compact: Bool
    let recordingErrorMessage: String?

    var body: some View {
        ZStack {
            Color.black
            WorkoutCameraPreview(
                camera: camera,
                videoGravity: .resizeAspectFill
            )
            switch presentation {
            case let .loading(message):
                ProgressView(message)
                    .tint(.white)
                    .foregroundStyle(.white)
            case let .failed(message):
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(message)
                }
                .font(.caption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(18)
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
                .padding(14)
            case .visible:
                EmptyView()
            }
            if showsSafeFrame {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        .green.opacity(0.58),
                        style: StrokeStyle(lineWidth: 3, dash: [10, 8])
                    )
                    .padding(26)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topLeading) {
            Label(
                compactPreviewBadgeText,
                systemImage: camera.state == .recording
                    ? "record.circle.fill"
                    : (camera.state == .startingRecording
                        ? "camera.aperture"
                        : "viewfinder")
            )
            .font(compact ? .caption2.bold() : .caption.bold())
            .foregroundStyle(camera.state == .recording ? .white : .primary)
            .padding(.horizontal, compact ? 7 : 10)
            .padding(.vertical, compact ? 5 : 7)
            .background(
                camera.state == .recording
                    ? Color.black.opacity(0.62)
                    : Color.white.opacity(0.78),
                in: Capsule()
            )
            .padding(compact ? 7 : 12)
        }
    }

    private var compactPreviewBadgeText: String {
        if camera.state == .recording {
            return compact ? "录制中" : "正在录制"
        }
        if camera.state == .startingRecording {
            return "正在开启录像"
        }
        return compact ? "取景" : "完整取景"
    }

    private var presentation: WorkoutCameraSurfacePresentation {
        WorkoutCameraSurfacePresentation.resolve(
            cameraState: camera.state,
            isPreviewReady: camera.isPreviewReady,
            previewIssueMessage: camera.previewIssueMessage,
            recordingErrorMessage: recordingErrorMessage
        )
    }
}

struct GuidedSetProgressRail: View {
    let sets: [WorkoutSet]
    let currentSetID: UUID?

    var body: some View {
        HStack(spacing: 7) {
            ForEach(sets) { set in
                Capsule()
                    .fill(segmentFill(for: set))
                    .frame(height: 6)
                    .overlay {
                        if set.status == .partial {
                            Capsule()
                                .fill(AppTheme.tint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .scaleEffect(x: 0.5, anchor: .leading)
                        }
                    }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progressAccessibilityLabel)
    }

    private func segmentFill(for set: WorkoutSet) -> Color {
        if set.status == .completed {
            return AppTheme.tint
        }
        if set.status == .partial {
            return AppTheme.separator
        }
        if set.id == currentSetID {
            return AppTheme.trainingAccent
        }
        if set.status == .skipped || set.status == .failed {
            return Color.secondary.opacity(0.38)
        }
        return AppTheme.separator
    }

    private var progressAccessibilityLabel: String {
        let completed = sets.count { $0.status == .completed }
        let partial = sets.count { $0.status == .partial }
        return "已完整完成 \(completed) 组，部分完成 \(partial) 组，共 \(sets.count) 组"
    }
}
