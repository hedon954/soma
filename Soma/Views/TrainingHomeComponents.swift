import SwiftUI

/// `swipeActions` needs a List row, while the training root itself is a
/// ScrollView. A hidden intrinsic copy gives that one-row List the card's real
/// Dynamic Type height instead of clipping it with a fixed viewport.
struct TrainingResumeSwipeContainer: View {
    let session: WorkoutSession
    let onResume: () -> Void
    let onDelete: () -> Void

    var body: some View {
        TrainingResumeCard(session: session)
            .hidden()
            .accessibilityHidden(true)
            .overlay {
                List {
                    Button(action: onResume) {
                        TrainingResumeCard(session: session)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("删除未完成训练")
                        .tint(.red)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.vertical, 0, for: .scrollContent)
                .scrollDisabled(true)
            }
            .accessibilityIdentifier("resumable-workout-list")
    }
}

struct TrainingResumeCard: View {
    let session: WorkoutSession

    var body: some View {
        let orderedPerformances = session.performances.sorted { $0.order < $1.order }
        let currentPerformance: ExercisePerformance? = if let id = session.currentPerformanceID {
            orderedPerformances.first { $0.id == id }
        } else {
            orderedPerformances.first { $0.status == .pending || $0.status == .active }
        }
        let completedCount = orderedPerformances.count { $0.status == .completed }

        return AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("继续训练")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.trainingAccent)
                    Spacer()
                    Label("继续", systemImage: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.trainingAccent)
                        .labelStyle(.titleAndIcon)
                }

                Text(session.programNameSnapshot ?? "自由训练")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 6) {
                    if let currentPerformance {
                        Text(currentPerformance.exerciseName)
                    }
                    if !orderedPerformances.isEmpty {
                        Text("·")
                        Text("\(completedCount)/\(orderedPerformances.count) 个动作")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if !orderedPerformances.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(orderedPerformances) { performance in
                            Capsule()
                                .fill(progressColor(for: performance))
                                .frame(height: 5)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("已完成 \(completedCount) 个，共 \(orderedPerformances.count) 个动作")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("training-resume-card")
        .accessibilityHint("继续未完成的训练")
    }

    private func progressColor(for performance: ExercisePerformance) -> Color {
        switch performance.status {
        case .completed: AppTheme.trainingAccent
        case .active: AppTheme.trainingAccent.opacity(0.55)
        case .pending, .skipped: AppTheme.separator
        }
    }
}

struct TrainingProgramHomeCard: View {
    let program: TrainingProgram

    private var actionCount: Int? {
        let count = program.templateExercises.count
        return count == 0 ? nil : count
    }

    var body: some View {
        AppCard {
            HStack(spacing: 14) {
                Image(systemName: "dumbbell.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.trainingAccent)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.trainingSoftTint, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(program.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("查看训练计划")
    }

    private var detailText: String {
        var parts: [String] = []
        if let actionCount {
            parts.append("\(actionCount) 个动作")
        }
        if !program.scheduleHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(program.scheduleHint)
        }
        if parts.isEmpty, !program.overview.isEmpty {
            return program.overview
        }
        return parts.isEmpty ? "尚未填写计划内容" : parts.joined(separator: " · ")
    }
}

struct TrainingSessionHomeRow: View {
    let session: WorkoutSession
    let fallbackProgramName: String?

    private var title: String {
        session.programNameSnapshot
            ?? fallbackProgramName
            ?? "自由训练"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .foregroundStyle(AppTheme.trainingAccent)
                .frame(width: 32, height: 32)
                .background(AppTheme.trainingSoftTint, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
