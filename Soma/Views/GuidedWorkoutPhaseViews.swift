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
                .background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))

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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            VStack(spacing: 16) {
                Text("第 \(set?.order ?? 1) 组")
                    .font(.title2.bold())
                Text("\(remaining(at: context.date))")
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
    }

    private func remaining(at date: Date) -> Int {
        guard let phaseStartedAt else { return 3 }
        return max(3 - Int(date.timeIntervalSince(phaseStartedAt)), 1)
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
            Button("已完成：\(targetText)", action: onCompleted)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            HStack(spacing: 24) {
                Button("重新开始", action: onRedo)
                Button("跳过本组", action: onSkip)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GuidedRestView: View {
    let nextSet: WorkoutSet?
    let remainingSeconds: () -> Int
    let onAdjust: (Int) -> Void
    let onFinish: () -> Void

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
                    Text("下一组 · 第 \(nextSet.order) 组")
                        .font(.title3.bold())
                    Text(nextSetTarget(nextSet))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    Button("-15 秒") { onAdjust(-15) }
                        .buttonStyle(.bordered)
                    Button("+15 秒") { onAdjust(15) }
                        .buttonStyle(.bordered)
                }
                Button(remainingSeconds() == 0 ? "开始下一组" : "跳过休息") {
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func timeText(_ seconds: Int) -> String {
        String(
            format: "%02d:%02d",
            seconds / 60,
            seconds % 60
        )
    }

    private func nextSetTarget(_ set: WorkoutSet) -> String {
        var values: [String] = []
        if let weight = set.plannedWeightKG {
            values.append(weight == 0 ? "自重" : "\(weight.formatted()) kg")
        }
        if let reps = set.plannedReps {
            values.append("\(reps) 次")
        }
        return values.isEmpty ? "按状态完成" : values.joined(separator: " × ")
    }
}

struct GuidedSessionReviewView: View {
    let summary: String
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 70))
                .foregroundStyle(.green)
            Text("本次训练已完成")
                .font(.largeTitle.bold())
            Text(summary)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("完成训练", action: onFinish)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GuidedSetActualEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var reps: String
    @Binding var weight: String
    let targetText: String

    var body: some View {
        NavigationStack {
            Form {
                Section("本组实际完成") {
                    TextField("次数", text: $reps)
                        .keyboardType(.numberPad)
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
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
