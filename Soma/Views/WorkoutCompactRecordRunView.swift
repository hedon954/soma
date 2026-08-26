import SwiftUI

struct WorkoutRecordHeaderChips: View {
    let targetKind: String?
    let side: String?

    var body: some View {
        HStack(spacing: 6) {
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
            .padding(.horizontal, 7)
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
            HStack(spacing: 8) {
                inlineSummary
                Spacer(minLength: 12)
                WorkoutRunCountLabel(count: runCount)
            }

            VStack(alignment: .leading, spacing: 6) {
                metricSummary
                HStack {
                    if let rest {
                        Text(rest)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    WorkoutRunCountLabel(count: runCount)
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
        HStack(spacing: 8) {
            metricSummary
            if let rest {
                separator
                Text(rest)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var metricSummary: some View {
        HStack(spacing: 8) {
            Text(target)
            separator
            Text(weight)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var separator: some View {
        Text("·")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
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
