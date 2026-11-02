import SwiftUI

enum ProgressRecentActivityViewport {
    static let maximumVisibleRows = 6
    static let rowHeight: CGFloat = 72
    static let dividerHeight: CGFloat = 1

    static func height(activityCount: Int) -> CGFloat {
        let visibleRows = min(max(activityCount, 0), maximumVisibleRows)
        guard visibleRows > 0 else { return 0 }
        return CGFloat(visibleRows) * rowHeight
            + CGFloat(visibleRows - 1) * dividerHeight
    }
}

struct ProgressRecentActivity: Identifiable, Sendable {
    enum Kind: Sendable {
        case workout
        case meal
        case body
    }

    let id: UUID
    let kind: Kind
    let date: Date
    let title: String
    let detail: String
    let metric: String?
    var isDailyActivity = false

    static func workout(
        id: UUID,
        date: Date,
        title: String,
        detail: String?,
        volume: Double?,
        calories: Int? = nil
    ) -> ProgressRecentActivity {
        ProgressRecentActivity(
            id: id,
            kind: .workout,
            date: date,
            title: title,
            detail: detail ?? "训练记录",
            metric: workoutMetric(volume: volume, calories: calories)
        )
    }

    private static func workoutMetric(volume: Double?, calories: Int?) -> String? {
        let volumeText = volume.map { "\($0.formatted()) kg" }
        let calorieText = calories.map { "约 \($0) kcal" }
        switch (volumeText, calorieText) {
        case let (volume?, calorie?):
            return "\(volume)\n\(calorie)"
        case let (volume?, nil):
            return volume
        case let (nil, calorie?):
            return calorie
        case (nil, nil):
            return nil
        }
    }

    static func workout(_ entry: WorkoutEntry) -> ProgressRecentActivity {
        if let day = entry.dailyActivity {
            let detail = [DailyActivityMetricKind.steps, .walkingRunningDistance].compactMap { kind in
                day[kind].value.map { "\(kind.displayValue($0)) \(kind.unit)" }
            }.joined(separator: " · ")
            return .init(id: entry.id, kind: .workout, date: entry.date, title: "日常活动", detail: detail,
                         metric: day[.activeEnergy].value.map { "\(DailyActivityMetricKind.activeEnergy.displayValue($0)) kcal" }, isDailyActivity: true)
        }
        return workout(
            id: entry.id,
            date: entry.date,
            title: entry.exercise,
            detail: entry.setEvidenceSummary,
            volume: entry.estimatedVolume,
            calories: entry.estimatedCalories
        )
    }

    var icon: String {
        if isDailyActivity {
            return "figure.walk"
        }
        return switch kind {
        case .workout: "dumbbell.fill"
        case .meal: "fork.knife"
        case .body: "scalemass.fill"
        }
    }

    var tint: Color {
        switch kind {
        case .workout: AppTheme.trainingAccent
        case .meal: AppTheme.mealAccent
        case .body: AppTheme.bodyAccent
        }
    }

    var softTint: Color {
        switch kind {
        case .workout: AppTheme.trainingSoftTint
        case .meal: AppTheme.mealSoftTint
        case .body: AppTheme.bodySoftTint
        }
    }
}

struct ProgressWeekSummaryCard: View {
    let trainingCount: Int
    let volume: Double?
    let weightChange: Double?
    let trainingDays: Set<Date>
    var embedded = false

    private let calendar = Calendar.current

    var body: some View {
        if embedded {
            content
        } else {
            AppCard { content }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !embedded {
                MetricHeading(title: "最近 7 天", role: .consistency)
            }

            HStack(spacing: 0) {
                metric(value: "\(trainingCount)", unit: nil, label: "次训练")
                if let volume {
                    Divider()
                        .frame(height: 48)
                    metric(
                        value: volume.formatted(.number.precision(.fractionLength(0))),
                        unit: "kg",
                        label: "总训练量"
                    )
                }
                if let weightChange {
                    Divider()
                        .frame(height: 48)
                    metric(
                        value: weightChange.formatted(
                            .number.sign(strategy: .always()).precision(.fractionLength(0 ... 1))
                        ),
                        unit: "kg",
                        label: "体重变化"
                    )
                }
            }

            HStack(spacing: 0) {
                ForEach(days, id: \.self) { date in
                    VStack(spacing: 7) {
                        Capsule()
                            .fill(
                                trainingDays.contains(calendar.startOfDay(for: date))
                                    ? AppMetricRole.consistency.accent
                                    : AppTheme.separator
                            )
                            .frame(width: 7, height: 38)
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("最近 7 天有 \(trainingDays.count) 个训练日")
        }
    }

    private var days: [Date] {
        (0 ..< 7).compactMap {
            calendar.date(byAdding: .day, value: $0 - 6, to: .now)
        }
    }

    private func metric(value: String, unit: String?, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title.weight(.semibold).monospacedDigit())
                    .minimumScaleFactor(0.72)
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.semibold))
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ProgressConclusionCard: View {
    let title: String
    let detail: String
    let status: AppStatusRole

    var body: some View {
        AppCard {
            HStack(alignment: .center, spacing: 14) {
                StatusIconBadge(role: status)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ProgressRecentActivityRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let activity: ProgressRecentActivity
    var showsDisclosure = true

    var body: some View {
        Group {
            if activity.isDailyActivity, dynamicTypeSize.isAccessibilitySize {
                dailyAccessibilityRow
            } else {
                horizontalRow
            }
        }
        .frame(minHeight: activity.metric?.contains("\n") == true ? 72 : 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(activity.isDailyActivity ? "daily-activity-record" : "progress-activity-\(activity.id)")
    }

    private var dailyAccessibilityRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: activity.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(activity.tint)
                .frame(width: 40, height: 40)
                .background(activity.softTint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(activity.title).font(.subheadline.weight(.semibold))
                Text(activity.detail).font(.caption).foregroundStyle(.secondary)
                if let metric = activity.metric {
                    Text(metric).font(.subheadline.monospacedDigit())
                }
                Text(dateText).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var horizontalRow: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(activity.tint)
                .frame(width: 40, height: 40)
                .background(activity.softTint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(activity.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(activity.isDailyActivity ? nil : 1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if let metric = activity.metric {
                    Text(metric)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(dateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var dateText: String {
        if activity.isDailyActivity {
            return activity.date.formatted(.dateTime.month().day())
        }
        if Calendar.current.isDateInToday(activity.date) {
            return activity.date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.component(.year, from: activity.date)
            == Calendar.current.component(.year, from: .now)
        {
            return activity.date.formatted(.dateTime.month().day())
        }
        return activity.date.formatted(date: .abbreviated, time: .omitted)
    }
}
