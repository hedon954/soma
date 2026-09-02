import SwiftUI

struct HistoryPageTitle: View {
    let title: String
    let systemImage: String
    let role: AppSemanticRole

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(role.accent)
            Text(title)
                .foregroundStyle(.primary)
        }
        .font(.headline)
        .imageScale(.medium)
        .fixedSize()
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    func historyListChrome(
        title: String,
        systemImage: String,
        role: AppSemanticRole,
        selected: WorkoutHistoryDateFilter,
        chips: [(filter: WorkoutHistoryDateFilter, title: String)],
        onSelect: @escaping (WorkoutHistoryDateFilter) -> Void
    ) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HistoryPageTitle(title: title, systemImage: systemImage, role: role)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !chips.isEmpty {
                    HistoryMonthFilterBar(
                        selected: selected,
                        chips: chips,
                        onSelect: onSelect
                    )
                }
            }
    }
}

struct HistoryMonthFilterBar: View {
    let selected: WorkoutHistoryDateFilter
    let chips: [(filter: WorkoutHistoryDateFilter, title: String)]
    let onSelect: (WorkoutHistoryDateFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    Button {
                        onSelect(chip.filter)
                    } label: {
                        Text(chip.title)
                            .font(.subheadline.weight(chip.filter == selected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(minHeight: AppTheme.minimumTapTarget)
                            .background(
                                chip.filter == selected
                                    ? AppTheme.softTint
                                    : Color.primary.opacity(0.06),
                                in: Capsule()
                            )
                            .foregroundStyle(
                                chip.filter == selected ? AppTheme.tint : .primary
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("筛选\(chip.title)")
                    .accessibilityAddTraits(
                        chip.filter == selected ? .isSelected : []
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("按月份筛选")
    }
}

enum HistoryDayMetrics {
    static func kilograms(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
    }

    static func calories(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

enum HistoryDayCardEdge {
    case single
    case top
    case middle
    case bottom
}

enum HistoryDayCardLayout {
    /// Shared by the day title and row thumbnails so the left edge stays on one grid.
    static let horizontalInset: CGFloat = 16
    static let headerVerticalPadding: CGFloat = 14
}

extension View {
    func historyDayCardRow(edge: HistoryDayCardEdge) -> some View {
        overlay(alignment: .top) {
            if edge == .middle || edge == .bottom {
                Divider()
            }
        }
        .listRowInsets(
            EdgeInsets(
                top: 0,
                leading: HistoryDayCardLayout.horizontalInset,
                bottom: 0,
                trailing: HistoryDayCardLayout.horizontalInset
            )
        )
        .listRowSeparator(.hidden)
        .listRowBackground(HistoryDayCardBackground(edge: edge))
    }
}

private struct HistoryDayCardBackground: View {
    let edge: HistoryDayCardEdge

    var body: some View {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: topRadius,
                bottomLeading: bottomRadius,
                bottomTrailing: bottomRadius,
                topTrailing: topRadius
            ),
            style: .continuous
        )
        .fill(AppTheme.cardBackground)
    }

    private var topRadius: CGFloat {
        switch edge {
        case .single, .top:
            AppTheme.cardRadius
        case .middle, .bottom:
            0
        }
    }

    private var bottomRadius: CGFloat {
        switch edge {
        case .single, .bottom:
            AppTheme.cardRadius
        case .top, .middle:
            0
        }
    }
}

struct HistoryDayHeader: View {
    let title: String
    let summary: String
    var metric: String?
    var metricUnit: String?
    let isExpanded: Bool
    let toggle: () -> Void
    var shareAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .textCase(nil)
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let metric {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(metric)
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.primary)
                            if let metricUnit {
                                Text(metricUnit)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.vertical, HistoryDayCardLayout.headerVerticalPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("点按折叠或展开这一天的记录")

            if let shareAction {
                Button(action: shareAction) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.medium))
                        .frame(
                            width: AppTheme.minimumTapTarget,
                            height: AppTheme.minimumTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workout-day-share")
                .accessibilityLabel("分享\(title)训练记录")
                .accessibilityHint("生成当天全部训练记录的分享海报")
            }
        }
    }

    private var accessibilityValue: String {
        let state = isExpanded ? "已展开" : "已折叠"
        if let metric, let metricUnit {
            return "\(state)，\(summary)，\(metric) \(metricUnit)"
        }
        return "\(state)，\(summary)"
    }
}
