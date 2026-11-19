import SwiftUI

struct ProgressDailyActivitySection: View {
    let date: Date
    let records: [ProgressHistoryRecord]
    let owner: UUID
    @Environment(DailyActivitySyncCoordinator.self) private var activity

    var body: some View {
        let recovery = activity.readRecovery(for: date)
        if !records.isEmpty || recovery != nil {
            Text("日常活动").font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(records, id: \.activity.id) { record in
                if let summary = record.dailyActivity {
                    VStack(alignment: .leading, spacing: 8) {
                        let card = ProgressDailyActivityCard(summary: summary)
                        NavigationLink { ProgressRecentActivityDestination(activity: record.activity) } label: { card }
                            .buttonStyle(.plain)
                            .accessibilityLabel(card.accessibilityTitle)
                            .accessibilityValue(card.accessibilityMetrics)
                            .accessibilityHint("打开活动详情")
                            .accessibilityIdentifier("progress-daily-activity")
                        if record.activity.id == records.first?.activity.id, let recovery {
                            recoveryRow(recovery, hasSavedValues: true)
                        }
                    }
                } else {
                    NavigationLink { ProgressRecentActivityDestination(activity: record.activity) } label: {
                        ProgressRecentActivityRow(activity: record.activity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("progress-daily-activity")
                }
            }
            if let recovery, records.first?.dailyActivity == nil {
                recoveryRow(recovery, hasSavedValues: !records.isEmpty)
            }
        }
    }

    private func recoveryRow(_ recovery: DailyActivityReadRecovery, hasSavedValues: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                recoveryLabel(recovery, hasSavedValues: hasSavedValues).fixedSize()
                Spacer(minLength: 0)
                retryButton(recovery)
            }
            VStack(alignment: .leading, spacing: 0) {
                recoveryLabel(recovery, hasSavedValues: hasSavedValues)
                retryButton(recovery)
            }
        }
        .font(.subheadline)
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func recoveryLabel(_ recovery: DailyActivityReadRecovery, hasSavedValues: Bool) -> some View {
        let text = switch (recovery, hasSavedValues) {
        case (.retrying, _): "正在读取活动…"
        case (.failed, true): "同步失败，显示上次数据"
        case (.failed, false): "同步失败，暂无活动数据"
        }
        return Label(text, systemImage: recovery == .retrying ? "arrow.clockwise" : "exclamationmark.circle")
    }

    private func retryButton(_ recovery: DailyActivityReadRecovery) -> some View {
        Button {
            activity.retryRead(for: date, owner: owner)
        } label: {
            Text("重试").fontWeight(.medium)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("重试日常活动同步")
        .disabled(recovery == .retrying)
    }
}

struct ProgressDailyActivityCard: View {
    let summary: DailyActivitySummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var size

    var accessibilityTitle: String {
        "日常活动，\(summary.resolvedWinningSource.title)"
    }

    var accessibilityMetrics: String {
        DailyActivityMetricKind.allCases.map { metric in
            guard let value = summary[metric].value else { return "\(metric.title) 暂无数据" }
            let unit = switch metric {
            case .steps: "步"
            case .walkingRunningDistance: "千米"
            case .activeEnergy: "千卡"
            }
            return "\(metric.title) \(metric.displayValue(value)) \(unit)"
        }.joined(separator: "，")
    }

    var body: some View {
        HStack(alignment: size.isAccessibilitySize ? .top : .center, spacing: 12) {
            DailyActivitySourceIcon(kind: .winning(summary.resolvedWinningSource), size: 24)
                .frame(width: 40, height: 40)
                .background(AppTheme.insetBackground, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(summary.resolvedWinningSource.title)
                    .font(.subheadline.weight(.semibold))
                if size.isAccessibilitySize {
                    stackedMetrics
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 8) { metrics }
                        stackedMetrics
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent.opacity(0.46))
                .accessibilityHidden(true)
        }
        .foregroundStyle(AppTheme.accent)
        .padding(.vertical, 5)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private var stackedMetrics: some View {
        VStack(alignment: .leading, spacing: 8) { metrics }
    }

    private var metrics: some View {
        ForEach(DailyActivityMetricKind.allCases, id: \.self) { metric in
            VStack(alignment: .leading, spacing: 3) {
                Text(metric == .walkingRunningDistance ? "步跑距离" : metric.title)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.accent.opacity(0.64))
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(metric.displayValue(summary[metric].value))
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: summary[metric].value)
                    Text(metric.unit)
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent.opacity(0.64))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
