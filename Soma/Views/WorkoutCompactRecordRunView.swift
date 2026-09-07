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

/// 聊天已保存记录：各组都相同时为 `60 秒 · 自重 · 间歇 60 秒`，右侧 `× 3`。
struct WorkoutCompactRecordRunView: View {
    let target: String
    let weight: String
    let rest: String?
    let runCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(summary)
                .font(.subheadline.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            WorkoutRunCountLabel(count: runCount)
        }
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
        .accessibilityLabel(summary)
    }

    private var summary: String {
        var parts = [target, weight]
        if let rest {
            parts.append(rest)
        }
        return parts.joined(separator: " · ")
    }
}

struct WorkoutCompactMetricDivider: View {
    var body: some View {
        Text("·")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

struct WorkoutCompactGroupCountLabel: View {
    let count: Int

    var body: some View {
        WorkoutRunCountLabel(count: count)
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
