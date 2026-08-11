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

    private var weekWorkouts: [WorkoutEntry] {
        workouts.filter {
            $0.sourceWorkoutSessionID == nil && $0.date >= weekStart
        }
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
        weekWorkouts.count
            + completedSessions.count { $0.startedAt >= weekStart }
    }

    private var combinedVolumePoints: [TrainingVolumePoint] {
        TrainingVolumeAnalytics.dailyPoints(
            from: workouts,
            sessions: completedSessions,
            performances: exercisePerformances,
            sets: workoutSets
        )
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

    /// PRD 020：首屏收敛为紧凑上下文入口、记录入口、连续性与趋势卡；
    /// 「最近 7 天」摘要并入连续性卡头部，不再单独占一个区块。
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                NavigationLink {
                    GymLibraryView()
                } label: {
                    CompactContextRow(
                        gymName: currentGym?.name ?? "尚未建立",
                        equipmentCount: currentEquipmentCount
                    )
                }
                .buttonStyle(.plain)

                // PRD 020 修订：足迹与动作库不再挤进「最近记录」，各自独立成卡。
                AppCard {
                    VStack(spacing: 0) {
                        NavigationLink {
                            FootprintsView()
                        } label: {
                            RecordIndexRow(
                                icon: "shoeprints.fill",
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

                RecentRecordsCard(
                    workoutCount: workouts.count,
                    mealCount: meals.count,
                    bodyCount: bodyEntries.count,
                    latestWorkout: workouts.last?.exercise,
                    latestMeal: meals.last?.title,
                    latestWeight: weightedBodyEntries.last?.weight
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("连续性")
                            .font(.headline)
                        Spacer()
                        Text("最近 7 天 \(weekTrainingCount) 次训练")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ContributionCard(trainingDates: trainingDates)
                }

                if weightedBodyEntries.count >= 2 {
                    WeightTrendCard(entries: weightedBodyEntries)
                }

                TrainingVolumeTrendCard(points: combinedVolumePoints)
            }
            .padding(16)
            .padding(.bottom, 72)
        }
        .appPageBackground()
        .navigationTitle("进展")
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
    let title: String
    let count: Int
    let latest: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(AppTheme.tint)
                .frame(width: 32, height: 32)
                .background(AppTheme.softTint, in: Circle())

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

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 9) {
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
        case 1: AppTheme.tint.opacity(0.48)
        case 2: AppTheme.tint.opacity(0.72)
        default: AppTheme.tint
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
            Text("体重趋势")
                .font(.headline)
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
                            .foregroundStyle(AppTheme.tint)
                            PointMark(
                                x: .value("日期", entry.date),
                                y: .value("体重", weight)
                            )
                            .foregroundStyle(AppTheme.tint)
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
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("训练容量趋势")
                .font(.headline)

            AppCard {
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
                                .foregroundStyle(changePercent >= 0 ? AppTheme.tint : .secondary)
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
                                        AppTheme.tint.opacity(0.24),
                                        AppTheme.tint.opacity(0.02)
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
                            .foregroundStyle(AppTheme.tint)

                            PointMark(
                                x: .value("日期", point.date),
                                y: .value("训练容量", point.volume)
                            )
                            .foregroundStyle(AppTheme.tint)
                        }
                        .chartScrollableAxes(.horizontal)
                        .chartXScale(domain: xDomain)
                        .chartXVisibleDomain(length: range.duration)
                        .chartScrollPosition(x: $scrollStart)
                        .chartYScale(domain: yDomain)
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.month().day())
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let volume = value.as(Double.self) {
                                        Text(TrainingVolumeAnalytics.formatted(volume))
                                    }
                                }
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
    }
}

/// PRD 020：AI 当前上下文降为一行紧凑入口。
private struct CompactContextRow: View {
    let gymName: String
    let equipmentCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(AppTheme.tint)
            Text("AI 上下文：\(gymName)")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if equipmentCount > 0 {
                Text("· \(equipmentCount) 件器械")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background, in: Capsule())
        .overlay { Capsule().stroke(.primary.opacity(0.06)) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI 当前上下文，健身房 \(gymName)，\(equipmentCount) 件器械")
    }
}
