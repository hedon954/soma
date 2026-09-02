import SwiftUI

struct WorkoutRecordHeaderChips: View {
    let targetKind: String?
    let side: String?

    var body: some View {
        HStack(spacing: 4) {
            if let targetKind {
                chip(targetKind)
            }
            if let side {
                chip(side)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func chip(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                AppTheme.insetBackground,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }
}

/// 聊天中的已保存记录优先表达完成结果，不沿用详情编辑器的分栏表单。
struct WorkoutCompactRecordRunView: View {
    let target: String
    let weight: String
    let rest: String?
    let runCount: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            inlineSummary

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    Text(target)
                    compactMetricDivider
                    Text(weight)
                }
                HStack(spacing: 0) {
                    WorkoutCompactGroupCountLabel(count: runCount)
                    if let rest {
                        compactMetricDivider
                        Text(rest)
                    }
                }
            }
        }
        .font(.subheadline.monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: AppTheme.minimumTapTarget)
        .background(
            AppTheme.insetBackground,
            in: RoundedRectangle(
                cornerRadius: AppTheme.controlRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-compact-inline-run")
    }

    private var inlineSummary: some View {
        HStack(spacing: 0) {
            Text(target)
            compactMetricDivider
            Text(weight)
            compactMetricDivider
            WorkoutCompactGroupCountLabel(count: runCount)
            if let rest {
                compactMetricDivider
                Text(rest)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var compactMetricDivider: some View {
        WorkoutCompactMetricDivider()
    }
}

struct WorkoutCompactMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.separator)
            .frame(width: 0.5, height: 18)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }
}

struct WorkoutCompactGroupCountLabel: View {
    let count: Int

    var body: some View {
        Text("\(count) 组")
            .font(.subheadline.monospacedDigit())
            .fixedSize()
            .accessibilityLabel("连续 \(count) 组")
            .accessibilityIdentifier("workout-run-count-\(count)")
    }
}

struct WorkoutRunCountLabel: View {
    let count: Int

    var body: some View {
        if count > 1 {
            Text("× \(count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityLabel("连续 \(count) 组")
                .accessibilityIdentifier("workout-run-count-\(count)")
        }
    }
}
