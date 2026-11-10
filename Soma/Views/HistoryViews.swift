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
    @State private var fetchedCount = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var collapsedDays: Set<Date> = []

    private static let pageSize = BodyHistoryQuery.pageSize

    private var measurements: [BodyHistoryMeasurement] {
        BodyMassMeasurementPairing.measurements(from: entries)
    }

    private var dayGroups: [BodyMeasurementDayGroup] {
        BodyHistoryQuery.groupedMeasurementsByDay(measurements)
    }

    var body: some View {
        List {
            Section {
                BodyHistoryTrendChart(entries: entries)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(AppTheme.cardBackground)
                    .listRowSeparator(.hidden)
            }

            if entries.isEmpty, !isLoading {
                ContentUnavailableView(
                    "暂无体重记录",
                    systemImage: "scalemass",
                    description: Text("连接 Apple 健康后会自动同步体重；也可把体重数字、体重秤或体型照片发给教练。")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(dayGroups) { group in
                    let isExpanded = !collapsedDays.contains(group.day)
                    Section {
                        HistoryDayHeader(
                            title: group.title,
                            summary: group.recordCountText,
                            metric: nil,
                            metricUnit: nil,
                            isExpanded: isExpanded,
                            toggle: { toggleDay(group.day) }
                        )
                        .historyDayCardRow(edge: isExpanded ? .top : .single)

                        if isExpanded {
                            ForEach(Array(group.measurements.enumerated()), id: \.element.id) { index, measurement in
                                NavigationLink {
                                    BodyRecordDetailView(entry: measurement.primary)
                                } label: {
                                    BodyHistoryRow(
                                        measurement: measurement,
                                        isListEnd: group.day == dayGroups.last?.day
                                            && index == group.measurements.count - 1
                                    )
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(measurement)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .accessibilityLabel("删除身体记录")
                                    .tint(.red)
                                }
                                .historyDayCardRow(
                                    edge: index == group.measurements.count - 1 ? .bottom : .middle
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
                    .onAppear(perform: loadMore)
                }

                Color.clear
                    .frame(height: HistoryDayCardLayout.listBottomScrollMargin)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("body-history-scroll-end")
                    .accessibilityLabel("列表底部")
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, HistoryDayCardLayout.listBottomScrollMargin, for: .scrollContent)
        .accessibilityIdentifier("body-history-list")
        .appPageBackground()
        .navigationTitle("体重记录")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if entries.isEmpty {
                await Task.yield()
                loadMore()
            }
        }
    }

    private func toggleDay(_ day: Date) {
        if collapsedDays.contains(day) {
            collapsedDays.remove(day)
        } else {
            collapsedDays.insert(day)
        }
    }

    private func loadMore() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        var descriptor = FetchDescriptor<BodyEntry>(
            sortBy: [
                SortDescriptor(\.date, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        descriptor.fetchOffset = fetchedCount
        descriptor.fetchLimit = Self.pageSize
        do {
            let page = try modelContext.fetch(descriptor)
            fetchedCount += page.count
            let existing = Set(entries.map(\.id))
            entries.append(contentsOf: page.filter { !existing.contains($0.id) })
            injectComplements(for: page)
            hasMore = page.count >= Self.pageSize
        } catch {
            hasMore = false
        }
    }

    private func injectComplements(for page: [BodyEntry]) {
        var existing = Set(entries.map(\.id))
        var extras: [BodyEntry] = []
        for entry in page {
            let measurement = BodyMassMeasurementPairing.measurement(for: entry, in: modelContext)
            for peer in measurement.entries where !existing.contains(peer.id) {
                extras.append(peer)
                existing.insert(peer.id)
            }
        }
        entries.append(contentsOf: extras)
    }

    private func delete(_ measurement: BodyHistoryMeasurement) {
        let ids = measurement.memberIDs
        entries.removeAll { ids.contains($0.id) }
        fetchedCount = max(0, fetchedCount - measurement.entries.count)
        for entry in measurement.entries {
            modelContext.delete(entry)
        }
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
    let measurement: BodyHistoryMeasurement
    var isListEnd: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let leadingIconSize: CGFloat = 58

    private var knownSource: BodyMassKnownSource? {
        guard measurement.isHealthImported else { return nil }
        return BodyMassKnownSource.resolve(
            name: measurement.sourceName,
            bundleIdentifier: measurement.sourceBundleIdentifier
        )
    }

    private var rowAccessibilityIdentifier: String {
        if isListEnd {
            return "body-history-last-row"
        }
        if measurement.isHealthImported, measurement.weight != nil, measurement.bodyFat != nil {
            return "body-history-paired-row"
        }
        return measurement.isHealthImported ? "body-history-health-row" : "body-history-manual-row"
    }

    private var dateText: String {
        measurement.date.formatted(date: .abbreviated, time: .shortened)
    }

    private var accessibilityLines: BodyMassHistoryRowPresentation.AccessibilityLines {
        BodyMassHistoryRowPresentation.accessibilityLines(
            date: measurement.date,
            weight: measurement.weight,
            bodyFat: measurement.bodyFat,
            source: knownSource,
            unknownSourceName: measurement.sourceName,
            isHealthImported: measurement.isHealthImported
        )
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                compactLayout
            }
        }
        .padding(.vertical, 6)
        // Accessibility 布局暴露子元素标识，便于 UITest 断言「70.9 kg」整行未被拆开。
        .accessibilityElement(
            children: dynamicTypeSize.isAccessibilitySize ? .contain : .combine
        )
        .accessibilityIdentifier(rowAccessibilityIdentifier)
    }

    private var compactLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            leadingIcon
                .frame(width: Self.leadingIconSize, height: Self.leadingIconSize)
                .accessibilityIdentifier("body-history-row-leading-icon")

            VStack(alignment: .leading, spacing: 5) {
                Text(dateText)
                    .font(.headline)
                    .lineLimit(2)
                Text(secondaryMetrics)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            weightTrailing
        }
    }

    /// Accessibility：日期（仅采样时间）/ 来源 / 体重 / 体脂各自足宽整行，禁止把数值和单位塞进窄横排。
    private var accessibilityLayout: some View {
        let lines = accessibilityLines
        return VStack(alignment: .leading, spacing: 10) {
            Text(lines.sampleTime)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("body-history-row-sample-time")

            HStack(alignment: .center, spacing: 12) {
                leadingIcon
                    .frame(width: Self.leadingIconSize, height: Self.leadingIconSize)
                    .accessibilityIdentifier("body-history-row-leading-icon")
                if let source = lines.sourceCaption {
                    Text(source)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("body-history-row-source")
                } else {
                    Spacer(minLength: 0)
                }
            }

            if let weightLine = lines.weightLine {
                Text(weightLine)
                    .font(.title3.weight(.medium).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("body-history-row-weight")
            }

            if let bodyFat = measurement.bodyFat {
                VStack(alignment: .leading, spacing: 2) {
                    Text("体脂率")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(
                        "\(bodyFat.formatted(.number.precision(.fractionLength(1))))%"
                    )
                    .font(.title3.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(BodyMassHistoryRowPresentation.bodyFatLine(for: bodyFat))
                .accessibilityIdentifier("body-history-row-body-fat")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var weightTrailing: some View {
        if let weight = measurement.weight {
            Text(BodyMassHistoryRowPresentation.weightLine(for: weight))
                .font(.title3.weight(.medium).monospacedDigit())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("body-history-row-weight")
        }
    }

    private var mediaEntry: BodyEntry? {
        measurement.entries.first { !$0.mediaAttachments.isEmpty || $0.imagePath != nil }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let knownSource {
            BodyMassSourceIcon(source: knownSource, size: Self.leadingIconSize)
        } else {
            MediaThumbnail(
                kind: mediaEntry?.mediaAttachments.first?.kind ?? .none,
                path: mediaEntry?.mediaAttachments.first?.path,
                fallbackIcon: "scalemass",
                width: Self.leadingIconSize,
                height: Self.leadingIconSize,
                role: .body
            )
        }
    }

    private var secondaryMetrics: String {
        var metrics: [String] = []
        if let knownSource {
            metrics.append(knownSource.listCaption)
        }
        if let bodyFat = measurement.bodyFat {
            metrics.append("体脂 \(bodyFat.formatted(.number.precision(.fractionLength(1))))%")
        }
        // 用户路径不展示腰围；BodyEntry.waist 持久化字段保留。
        if metrics.isEmpty {
            return "身体趋势记录"
        }
        return metrics.joined(separator: " · ")
    }
}
