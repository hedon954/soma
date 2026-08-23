import SwiftUI

struct TrainingResumeCard: View {
    let session: WorkoutSession

    private var orderedPerformances: [ExercisePerformance] {
        session.performances.sorted { $0.order < $1.order }
    }

    private var currentPerformance: ExercisePerformance? {
        guard let id = session.currentPerformanceID else {
            return orderedPerformances.first { $0.status == .pending || $0.status == .active }
        }
        return orderedPerformances.first { $0.id == id }
    }

    private var completedCount: Int {
        orderedPerformances.count { $0.status == .completed }
    }

    var body: some View {
        AppCard {
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
    let programs: [TrainingProgram]

    private var title: String {
        session.programNameSnapshot
            ?? programs.first { $0.id == session.programID }?.name
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
