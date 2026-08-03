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
    let onExpandCamera: () -> Void
    let onEdit: () -> Void
    let onComplete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        if isLandscape {
            HStack(spacing: 22) {
                hero
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                controls
                    .frame(width: 320)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        } else {
            VStack(spacing: 16) {
                hero
                    .frame(maxHeight: .infinity)
                controls
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
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
                            compact: true
                        )
                        .frame(width: isLandscape ? 120 : 92)
                        .aspectRatio(
                            camera.captureGeometry.orientation.aspectRatio,
                            contentMode: .fit
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(.white.opacity(0.8), lineWidth: 2)
                        }
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
                    }
                    .buttonStyle(.plain)
                    .padding(14)
                    .accessibilityLabel(camera.state == .recording
                        ? "正在录制，放大相机"
                        : "放大相机预览")
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本组目标")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.green.opacity(0.08), in: Capsule())
                    Text(targetText)
                        .font(.system(size: isLandscape ? 38 : 46, weight: .bold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                Spacer()
                Button("编辑", systemImage: "pencil", action: onEdit)
                    .font(.subheadline)
                    .buttonStyle(.bordered)
            }

            GuidedSetProgressRail(sets: sets, currentSetID: set?.id)

            Label(coachingNote, systemImage: "lightbulb.fill")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))

            Button(action: onComplete) {
                Text("完成：\(targetText)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("跳过本组", action: onSkip)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
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
    let onCollapse: () -> Void
    let onPause: () -> Void
    let onComplete: () -> Void
    let onEdit: () -> Void
    let onMore: () -> Void

    var body: some View {
        Group {
            if isLandscape {
                landscapeBody
            } else {
                portraitBody
            }
        }
        .padding(isLandscape ? 18 : 16)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private var landscapeBody: some View {
        VStack(spacing: 12) {
            captureHeader
            HStack(spacing: 16) {
                cameraSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                controlPanel
                    .frame(width: 320)
            }
        }
    }

    private var portraitBody: some View {
        VStack(spacing: 14) {
            captureHeader
            cameraSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            controlPanel
        }
    }

    private var captureHeader: some View {
        HStack {
            Button(action: onCollapse) {
                Label("收起", systemImage: "chevron.down")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
            }
            .foregroundStyle(.primary)
            .accessibilityHint("录像会继续")
            Spacer()
            HStack(spacing: 10) {
                Button(action: onPause) {
                    Image(systemName: "pause.fill")
                }
                .accessibilityLabel("暂停训练")

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedText(at: context.date))
                        .font(.headline.monospacedDigit())
                }
            }
            .buttonStyle(.bordered)
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
            compact: false
        )
        .aspectRatio(
            camera.captureGeometry.orientation.aspectRatio,
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
        VStack(alignment: .leading, spacing: isLandscape ? 10 : 14) {
            HStack(alignment: .lastTextBaseline) {
                Text(targetText)
                    .font(.system(size: isLandscape ? 34 : 42, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Spacer()
                Button("编辑", systemImage: "pencil", action: onEdit)
                    .buttonStyle(.bordered)
            }
            GuidedSetProgressRail(sets: sets, currentSetID: set?.id)
            Label(coachingNote, systemImage: "lightbulb.fill")
                .font(.subheadline)
                .lineLimit(isLandscape ? 2 : 3)
                .padding(isLandscape ? 10 : 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
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

    var body: some View {
        ZStack {
            Color.black
            WorkoutCameraPreview(camera: camera)
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
