import SwiftData
import SwiftUI

struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseDefinition.canonicalName) private var exercises: [ExerciseDefinition]
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var allWorkouts: [WorkoutEntry]

    @State private var filter = WorkoutHistoryDateFilter.all
    @State private var loaded: [WorkoutEntry] = []
    @State private var hasMore = true
    @State private var isLoading = false

    private var dayGroups: [WorkoutHistoryDayGroup] {
        WorkoutHistoryQuery.groupedByDay(loaded)
    }

    private var filterChoices: (
        years: [Int],
        monthsByYear: [Int: [Int]],
        daysByYearMonth: [Int: [Int: [Int]]]
    ) {
        WorkoutHistoryQuery.filterChoices(from: allWorkouts.map(\.date))
    }

    var body: some View {
        List {
            if loaded.isEmpty, !isLoading {
                ContentUnavailableView(
                    filter == .all ? "暂无训练记录" : "没有符合筛选的记录",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text(
                        filter == .all
                            ? "在教练对话中描述训练，AI 会自动记录到这里。"
                            : "试试调整年、月或日筛选条件。"
                    )
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(dayGroups) { group in
                    Section {
                        ForEach(group.workouts) { workout in
                            NavigationLink {
                                WorkoutRecordDetailView(workout: workout)
                            } label: {
                                WorkoutHistoryRow(
                                    workout: workout,
                                    exercise: resolvedExercise(for: workout)
                                )
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(workout)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("删除训练记录")
                                .tint(.red)
                            }
                        }
                    } header: {
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }

                if hasMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 12)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .onAppear {
                        loadMore()
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle("训练记录")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu
            }
        }
        .onAppear {
            if loaded.isEmpty {
                reload()
            }
        }
        .onChange(of: filter) { _, _ in
            reload()
        }
    }

    private var filterMenu: some View {
        Menu {
            Button("全部") { filter = .all }
            Divider()
            yearPickerSection
            monthPickerSection
            dayPickerSection
        } label: {
            Label(filter.label, systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("筛选训练记录")
    }

    @ViewBuilder
    private var yearPickerSection: some View {
        let years = filterChoices.years
        if !years.isEmpty {
            Menu("按年") {
                ForEach(years, id: \.self) { year in
                    Button("\(year)年") { filter = .year(year) }
                }
            }
        }
    }

    @ViewBuilder
    private var monthPickerSection: some View {
        let choices = filterChoices
        let baseYear: Int? = switch filter {
        case let .year(year), let .yearMonth(year, _), let .day(year, _, _):
            year
        case .all:
            choices.years.first
        }
        if let baseYear, let months = choices.monthsByYear[baseYear], !months.isEmpty {
            Menu("按月（\(baseYear)年）") {
                ForEach(months, id: \.self) { month in
                    Button("\(month)月") {
                        filter = .yearMonth(year: baseYear, month: month)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dayPickerSection: some View {
        let choices = filterChoices
        let yearMonth: (year: Int, month: Int)? = {
            switch filter {
            case let .yearMonth(year, month), let .day(year, month, _):
                return (year, month)
            case let .year(year):
                guard let month = choices.monthsByYear[year]?.first else { return nil }
                return (year, month)
            case .all:
                guard let year = choices.years.first,
                      let month = choices.monthsByYear[year]?.first
                else { return nil }
                return (year, month)
            }
        }()
        if let yearMonth,
           let days = choices.daysByYearMonth[yearMonth.year]?[yearMonth.month],
           !days.isEmpty
        {
            Menu("按日（\(yearMonth.year)年\(yearMonth.month)月）") {
                ForEach(days, id: \.self) { day in
                    Button("\(day)日") {
                        filter = .day(
                            year: yearMonth.year,
                            month: yearMonth.month,
                            day: day
                        )
                    }
                }
            }
        }
    }

    private func resolvedExercise(for workout: WorkoutEntry) -> ExerciseDefinition? {
        if let exerciseID = workout.exerciseID {
            if let match = exercises.first(where: { $0.id == exerciseID }) {
                return match
            }
        }
        let name = workout.exercise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let key = ExerciseLibraryStore.canonicalNameKey(name)
        return exercises.first {
            !$0.isArchived && $0.canonicalNameKey == key
        }
    }

    private func reload() {
        loaded = []
        hasMore = true
        isLoading = false
        loadMore()
    }

    private func loadMore() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let descriptor = WorkoutHistoryQuery.fetchDescriptor(
            filter: filter,
            offset: loaded.count
        )
        do {
            let page = try modelContext.fetch(descriptor)
            ExerciseLibraryStore.linkExistingExercises(
                for: page,
                in: modelContext
            )
            loaded.append(contentsOf: page)
            hasMore = page.count >= WorkoutHistoryQuery.pageSize
        } catch {
            hasMore = false
        }
    }

    private func delete(_ workout: WorkoutEntry) {
        loaded.removeAll { $0.id == workout.id }
        modelContext.delete(workout)
        try? modelContext.save()
        if loaded.count < WorkoutHistoryQuery.pageSize, hasMore {
            loadMore()
        }
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
    var exercise: ExerciseDefinition?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            workoutThumbnail

            VStack(alignment: .leading, spacing: 5) {
                Text(exercise?.canonicalName ?? workout.exercise)
                    .font(.headline)
                Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let muscles = exercise?.primaryMuscles, !muscles.isEmpty {
                    Text(muscles.joined(separator: "、"))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.tint)
                        .lineLimit(1)
                }
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

    @ViewBuilder
    private var workoutThumbnail: some View {
        if let exercise {
            ExerciseArtworkView(
                reference: exercise.preferredActionIllustration,
                contentMode: .fill
            )
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel("\(exercise.canonicalName)示意图")
        } else if let image = workout.mediaAttachments.first(where: { $0.kind == .image }) {
            MediaThumbnail(
                kind: .image,
                path: image.path,
                fallbackIcon: "figure.strengthtraining.traditional"
            )
        } else {
            MediaThumbnail(
                kind: .none,
                path: nil,
                fallbackIcon: "figure.strengthtraining.traditional"
            )
        }
    }

    private var metricsText: String {
        var metrics: [String] = []
        if let setEvidenceSummary = workout.setEvidenceSummary {
            metrics.append(setEvidenceSummary)
        } else if let sets = workout.sets, let reps = workout.reps {
            metrics.append("\(sets) 组 × \(reps) 次")
        } else {
            if let sets = workout.sets {
                metrics.append("\(sets) 组")
            }
            if let reps = workout.reps {
                metrics.append("\(reps) 次")
            }
        }
        if workout.setEntries.isEmpty, let weight = workout.weight {
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
