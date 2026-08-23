import Charts
import SwiftData
import SwiftUI

struct InsightsView: View {
    @Query(sort: \WorkoutEntry.date) private var workouts: [WorkoutEntry]
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query(sort: \BodyEntry.date) private var bodyEntries: [BodyEntry]
    @Query(sort: \GymProfile.createdAt) private var gyms: [GymProfile]
    @Query(sort: \GymEquipment.createdAt) private var equipment: [GymEquipment]
    @Query(sort: \CoachMessage.date) private var messages: [CoachMessage]
    @Query(sort: \ExerciseDefinition.canonicalName)
    private var exerciseDefinitions: [ExerciseDefinition]
    @Query(sort: \WorkoutSession.startedAt)
    private var workoutSessions: [WorkoutSession]
    @Query(sort: \ExercisePerformance.order)
    private var exercisePerformances: [ExercisePerformance]
    @Query(sort: \WorkoutSet.order) private var workoutSets: [WorkoutSet]

    private var weekStart: Date {
        Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .distantPast
    }

    private var completedSessions: [WorkoutSession] {
        workoutSessions.filter {
            $0.status == .completed || $0.status == .abandoned
        }
    }

    private var trainingDates: [Date] {
        workouts.filter { $0.sourceWorkoutSessionID == nil }.map(\.date)
            + completedSessions.map(\.startedAt)
    }

    private var weekTrainingCount: Int {
        let standaloneCount = workouts.count {
            $0.sourceWorkoutSessionID == nil && $0.date >= weekStart
        }
        let projectedSessionIDs = Set(workouts.compactMap { workout in
            workout.date >= weekStart ? workout.sourceWorkoutSessionID : nil
        })
        let recentCompletedSessionIDs = Set(completedSessions.compactMap { session in
            session.startedAt >= weekStart ? session.id : nil
        })
        return standaloneCount + projectedSessionIDs.union(recentCompletedSessionIDs).count
    }

    private var combinedVolumePoints: [TrainingVolumePoint] {
        TrainingVolumeAnalytics.dailyPoints(
            from: workouts,
            sessions: completedSessions,
            performances: exercisePerformances,
            sets: workoutSets
        )
    }

    private var weekVolume: Double? {
        let total = combinedVolumePoints
            .filter { $0.date >= weekStart }
            .reduce(0) { $0 + $1.volume }
        return total > 0 ? total : nil
    }

    private var weekTrainingDays: Set<Date> {
        Set(trainingDates.filter { $0 >= weekStart }.map(Calendar.current.startOfDay(for:)))
    }

    private var weekWeightChange: Double? {
        let values = weightedBodyEntries
            .filter { $0.date >= weekStart }
            .compactMap(\.weight)
        guard let first = values.first, let last = values.last, values.count >= 2 else {
            return nil
        }
        return last - first
    }

    private var dateRangeText: String {
        let format = Date.FormatStyle(date: .abbreviated, time: .omitted)
        return "\(weekStart.formatted(format))—\(Date.now.formatted(format))"
    }

    private var recentActivities: [ProgressRecentActivity] {
        let workoutValues = workouts.map {
            ProgressRecentActivity(
                id: $0.id,
                kind: .workout,
                date: $0.date,
                title: $0.exercise,
                detail: $0.setEvidenceSummary ?? "训练记录",
                metric: $0.estimatedVolume.map { "\($0.formatted()) kg" }
            )
        }
        let mealValues = meals.map {
            ProgressRecentActivity(
                id: $0.id,
                kind: .meal,
                date: $0.date,
                title: $0.title,
                detail: $0.mealType.rawValue,
                metric: $0.calories.map { "\($0) kcal" }
            )
        }
        let bodyValues = bodyEntries.map {
            ProgressRecentActivity(
                id: $0.id,
                kind: .body,
                date: $0.date,
                title: "身体记录",
                detail: $0.notes.isEmpty ? "身体变化" : $0.notes,
                metric: $0.weight.map { "\($0.formatted()) kg" }
            )
        }
        return (workoutValues + mealValues + bodyValues)
            .sorted { $0.date > $1.date }
    }

    private var weightedBodyEntries: [BodyEntry] {
        bodyEntries.filter { $0.weight != nil }
    }

    private var currentGym: GymProfile? {
        GymSelection.current(in: gyms)
    }

    private var currentEquipmentCount: Int {
        guard let currentGym else { return 0 }
        return equipment.filter { $0.gymID == currentGym.id }.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                Text(dateRangeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach(
                    ProgressHomeSection.visible(
                        hasRecentActivities: !recentActivities.isEmpty,
                        hasWeightTrend: weightedBodyEntries.count >= 2
                    )
                ) { section in
                    progressHomeSection(section)
                }
            }
            .padding(AppTheme.pagePadding)
            .padding(.bottom, 72)
            .frame(maxWidth: AppTheme.readableContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .appPageBackground()
        .navigationTitle("进展")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func progressHomeSection(_ section: ProgressHomeSection) -> some View {
        switch section {
        case .trainingOverview:
            ProgressTrainingOverviewCard(
                trainingCount: weekTrainingCount,
                volume: weekVolume,
                weightChange: weekWeightChange,
                trainingDays: weekTrainingDays,
                trainingDates: trainingDates,
                volumePoints: combinedVolumePoints
            )
        case .conclusion:
            ProgressConclusionCard(
                title: conclusionTitle,
                detail: conclusionDetail,
                status: conclusionStatus
            )
        case .recentActivities:
            HStack(alignment: .center, spacing: 12) {
                SectionHeading(title: "最近活动")
                Spacer()
                NavigationLink {
                    WorkoutHistoryView()
                } label: {
                    progressHistoryShortcut(
                        title: "训练记录",
                        systemImage: "dumbbell.fill",
                        role: .training
                    )
                }
                .buttonStyle(.plain)
                NavigationLink {
                    MealHistoryView()
                } label: {
                    progressHistoryShortcut(
                        title: "饮食记录",
                        systemImage: "fork.knife",
                        role: .meal
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 44)
            AppCard {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(
                            Array(recentActivities.enumerated()),
                            id: \.element.id
                        ) { index, activity in
                            NavigationLink {
                                recentActivityDestination(activity)
                            } label: {
                                ProgressRecentActivityRow(activity: activity)
                            }
                            .buttonStyle(.plain)
                            if index < recentActivities.count - 1 {
                                Divider()
                                    .overlay(AppTheme.separator)
                            }
                        }
                    }
                }
                .frame(
                    height: ProgressRecentActivityViewport.height(
                        activityCount: recentActivities.count
                    )
                )
                .scrollIndicators(
                    recentActivities.count
                        > ProgressRecentActivityViewport.maximumVisibleRows
                        ? .visible
                        : .hidden
                )
                .scrollBounceBehavior(.basedOnSize)
            }
        case .weightTrend:
            WeightTrendCard(entries: weightedBodyEntries)
        case .allData:
            SectionHeading(title: "数据与全部记录")
            RecentRecordsCard(
                workoutCount: workouts.count,
                mealCount: meals.count,
                bodyCount: bodyEntries.count,
                latestWorkout: workouts.last?.exercise,
                latestMeal: meals.last?.title,
                latestWeight: weightedBodyEntries.last?.weight
            )
        case .currentGym:
            NavigationLink {
                GymLibraryView()
            } label: {
                CurrentGymContextCard(
                    gymName: currentGym?.name ?? "尚未建立",
                    coverImagePath: currentGym?.coverImagePath,
                    note: currentGym?.notes,
                    equipmentCount: currentEquipmentCount
                )
            }
            .buttonStyle(.plain)
        case .personalResources:
            AppCard {
                VStack(spacing: 0) {
                    NavigationLink {
                        FootprintsView()
                    } label: {
                        RecordIndexRow(
                            icon: "shoeprints.fill",
                            role: .trend,
                            title: "足迹",
                            count: successfulFootprintCount,
                            latest: successfulFootprintCount == 0
                                ? "Agent 成功后自动收录"
                                : "回顾你的文字与影像"
                        )
                    }

                    Divider()
                        .padding(.leading, 44)

                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        RecordIndexRow(
                            icon: "books.vertical",
                            role: .training,
                            title: "动作库",
                            count: exerciseDefinitions.count { !$0.isArchived },
                            latest: exerciseDefinitions.contains(where: { !$0.isArchived })
                                ? "查看动作详情与受力"
                                : "随训练自然形成"
                        )
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func progressHistoryShortcut(
        title: String,
        systemImage: String,
        role: AppSemanticRole
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
            Text(title)
                .font(.caption.weight(.medium))
                .underline(true, color: role.accent)
        }
        .foregroundStyle(role.accent)
        .frame(minHeight: AppTheme.minimumTapTarget)
        .contentShape(Rectangle())
    }

    private var conclusionTitle: String {
        switch weekTrainingCount {
        case 0: "等待新的训练节奏"
        case 1 ... 2: "训练正在积累"
        default: "训练节奏稳定"
        }
    }

    private var conclusionDetail: String {
        switch weekTrainingCount {
        case 0: "最近 7 天还没有完整训练记录。"
        case 1 ... 2: "本周完成 \(weekTrainingCount) 次训练，继续保持规律即可。"
        default: "本周完成 \(weekTrainingCount) 次训练，频率比单次数字更值得关注。"
        }
    }

    private var conclusionStatus: AppStatusRole {
        switch weekTrainingCount {
        case 0: .neutral
        case 1 ... 2: .attention
        default: .positive
        }
    }

    @ViewBuilder
    private func recentActivityDestination(_ activity: ProgressRecentActivity) -> some View {
        switch activity.kind {
        case .workout:
            if let workout = workouts.first(where: { $0.id == activity.id }) {
                WorkoutRecordDetailView(workout: workout)
            }
        case .meal:
            if let meal = meals.first(where: { $0.id == activity.id }) {
                MealRecordDetailView(meal: meal)
            }
        case .body:
            if let entry = bodyEntries.first(where: { $0.id == activity.id }) {
                BodyRecordDetailView(entry: entry)
            }
        }
    }

    private var successfulFootprintCount: Int {
        let successful = ConversationTurnProjection.successfulTurnIDs(
            in: messages
        )
        return messages.count {
            !$0.isFromCoach && $0.turnID.map(successful.contains) == true
        }
    }
}

private struct ProgressTrainingOverviewCard: View {
    let trainingCount: Int
    let volume: Double?
    let weightChange: Double?
    let trainingDays: Set<Date>
    let trainingDates: [Date]
    let volumePoints: [TrainingVolumePoint]
    @State private var selection = ProgressTrainingOverviewTab.recentWeek

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 18) {
                Picker("训练概览", selection: $selection) {
                    ForEach(ProgressTrainingOverviewTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch selection {
                case .recentWeek:
                    ProgressWeekSummaryCard(
                        trainingCount: trainingCount,
                        volume: volume,
                        weightChange: weightChange,
                        trainingDays: trainingDays,
                        embedded: true
                    )
                case .continuity:
                    ContributionCard(
                        trainingDates: trainingDates,
                        embedded: true
                    )
                case .volume:
                    TrainingVolumeTrendCard(
                        points: volumePoints,
                        embedded: true
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct RecentRecordsCard: View {
    let workoutCount: Int
    let mealCount: Int
    let bodyCount: Int
    let latestWorkout: String?
    let latestMeal: String?
    let latestWeight: Double?

    /// PRD 020 修订：足迹与动作库独立成卡后，这里只保留三类业务记录。
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近记录")
                .font(.headline)

            AppCard {
                VStack(spacing: 0) {
                    NavigationLink {
                        WorkoutHistoryView()
                    } label: {
                        RecordIndexRow(
                            icon: "figure.strengthtraining.traditional",
                            role: .training,
                            title: "训练记录",
                            count: workoutCount,
                            latest: latestWorkout ?? "暂无记录"
                        )
                    }

                    Divider()
                        .padding(.leading, 44)

                    NavigationLink {
                        MealHistoryView()
                    } label: {
                        RecordIndexRow(
                            icon: "fork.knife",
                            role: .meal,
                            title: "饮食记录",
                            count: mealCount,
                            latest: latestMeal ?? "暂无记录"
                        )
                    }

                    Divider()
                        .padding(.leading, 44)

                    NavigationLink {
                        BodyHistoryView()
                    } label: {
                        RecordIndexRow(
                            icon: "scalemass",
                            role: .body,
                            title: "体重记录",
                            count: bodyCount,
                            latest: latestWeight.map { String(format: "%.1f kg", $0) } ?? "暂无记录"
                        )
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RecordIndexRow: View {
    let icon: String
    let role: AppSemanticRole
    let title: String
    let count: Int
    let latest: String

    var body: some View {
        HStack(spacing: 12) {
            SemanticIconBadge(systemImage: icon, role: role, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("最近：\(latest)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(count) 条")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
    }
}

private struct ContributionCard: View {
    let trainingDates: [Date]
    var embedded = false

    var body: some View {
        if embedded {
            content
        } else {
            AppCard { content }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !embedded {
                MetricHeading(title: "训练连续性", role: .consistency)
            }

            HStack(alignment: .top, spacing: 7) {
                VStack(spacing: 4) {
                    Color.clear.frame(width: 16, height: 14)
                    ForEach(0 ..< 7, id: \.self) { row in
                        Text(weekdayLabel(for: row))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 13, alignment: .trailing)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            ForEach(Array(weeks.enumerated()), id: \.element.id) { index, _ in
                                Color.clear
                                    .frame(width: 13, height: 14)
                                    .overlay(alignment: .leading) {
                                        Text(monthLabel(at: index))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                            .fixedSize()
                                    }
                            }
                        }

                        HStack(alignment: .top, spacing: 4) {
                            ForEach(weeks) { week in
                                VStack(spacing: 4) {
                                    ForEach(week.days, id: \.self) { day in
                                        contributionCell(for: day)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 4) {
                Text("过去 13 周")
                Spacer()
                Text("少")
                ForEach(0 ..< 5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: level))
                        .frame(width: 10, height: 10)
                }
                Text("多")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var weeks: [ContributionWeek] {
        let calendar = Calendar.current
        let today = Calendar.current.startOfDay(for: .now)
        let threshold = calendar.date(byAdding: .day, value: -90, to: today) ?? today
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: threshold)?.start ?? threshold
        let lastWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let weekCount = max(1, (calendar.dateComponents([.weekOfYear], from: firstWeek, to: lastWeek).weekOfYear ?? 0) + 1)

        return (0 ..< weekCount).compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: offset, to: firstWeek) else { return nil }
            let days = (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            return ContributionWeek(start: start, days: days)
        }
    }

    private func contributionCell(for day: Date) -> some View {
        let isFuture = day > Calendar.current.startOfDay(for: .now)
        let count = trainingDates.count {
            Calendar.current.isDate($0, inSameDayAs: day)
        }

        return RoundedRectangle(cornerRadius: 3)
            .fill(isFuture ? Color.clear : color(for: count))
            .frame(width: 13, height: 13)
            .accessibilityLabel(
                isFuture
                    ? ""
                    : "\(day.formatted(date: .abbreviated, time: .omitted))，\(count) 次训练"
            )
            .accessibilityHidden(isFuture)
    }

    private func weekdayLabel(for row: Int) -> String {
        guard [1, 3, 5].contains(row), let day = weeks.first?.days[row] else { return "" }
        return day.formatted(.dateTime.weekday(.narrow))
    }

    private func monthLabel(at index: Int) -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: weeks[index].start)
        if index == 0 {
            let visibleWeeks = weeks.prefix { calendar.component(.month, from: $0.start) == month }.count
            return visibleWeeks >= 2 ? "\(month)月" : ""
        } else {
            let previousMonth = calendar.component(.month, from: weeks[index - 1].start)
            guard month != previousMonth else { return "" }
        }
        return "\(month)月"
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0: Color.secondary.opacity(0.1)
        case 1: AppMetricRole.consistency.accent.opacity(0.42)
        case 2: AppMetricRole.consistency.accent.opacity(0.7)
        default: AppMetricRole.consistency.accent
        }
    }
}

private struct ContributionWeek: Identifiable {
    let start: Date
    let days: [Date]
    var id: Date {
        start
    }
}

private enum TrendRange: Int, CaseIterable, Identifiable {
    case week = 7
    case twoWeeks = 14
    case month = 30
    case quarter = 90

    var id: Int {
        rawValue
    }

    var label: String {
        switch self {
        case .week: "周"
        case .twoWeeks: "双周"
        case .month: "月"
        case .quarter: "季"
        }
    }

    var duration: TimeInterval {
        TimeInterval(rawValue * 24 * 60 * 60)
    }
}

private struct WeightTrendCard: View {
    let entries: [BodyEntry]
    @State private var range: TrendRange = .month
    @State private var scrollStart = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now

    private var visibleEnd: Date {
        scrollStart.addingTimeInterval(range.duration)
    }

    private var yDomain: ClosedRange<Double> {
        let weights = entries.compactMap(\.weight)
        let lower = (weights.min() ?? 0) - 1.5
        let upper = (weights.max() ?? 100) + 1.5
        return lower ... upper
    }

    private var xDomain: ClosedRange<Date> {
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .now
        let firstEntry = entries.first(where: { $0.weight != nil })?.date ?? .now
        return min(ninetyDaysAgo, firstEntry) ... Date.now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetricHeading(title: "体重趋势", role: .body)
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("时间粒度", selection: $range) {
                        ForEach(TrendRange.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("\(scrollStart.formatted(.dateTime.year().month().day())) – \(visibleEnd.formatted(.dateTime.month().day()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Chart(entries) { entry in
                        if let weight = entry.weight {
                            LineMark(
                                x: .value("日期", entry.date),
                                y: .value("体重", weight)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(
                                StrokeStyle(
                                    lineWidth: 2.25,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .foregroundStyle(AppMetricRole.body.accent)
                            PointMark(
                                x: .value("日期", entry.date),
                                y: .value("体重", weight)
                            )
                            .foregroundStyle(AppMetricRole.body.accent)
                        }
                    }
                    .chartScrollableAxes(.horizontal)
                    .chartXScale(domain: xDomain)
                    .chartXVisibleDomain(length: range.duration)
                    .chartScrollPosition(x: $scrollStart)
                    .chartYScale(domain: yDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                                .foregroundStyle(AppTheme.separator)
                            AxisTick()
                                .foregroundStyle(AppTheme.separator)
                            AxisValueLabel(format: .dateTime.month().day())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine()
                                .foregroundStyle(AppTheme.separator)
                            AxisTick()
                                .foregroundStyle(AppTheme.separator)
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 180)
                }
                .onChange(of: range) {
                    scrollStart = Calendar.current.date(
                        byAdding: .day,
                        value: -range.rawValue,
                        to: .now
                    ) ?? .now
                }
            }
        }
    }
}

struct TrainingVolumePoint: Identifiable, Equatable {
    let date: Date
    let volume: Double

    var id: Date {
        date
    }
}

enum TrainingVolumeAnalytics {
    static func dailyPoints(
        from workouts: [WorkoutEntry],
        calendar: Calendar = .current
    ) -> [TrainingVolumePoint] {
        let dailyVolumes = workouts.reduce(into: [Date: Double]()) { result, workout in
            guard let volume = workout.estimatedVolume, volume > 0 else { return }
            result[calendar.startOfDay(for: workout.date), default: 0] += volume
        }

        return dailyVolumes
            .map { TrainingVolumePoint(date: $0.key, volume: $0.value) }
            .sorted { $0.date < $1.date }
    }

    static func dailyPoints(
        from workouts: [WorkoutEntry],
        sessions: [WorkoutSession],
        performances: [ExercisePerformance],
        sets: [WorkoutSet],
        calendar: Calendar = .current
    ) -> [TrainingVolumePoint] {
        var daily = Dictionary(
            uniqueKeysWithValues: dailyPoints(
                from: workouts,
                calendar: calendar
            ).map { ($0.date, $0.volume) }
        )
        let performancesByID = Dictionary(
            uniqueKeysWithValues: performances.map { ($0.id, $0) }
        )
        let sessionsByID = Dictionary(
            uniqueKeysWithValues: sessions.map { ($0.id, $0) }
        )
        let projectedPerformanceIDs = Set(
            workouts.compactMap(\.sourcePerformanceID)
        )
        for set in sets where set.status == .completed {
            guard let volume = set.completedVolume,
                  volume > 0,
                  let performance = performancesByID[set.performanceID],
                  !projectedPerformanceIDs.contains(performance.id),
                  !performance.workoutProjectionSuppressed,
                  let session = sessionsByID[performance.sessionID]
            else {
                continue
            }
            daily[
                calendar.startOfDay(for: session.startedAt),
                default: 0
            ] += volume
        }
        return daily.map {
            TrainingVolumePoint(date: $0.key, volume: $0.value)
        }.sorted { $0.date < $1.date }
    }

    static func total(
        in interval: Range<Date>,
        points: [TrainingVolumePoint]
    ) -> Double {
        points
            .filter { interval.contains($0.date) }
            .reduce(0) { $0 + $1.volume }
    }

    static func formatted(_ volume: Double) -> String {
        guard volume >= 1000 else { return String(format: "%.0f", volume) }
        let thousands = volume / 1000
        return thousands >= 10
            ? String(format: "%.0fk", thousands)
            : String(format: "%.1fk", thousands)
    }
}

private struct TrainingVolumeTrendCard: View {
    let points: [TrainingVolumePoint]
    var embedded = false
    @State private var range: TrendRange = .month
    @State private var scrollStart = Calendar.current.startOfDay(
        for: Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    )

    private var visibleEnd: Date {
        scrollStart.addingTimeInterval(range.duration)
    }

    private var currentTotal: Double {
        TrainingVolumeAnalytics.total(
            in: scrollStart ..< visibleEnd,
            points: points
        )
    }

    private var previousStart: Date {
        scrollStart.addingTimeInterval(-range.duration)
    }

    private var previousTotal: Double {
        TrainingVolumeAnalytics.total(
            in: previousStart ..< scrollStart,
            points: points
        )
    }

    private var changePercent: Double? {
        guard
            let firstPoint = points.first,
            firstPoint.date <= previousStart,
            previousTotal > 0
        else {
            return nil
        }
        return (currentTotal - previousTotal) / previousTotal * 100
    }

    private var xDomain: ClosedRange<Date> {
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .now
        let firstEntry = points.first?.date ?? .now
        return min(ninetyDaysAgo, firstEntry) ... Date.now
    }

    private var yDomain: ClosedRange<Double> {
        let upper = max(points.map(\.volume).max() ?? 1, 1) * 1.15
        return 0 ... upper
    }

    var body: some View {
        if embedded {
            content
        } else {
            VStack(alignment: .leading, spacing: 10) {
                MetricHeading(title: "训练容量趋势", role: .trainingLoad)
                AppCard { content }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("时间粒度", selection: $range) {
                ForEach(TrendRange.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if points.isEmpty {
                ContentUnavailableView {
                    Label("暂无容量数据", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("记录组数、次数和重量后，这里会按日汇总组数 × 次数 × 重量生成趋势；缺失字段不计入。")
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本期总容量")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(TrainingVolumeAnalytics.formatted(currentTotal)) kg")
                            .font(.title3.bold().monospacedDigit())
                    }

                    Spacer()

                    if let changePercent {
                        Label(
                            String(format: "%+.0f%% 较上期", changePercent),
                            systemImage: changePercent >= 0
                                ? "arrow.up.right"
                                : "arrow.down.right"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppMetricRole.trainingLoad.accent)
                    }
                }

                Text("\(scrollStart.formatted(.dateTime.year().month().day())) – \(visibleEnd.formatted(.dateTime.month().day()))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Chart(points) { point in
                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value("训练容量", point.volume)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                AppMetricRole.trainingLoad.accent.opacity(0.24),
                                AppMetricRole.trainingLoad.accent.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("训练容量", point.volume)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 2.25,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .foregroundStyle(AppMetricRole.trainingLoad.accent)

                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("训练容量", point.volume)
                    )
                    .foregroundStyle(AppMetricRole.trainingLoad.accent)
                }
                .chartScrollableAxes(.horizontal)
                .chartXScale(domain: xDomain)
                .chartXVisibleDomain(length: range.duration)
                .chartScrollPosition(x: $scrollStart)
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                            .foregroundStyle(AppTheme.separator)
                        AxisTick()
                            .foregroundStyle(AppTheme.separator)
                        AxisValueLabel(format: .dateTime.month().day())
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                            .foregroundStyle(AppTheme.separator)
                        AxisTick()
                            .foregroundStyle(AppTheme.separator)
                        AxisValueLabel {
                            if let volume = value.as(Double.self) {
                                Text(TrainingVolumeAnalytics.formatted(volume))
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 180)
            }
        }
        .onChange(of: range) {
            let start = Calendar.current.date(
                byAdding: .day,
                value: -range.rawValue,
                to: .now
            ) ?? .now
            scrollStart = Calendar.current.startOfDay(for: start)
        }
    }
}

/// 当前健身房是 Agent 的高频上下文，首屏直接呈现名称、封面和器械摘要。
private struct CurrentGymContextCard: View {
    let gymName: String
    let coverImagePath: String?
    let note: String?
    let equipmentCount: Int

    var body: some View {
        AppCard {
            HStack(spacing: 12) {
                LocalImageView(path: coverImagePath)
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Label("当前健身房", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.trainingAccent)
                    Text(gymName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(contextDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前健身房 \(gymName)，\(equipmentCount) 件器械")
    }

    private var contextDetail: String {
        if equipmentCount > 0 {
            return "\(equipmentCount) 件器械可供 Agent 使用"
        }
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty
        {
            return note
        }
        return "点开管理健身房与器械"
    }
}
