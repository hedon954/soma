import SwiftUI

enum ProgressRecentActivityViewport {
    static let maximumVisibleRows = 6
    static let rowHeight: CGFloat = 64
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

    var icon: String {
        switch kind {
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
    let activity: ProgressRecentActivity

    var body: some View {
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
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if let metric = activity.metric {
                    Text(metric)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.primary)
                }
                Text(dateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
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
