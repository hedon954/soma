import SwiftData
import SwiftUI

struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]

    var body: some View {
        List {
            if workouts.isEmpty {
                ContentUnavailableView(
                    "暂无训练记录",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("在教练对话中描述训练，AI 会自动记录到这里。")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(workouts) { workout in
                    NavigationLink {
                        WorkoutRecordDetailView(workout: workout)
                    } label: {
                        WorkoutHistoryRow(workout: workout)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(workout)
                            try? modelContext.save()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("删除训练记录")
                        .tint(.red)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle("训练记录")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct MealHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]

    var body: some View {
        List {
            if meals.isEmpty {
                ContentUnavailableView(
                    "暂无饮食记录",
                    systemImage: "fork.knife",
                    description: Text("把食物照片或描述发给教练，AI 会自动记录到这里。")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(meals) { meal in
                    NavigationLink {
                        MealRecordDetailView(meal: meal)
                    } label: {
                        MealHistoryRow(meal: meal)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(meal)
                            try? modelContext.save()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("删除饮食记录")
                        .tint(.red)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle("饮食记录")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct BodyHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyEntry.date, order: .reverse) private var entries: [BodyEntry]

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "暂无体重记录",
                    systemImage: "scalemass",
                    description: Text("把体重数字、体重秤或体型照片发给教练，AI 会自动记录到这里。")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(entries) { entry in
                    NavigationLink {
                        BodyRecordDetailView(entry: entry)
                    } label: {
                        BodyHistoryRow(entry: entry)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(entry)
                            try? modelContext.save()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("删除身体记录")
                        .tint(.red)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle("体重记录")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct WorkoutHistoryRow: View {
    let workout: WorkoutEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MediaThumbnail(
                kind: workout.mediaAttachments.first?.kind ?? .none,
                path: workout.mediaAttachments.first?.path,
                fallbackIcon: "figure.strengthtraining.traditional"
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(workout.exercise)
                    .font(.headline)
                Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !metricsText.isEmpty {
                    Text(metricsText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if let score = workout.formScore {
                Text("\(score)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(score >= 85 ? AppTheme.tint : AppTheme.warning)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var metricsText: String {
        var metrics: [String] = []
        if let sets = workout.sets, let reps = workout.reps {
            metrics.append("\(sets) 组 × \(reps) 次")
        } else {
            if let sets = workout.sets {
                metrics.append("\(sets) 组")
            }
            if let reps = workout.reps {
                metrics.append("\(reps) 次")
            }
        }
        if let weight = workout.weight {
            metrics.append(
                weight == 0
                    ? "自重"
                    : "\(weight.formatted(.number.precision(.fractionLength(0 ... 1)))) kg"
            )
        }
        if let rest = workout.restSeconds {
            metrics.append("间歇 \(rest)s")
        }
        if let duration = workout.durationMinutes {
            metrics.append("\(duration) 分钟")
        }
        if let calories = workout.estimatedCalories {
            metrics.append("约 \(calories) kcal")
        }
        return metrics.joined(separator: " · ")
    }
}

private struct MealHistoryRow: View {
    let meal: MealEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MediaThumbnail(
                kind: meal.mediaAttachments.first?.kind ?? .none,
                path: meal.mediaAttachments.first?.path,
                fallbackIcon: meal.mealType.icon
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(meal.title)
                    .font(.headline)
                Text("\(meal.mealType.rawValue) · \(meal.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("蛋白质 \(meal.protein.formatted(.number.precision(.fractionLength(0 ... 1))))g · 碳水 \(meal.carbs.formatted(.number.precision(.fractionLength(0 ... 1))))g")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(meal.calories)")
                .font(.subheadline.bold().monospacedDigit())
            Text("kcal")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct BodyHistoryRow: View {
    let entry: BodyEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MediaThumbnail(
                kind: entry.mediaAttachments.first?.kind ?? .none,
                path: entry.mediaAttachments.first?.path,
                fallbackIcon: "scalemass"
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Text(secondaryMetrics)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let weight = entry.weight {
                Text(weight.formatted(.number.precision(.fractionLength(1))))
                    .font(.title3.bold().monospacedDigit())
                Text("kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var secondaryMetrics: String {
        var metrics: [String] = []
        if let bodyFat = entry.bodyFat {
            metrics.append("体脂 \(bodyFat.formatted(.number.precision(.fractionLength(1))))%")
        }
        if let waist = entry.waist {
            metrics.append("腰围 \(waist.formatted(.number.precision(.fractionLength(1))))cm")
        }
        return metrics.isEmpty ? "身体趋势记录" : metrics.joined(separator: " · ")
    }
}
