import SwiftData
import SwiftUI

struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var filter = WorkoutHistoryDateFilter.all
    @State private var loaded: [WorkoutEntry] = []
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var collapsedDays: Set<Date> = []
    @State private var availableDates: Set<Date> = []
    @State private var shareModel: WorkoutSharePosterModel?
    @State private var shareErrorMessage: String?

    private var dayGroups: [WorkoutHistoryDayGroup] {
        WorkoutHistoryQuery.groupedByDay(loaded)
    }

    private var filterChoices: (
        years: [Int],
        monthsByYear: [Int: [Int]],
        daysByYearMonth: [Int: [Int: [Int]]]
    ) {
        WorkoutHistoryQuery.filterChoices(from: Array(availableDates))
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
                            toggle: { toggleDay(group.day) },
                            shareAction: { shareWorkoutDay(group.day) }
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
                                        exercise: workout.exerciseDefinition
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
        .task {
            if loaded.isEmpty {
                await Task.yield()
                reload()
            }
        }
        .onChange(of: filter) { _, _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { notification in
            guard ModelContextSaveImpact.affectsInsights(notification, in: modelContext) else { return }
            refreshLoadedWorkouts()
        }
        .sheet(item: $shareModel) { model in
            WorkoutShareSheet(model: model)
        }
        .alert(
            "无法分享训练",
            isPresented: Binding(
                get: { shareErrorMessage != nil },
                set: {
                    if !$0 {
                        shareErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(shareErrorMessage ?? "")
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

    private func refreshLoadedWorkouts() {
        let count = max(loaded.count, WorkoutHistoryQuery.pageSize)
        var query = WorkoutHistoryQuery.fetchDescriptor(filter: filter, offset: 0)
        query.fetchLimit = count + 1
        guard let rows = try? modelContext.fetch(query) else { return }
        loaded = Array(rows.prefix(count))
        hasMore = rows.count > count
        availableDates.formUnion(loaded.map(\.date))
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
            availableDates.formUnion(page.map(\.date))
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

    private func shareWorkoutDay(_ day: Date) {
        do {
            guard let model = try WorkoutSharePosterBuilder.makeModel(
                forDay: day,
                in: modelContext
            ) else {
                shareErrorMessage = "这一天已经没有可分享的训练记录。"
                return
            }
            shareModel = model
        } catch {
            shareErrorMessage = "读取当天训练记录失败，请稍后重试。"
        }
    }
}

struct MealHistoryView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var filter = WorkoutHistoryDateFilter.all
    @State private var loaded: [MealEntry] = []
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var collapsedDays: Set<Date> = []
    @State private var availableDates: Set<Date> = []

    private var dayGroups: [MealHistoryDayGroup] {
        MealHistoryQuery.groupedByDay(loaded)
    }

    private var monthChips: [(filter: WorkoutHistoryDateFilter, title: String)] {
        HistoryMonthFilterChips.chips(
            from: WorkoutHistoryQuery.filterChoices(from: Array(availableDates))
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
        .task {
            if loaded.isEmpty {
                await Task.yield()
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
            availableDates.formUnion(page.map(\.date))
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
    @State private var entries: [BodyEntry] = []
    @State private var hasMore = true
    @State private var isLoading = false

    private static let pageSize = 50

    private var chartEntries: [BodyEntry] {
        entries
    }

    var body: some View {
        List {
            Section {
                BodyHistoryTrendChart(entries: chartEntries)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(AppTheme.cardBackground)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("body-history-trend-section")
            }

            if entries.isEmpty {
                ContentUnavailableView(
                    "暂无体重记录",
                    systemImage: "scalemass",
                    description: Text("连接 Apple 健康后会自动同步体重；也可把体重数字、体重秤或体型照片发给教练。")
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
                            delete(entry)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("删除身体记录")
                        .tint(.red)
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
                    .onAppear(perform: loadMore)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle("体重记录")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if entries.isEmpty {
                await Task.yield()
                loadMore()
            }
        }
    }

    private func loadMore() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        var descriptor = FetchDescriptor<BodyEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchOffset = entries.count
        descriptor.fetchLimit = Self.pageSize
        do {
            let page = try modelContext.fetch(descriptor)
            entries.append(contentsOf: page)
            hasMore = page.count >= Self.pageSize
        } catch {
            hasMore = false
        }
    }

    private func delete(_ entry: BodyEntry) {
        entries.removeAll { $0.id == entry.id }
        modelContext.delete(entry)
        try? modelContext.save()
        if entries.count < Self.pageSize, hasMore {
            loadMore()
        }
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
                Text(workout.date.formatted(date: .abbreviated, time: workout.isDailyActivity ? .omitted : .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !metricsText.isEmpty {
                    Text(metricsText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(workout.isDailyActivity ? nil : 1)
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
                fallbackIcon: workout.isDailyActivity ? "figure.walk" : "figure.strengthtraining.traditional",
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
                fallbackIcon: workout.isDailyActivity ? "figure.walk" : "figure.strengthtraining.traditional"
            )
        } else {
            MediaThumbnail(
                kind: .none,
                path: nil,
                fallbackIcon: workout.isDailyActivity ? "figure.walk" : "figure.strengthtraining.traditional"
            )
        }
    }

    private var metricsText: String {
        var metrics: [String] = []
        if let summary = workout.dailyActivitySummary {
            return summary
        }
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

    private var knownSource: BodyMassKnownSource? {
        guard entry.isHealthImported else { return nil }
        return BodyMassKnownSource.resolve(
            name: entry.sourceName,
            bundleIdentifier: entry.sourceBundleIdentifier
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let knownSource {
                BodyMassSourceIcon(source: knownSource, size: 28)
            } else {
                MediaThumbnail(
                    kind: entry.mediaAttachments.first?.kind ?? .none,
                    path: entry.mediaAttachments.first?.path,
                    fallbackIcon: "scalemass",
                    role: .body
                )
            }

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
        .accessibilityIdentifier(entry.isHealthImported ? "body-history-health-row" : "body-history-manual-row")
    }

    private var secondaryMetrics: String {
        var metrics: [String] = []
        if let knownSource {
            metrics.append(knownSource.accessibilityLabel)
        }
        if let bodyFat = entry.bodyFat {
            metrics.append("体脂 \(bodyFat.formatted(.number.precision(.fractionLength(1))))%")
        }
        if let waist = entry.waist {
            metrics.append("腰围 \(waist.formatted(.number.precision(.fractionLength(1))))cm")
        }
        if metrics.isEmpty {
            return "身体趋势记录"
        }
        return metrics.joined(separator: " · ")
    }
}
