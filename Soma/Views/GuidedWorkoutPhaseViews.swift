import SwiftUI

struct GuidedExerciseIntroductionView: View {
    let exercise: ExerciseDefinition?
    let performance: ExercisePerformance?
    let onPrepare: () -> Void
    let onReplace: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(performance?.exerciseName ?? "准备动作")
                    .font(.system(.largeTitle, design: .rounded).bold())

                ExerciseArtworkView(
                    reference: exercise?.preferredActionIllustration
                        ?? BundledExerciseCatalog.fallbackActionIllustration
                )
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 26))

                Label(
                    exercise?.coachingNotes.nilIfBlank
                        ?? "确认器械和动作空间，准备后开始第一组。",
                    systemImage: "arrow.up.right.circle.fill"
                )
                .font(.body)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))

                Button(action: onPrepare) {
                    Text("准备本动作")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                HStack {
                    Button("替换动作", action: onReplace)
                    Spacer()
                    Button("跳过动作", action: onSkip)
                }
                .font(.subheadline)
            }
            .padding(20)
        }
    }
}

struct GuidedSetCountdownView: View {
    let set: WorkoutSet?
    let targetText: String
    let phaseStartedAt: Date?
    var deadlineAt: Date?
    let onTick: (Int) -> Void
    let onFinished: @MainActor () async -> Void

    private var clock: GuidedSetCountdownClock {
        GuidedSetCountdownClock(
            startedAt: deadlineAt?.addingTimeInterval(
                -GuidedSetCountdownClock.duration
            ) ?? phaseStartedAt ?? .now
        )
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            VStack(spacing: 16) {
                Text("第 \(set?.order ?? 1) 组")
                    .font(.title2.bold())
                Text("\(clock.remaining(at: context.date))")
                    .font(.system(size: 108, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.green)
                Text(targetText)
                    .font(.title.bold())
                Text("倒计时结束后开始本组")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: deadlineAt ?? phaseStartedAt) {
            do {
                var announced: Set<Int> = []
                while !clock.isDue(at: .now) {
                    let value = clock.remaining(at: .now)
                    if (1 ... 3).contains(value), announced.insert(value).inserted {
                        onTick(value)
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard !Task.isCancelled else { return }
                await onFinished()
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }
}

struct GuidedPausedView: View {
    let onResume: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            Text("训练已暂停")
                .font(.largeTitle.bold())
            Text("未完成录像已经停止；继续后请确认本组状态。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("继续训练", systemImage: "play.fill", action: onResume)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GuidedSetRecoveryView: View {
    let targetText: String
    var effortSide: WorkoutEffortSide = .none
    var isCompletingEffort = false
    let onCompleted: () -> Void
    let onRedo: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 62))
                .foregroundStyle(.orange)
            Text("刚才这一组怎么样？")
                .font(.largeTitle.bold())
            Text("Soma 不会自动把中断的组记为完成。")
                .foregroundStyle(.secondary)
            if isCompletingEffort {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在保存本组…")
                }
                .font(.headline)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在保存本组")
            } else {
                Button("已完成：\(targetText)", action: onCompleted)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            HStack(spacing: 24) {
                Button("重新开始", action: onRedo)
                Button(skipTitle, action: onSkip)
            }
            .disabled(isCompletingEffort)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var skipTitle: String {
        let side = WorkoutPrescriptionFormatter.sideName(effortSide)
        return side.isEmpty ? "跳过本组" : "跳过\(side)"
    }
}

struct GuidedRestView: View {
    let nextSet: WorkoutSet?
    var nextEffort: WorkoutEffort?
    let remainingSeconds: () -> Int
    let onTick: (Int) -> Void
    let onAdjust: (Int) -> Void
    let onFinish: () -> Void
    @State private var automaticallyFinishedTargetID: UUID?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(spacing: 20) {
                Text("休息")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
                Text(timeText(remainingSeconds()))
                    .font(.system(size: 84, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if let nextSet {
                    Text(nextEffort?.side == .right
                        ? "下一侧 · 右侧"
                        : "下一组 · 第 \(nextSet.order) 组")
                        .font(.title3.bold())
                    Text(WorkoutPrescriptionFormatter.setTarget(
                        set: nextSet,
                        effort: nextEffort
                    ))
                    .foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    Button("-15 秒") { onAdjust(-15) }
                        .buttonStyle(.bordered)
                    Button("+15 秒") { onAdjust(15) }
                        .buttonStyle(.bordered)
                }
                Button("跳过休息") {
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: nextEffort?.id ?? nextSet?.id) {
            var announced: Set<Int> = []
            while !Task.isCancelled {
                let value = remainingSeconds()
                if value == 0 {
                    let targetID = nextEffort?.id ?? nextSet?.id
                    guard automaticallyFinishedTargetID != targetID else {
                        return
                    }
                    automaticallyFinishedTargetID = targetID
                    onFinish()
                    return
                }
                if (1 ... 3).contains(value), announced.insert(value).inserted {
                    onTick(value)
                }
                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }

    private func timeText(_ seconds: Int) -> String {
        String(
            format: "%02d:%02d",
            seconds / 60,
            seconds % 60
        )
    }
}

struct GuidedSessionReviewView: View {
    let summary: TrainingSessionSummary
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                VStack(spacing: 6) {
                    Text("本次训练已完成")
                        .font(.largeTitle.bold())
                    Text(summary.text)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    metric("时长", summary.durationText)
                    metric(
                        "完整 / 部分",
                        "\(summary.completedSets) / \(summary.partialSets) 组"
                    )
                    metric("录像", "\(summary.recordedVideoCount) 组")
                }

                if !summary.exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("动作完成情况")
                            .font(.headline)
                        ForEach(summary.exercises) { exercise in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(exercise.name)
                                        .font(.subheadline.bold())
                                    Text(exerciseDetail(exercise))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: exercise.completedSets > 0
                                    ? "checkmark.circle.fill"
                                    : (exercise.partialSets > 0
                                        ? "circle.lefthalf.filled"
                                        : "minus.circle"))
                                    .foregroundStyle(
                                        exercise.completedSets > 0
                                            || exercise.partialSets > 0
                                            ? .green
                                            : .secondary
                                    )
                            }
                            .padding(14)
                            .background(
                                Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("查看分享", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private func exerciseDetail(_ exercise: TrainingExerciseSummary) -> String {
        var values = ["完成 \(exercise.completedSets) 组"]
        if exercise.partialSets > 0 {
            values.append("部分 \(exercise.partialSets) 组")
        }
        if exercise.skippedSets > 0 {
            values.append("跳过 \(exercise.skippedSets) 组")
        }
        if exercise.failedSets > 0 {
            values.append("失败 \(exercise.failedSets) 组")
        }
        if exercise.completedVolume > 0 {
            values.append(
                "容量 \(exercise.completedVolume.formatted(.number.precision(.fractionLength(0 ... 1)))) kg"
            )
        }
        return values.joined(separator: " · ")
    }
}

enum GuidedSessionFinalizationState: Equatable {
    case saving
    case failed(String)

    var canRetry: Bool {
        if case .failed = self {
            return true
        }
        return false
    }

    var failureMessage: String? {
        guard case let .failed(message) = self else { return nil }
        return message
    }
}

struct GuidedSessionFinalizationView: View {
    let state: GuidedSessionFinalizationState
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch state {
            case .saving:
                ProgressView()
                    .controlSize(.large)
                Text("正在保存训练…")
                    .font(.headline)
            case let .failed(message):
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("训练尚未保存完成")
                    .font(.title2.bold())
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("重试保存", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("重新保存训练记录并打开分享界面")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GuidedSetActualEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var reps: String
    @Binding var duration: String
    @Binding var weight: String
    let targetText: String
    let targetKind: WorkoutTargetKind
    let side: WorkoutEffortSide
    var onSave: () -> Void = {}

    var body: some View {
        NavigationStack {
            Form {
                Section(sectionTitle) {
                    if targetKind == .repetitions {
                        TextField("次数", text: $reps)
                            .keyboardType(.numberPad)
                    } else {
                        TextField("时长（秒）", text: $duration)
                            .keyboardType(.numberPad)
                    }
                    TextField("重量 kg，0 表示自重", text: $weight)
                        .keyboardType(.decimalPad)
                }
                Section {
                    LabeledContent("将记录", value: targetText)
                }
            }
            .navigationTitle("编辑本组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var sectionTitle: String {
        let sideName = WorkoutPrescriptionFormatter.sideName(side)
        return sideName.isEmpty ? "本组实际完成" : "\(sideName)实际完成"
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
