import AVFoundation
import SwiftUI

struct GuidedWorkoutChrome: View {
    let session: WorkoutSession
    let completedExerciseCount: Int
    let exerciseCount: Int
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
                            .frame(width: 42, height: 42)
                            .background(.thinMaterial, in: Circle())
                        Text(session.status == .paused ? "继续" : "暂停")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityLabel(session.status == .paused ? "继续训练" : "暂停训练")

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
                            .frame(width: 42, height: 42)
                            .background(.thinMaterial, in: Circle())
                        Text("更多")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("更多训练操作")
            }

            ProgressView(
                value: Double(completedExerciseCount),
                total: Double(max(exerciseCount, 1))
            )
            .tint(.green)
        }
    }

    private func elapsedText(at date: Date) -> String {
        let total = max(Int(date.timeIntervalSince(session.startedAt)), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
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
    let coachingNote: String
    let isLandscape: Bool
    let showsCamera: Bool
    let isStartingRecording: Bool
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
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .lineLimit(2)
                Spacer()
                if let performance {
                    Text("动作 \(performance.order)/\(max(performanceCount, 1))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ExerciseArtworkView(
                        reference: exercise?.preferredActionIllustration
                            ?? BundledExerciseCatalog.fallbackActionIllustration
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 26))

                    if showsCamera {
                        Button(action: onExpandCamera) {
                            WorkoutCameraSurface(
                                camera: camera,
                                showsSafeFrame: false,
                                compact: true,
                                recordingErrorMessage: cameraErrorMessage
                            )
                            .allowsHitTesting(false)
                            .frame(width: WorkoutCaptureLayout.compactPreviewWidth(
                                availableWidth: proxy.size.width,
                                isLandscape: isLandscape
                            ))
                            .aspectRatio(
                                WorkoutCaptureLayout.previewAspectRatio(
                                    isLandscape: isLandscape
                                ),
                                contentMode: .fit
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                            .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
                        }
                        .buttonStyle(.plain)
                        .contentShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                        .padding(12)
                        .accessibilityLabel(camera.state == .recording
                            ? "正在录制，放大相机"
                            : "放大相机预览")
                    }
                }
            }
        }
    }

    /// PRD 020：执行面以「完成本组」为唯一主操作；录制与跳过收入次级菜单，
    /// 教练提示按需展开，组进度以文字呈现。
    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(setProgressText)
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.green.opacity(0.08), in: Capsule())
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
                            .frame(width: 36, height: 36)
                            .background(.thinMaterial, in: Circle())
                    }
                    .foregroundStyle(showsCoachingNote ? .green : .secondary)
                    .accessibilityLabel("教练提示")
                    .accessibilityValue(showsCoachingNote ? "已展开" : "已收起")

                    Menu {
                        if !showsCamera {
                            Button(action: onRecord) {
                                if isStartingRecording {
                                    Label("正在开启相机…", systemImage: "camera.fill")
                                } else {
                                    Label("录制本组", systemImage: "record.circle")
                                }
                            }
                            .disabled(!canStartRecording || isStartingRecording)
                        }
                        Button("跳过本组", systemImage: "forward.end", action: onSkip)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline)
                            .frame(width: 36, height: 36)
                            .background(.thinMaterial, in: Circle())
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("本组更多操作")
                    .accessibilityHint(recordingButtonHint)
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
                    .background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            }

            Button(action: onComplete) {
                Text("完成：\(targetText)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var setProgressText: String {
        guard let set else { return "本组目标" }
        let base = "第 \(set.order)/\(max(sets.count, 1)) 组"
        return set.kind == .warmup ? "\(base) · 热身" : base
    }

    private var recordingButtonHint: String {
        if isStartingRecording {
            return "正在开启相机"
        }
        if !canStartRecording {
            return "当前已有录像进行中"
        }
        if let cameraErrorMessage, !cameraErrorMessage.isEmpty {
            return cameraErrorMessage
        }
        return "只有开始录像后才会调用相机"
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
                        .frame(width: 38, height: 38)
                        .background(.thinMaterial, in: Circle())
                }
                .accessibilityLabel("暂停训练")

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
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: Circle())
            }
            .foregroundStyle(.primary)
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
                    + " · 第 \(set?.order ?? 1)/\(sets.count) 组"
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
                .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            if !isLandscape {
                Button("编辑本组", systemImage: "pencil", action: onEdit)
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .buttonStyle(.plain)
            }
            Button(action: onComplete) {
                Text("完成本组")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isLandscape ? 4 : 7)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(isLandscape ? 14 : 0)
        .background {
            if isLandscape {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
        }
    }

    private func elapsedText(at date: Date) -> String {
        let total = max(Int(date.timeIntervalSince(sessionStartedAt)), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
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
                videoGravity: compact ? .resizeAspectFill : .resizeAspect
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
                compact
                    ? (camera.state == .recording ? "录制中" : "取景")
                    : (camera.state == .recording ? "正在录制" : "完整取景"),
                systemImage: camera.state == .recording
                    ? "record.circle.fill"
                    : "viewfinder"
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
        HStack(spacing: 0) {
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(circleFill(for: set))
                            .frame(width: 30, height: 30)
                        if set.status == .completed {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        } else {
                            Text("\(set.order)")
                                .font(.caption.bold())
                                .foregroundStyle(set.id == currentSetID ? .white : .secondary)
                        }
                    }
                    Text(set.kind == .warmup ? "热身" : "第\(set.order)组")
                        .font(.caption2)
                        .foregroundStyle(set.id == currentSetID ? .green : .secondary)
                        .lineLimit(1)
                }
                if index < sets.count - 1 {
                    Rectangle()
                        .fill(set.status == .completed ? Color.green : Color.secondary.opacity(0.25))
                        .frame(height: 2)
                        .padding(.bottom, 22)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progressAccessibilityLabel)
    }

    private func circleFill(for set: WorkoutSet) -> Color {
        if set.status == .completed {
            return .green
        }
        if set.id == currentSetID {
            return .green.opacity(0.85)
        }
        return Color.secondary.opacity(0.12)
    }

    private var progressAccessibilityLabel: String {
        let completed = sets.count { $0.status == .completed }
        return "已完成 \(completed) 组，共 \(sets.count) 组"
    }
}
