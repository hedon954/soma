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
    @State private var collapsedDays: Set<Date> = []

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

    private var monthChips: [(filter: WorkoutHistoryDateFilter, title: String)] {
        HistoryMonthFilterChips.chips(from: filterChoices)
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
                            : "试试调整筛选月份。"
                    )
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(dayGroups) { group in
                    let isExpanded = !collapsedDays.contains(group.day)
                    Section {
                        HistoryDayHeader(
                            title: group.title,
                            summary: group.actionCountText,
                            metric: group.totalKnownVolumeKG.map(HistoryDayMetrics.kilograms),
                            metricUnit: group.totalKnownVolumeKG == nil ? nil : "kg",
                            isExpanded: isExpanded,
                            toggle: { toggleDay(group.day) }
                        )
                        .historyDayCardRow(edge: isExpanded ? .top : .single)

                        if isExpanded {
                            ForEach(
                                Array(group.workouts.enumerated()),
                                id: \.element.id
                            ) { index, workout in
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
                                .historyDayCardRow(
                                    edge: index == group.workouts.count - 1 ? .bottom : .middle
                                )
                            }
                        }
                    }
                    .listSectionSeparator(.hidden)
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
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .historyListChrome(
            title: "训练记录",
            systemImage: "figure.strengthtraining.traditional",
            role: .training,
            selected: filter,
            chips: monthChips,
            onSelect: { filter = $0 }
        )
        .onAppear {
            if loaded.isEmpty {
                reload()
            }
        }
        .onChange(of: filter) { _, _ in
            reload()
        }
    }

    private func toggleDay(_ day: Date) {
        if collapsedDays.contains(day) {
            collapsedDays.remove(day)
        } else {
            collapsedDays.insert(day)
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
        try? GuidedWorkoutRecordStore.delete(workout, in: modelContext)
        if loaded.count < WorkoutHistoryQuery.pageSize, hasMore {
            loadMore()
        }
    }
}

struct MealHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealEntry.date, order: .reverse) private var allMeals: [MealEntry]

    @State private var filter = WorkoutHistoryDateFilter.all
    @State private var loaded: [MealEntry] = []
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var collapsedDays: Set<Date> = []

    private var dayGroups: [MealHistoryDayGroup] {
        MealHistoryQuery.groupedByDay(loaded)
    }

    private var monthChips: [(filter: WorkoutHistoryDateFilter, title: String)] {
        HistoryMonthFilterChips.chips(
            from: WorkoutHistoryQuery.filterChoices(from: allMeals.map(\.date))
        )
    }

    var body: some View {
        List {
            if loaded.isEmpty, !isLoading {
                ContentUnavailableView(
                    filter == .all ? "暂无饮食记录" : "没有符合筛选的记录",
                    systemImage: "fork.knife",
                    description: Text(
                        filter == .all
                            ? "把食物照片或描述发给教练，AI 会自动记录到这里。"
                            : "试试调整筛选月份。"
                    )
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(dayGroups) { group in
                    let isExpanded = !collapsedDays.contains(group.day)
                    Section {
                        HistoryDayHeader(
                            title: group.title,
                            summary: group.mealCountText,
                            metric: group.totalKnownCalories.map(HistoryDayMetrics.calories),
                            metricUnit: group.totalKnownCalories == nil ? nil : "kcal",
                            isExpanded: isExpanded,
                            toggle: { toggleDay(group.day) }
                        )
                        .historyDayCardRow(edge: isExpanded ? .top : .single)

                        if isExpanded {
                            ForEach(
                                Array(group.meals.enumerated()),
                                id: \.element.id
                            ) { index, meal in
                                NavigationLink {
                                    MealRecordDetailView(meal: meal)
                                } label: {
                                    MealHistoryRow(meal: meal)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(meal)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .accessibilityLabel("删除饮食记录")
                                    .tint(.red)
                                }
                                .historyDayCardRow(
                                    edge: index == group.meals.count - 1 ? .bottom : .middle
                                )
                            }
                        }
                    }
                    .listSectionSeparator(.hidden)
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
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .historyListChrome(
            title: "饮食记录",
            systemImage: "fork.knife",
            role: .meal,
            selected: filter,
            chips: monthChips,
            onSelect: { filter = $0 }
        )
        .onAppear {
            if loaded.isEmpty {
                reload()
            }
        }
        .onChange(of: filter) { _, _ in
            reload()
        }
    }

    private func toggleDay(_ day: Date) {
        if collapsedDays.contains(day) {
            collapsedDays.remove(day)
        } else {
            collapsedDays.insert(day)
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

        let descriptor = MealHistoryQuery.fetchDescriptor(
            filter: filter,
            offset: loaded.count
        )
        do {
            let page = try modelContext.fetch(descriptor)
            loaded.append(contentsOf: page)
            hasMore = page.count >= MealHistoryQuery.pageSize
        } catch {
            hasMore = false
        }
    }

    private func delete(_ meal: MealEntry) {
        loaded.removeAll { $0.id == meal.id }
        modelContext.delete(meal)
        try? modelContext.save()
        if loaded.count < MealHistoryQuery.pageSize, hasMore {
            loadMore()
        }
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

            // PRD 020：行内只保留名称、时间与一组主指标；肌群、评分与热量在详情查看。
            VStack(alignment: .leading, spacing: 5) {
                Text(exercise?.canonicalName ?? workout.exercise)
                    .font(.headline)
                Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !metricsText.isEmpty {
                    Text(metricsText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var workoutThumbnail: some View {
        if let video = workout.mediaAttachments.first(where: { $0.kind == .video }) {
            MediaThumbnail(
                kind: .video,
                path: video.path,
                fallbackIcon: "figure.strengthtraining.traditional",
                width: 42,
                height: 74
            )
        } else if let exercise {
            ExerciseArtworkView(
                reference: exercise.preferredActionIllustration,
                contentMode: .fill
            )
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
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
                fallbackIcon: meal.mealType.icon,
                width: meal.mediaAttachments.first?.kind == .video ? 42 : 58,
                height: meal.mediaAttachments.first?.kind == .video ? 74 : 58,
                role: .meal
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(meal.title)
                    .font(.headline)
                Text("\(meal.mealType.rawValue) · \(meal.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(macrosText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(meal.calories.map(String.init) ?? "—")
                .font(.subheadline.bold().monospacedDigit())
            Text("kcal")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var macrosText: String {
        let protein = meal.protein.map {
            "蛋白质 \($0.formatted(.number.precision(.fractionLength(0 ... 1))))g"
        } ?? "蛋白质 —"
        let carbs = meal.carbs.map {
            "碳水 \($0.formatted(.number.precision(.fractionLength(0 ... 1))))g"
        } ?? "碳水 —"
        return "\(protein) · \(carbs)"
    }
}

private struct BodyHistoryRow: View {
    let entry: BodyEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MediaThumbnail(
                kind: entry.mediaAttachments.first?.kind ?? .none,
                path: entry.mediaAttachments.first?.path,
                fallbackIcon: "scalemass",
                role: .body
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
        .padding(.vertical, 6)
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
