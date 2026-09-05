import SwiftUI

struct ProgressEnergyBreakdownDisclosure<Label: View>: View {
    let snapshot: ProgressHistorySnapshot
    let kind: ProgressEnergyBreakdown.Kind
    @ViewBuilder let label: () -> Label
    @State private var isPresented = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            disclosureButton.sheet(isPresented: $isPresented) {
                ProgressEnergyBreakdownPopover(source: .init(snapshot: snapshot, kind: kind))
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        } else {
            disclosureButton.popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                ProgressEnergyBreakdownPopover(source: .init(snapshot: snapshot, kind: kind))
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var disclosureButton: some View {
        Button { isPresented.toggle() } label: {
            label()
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("progress-\(kind.rawValue)-breakdown")
        .accessibilityHint("查看组成明细")
    }
}

private struct ProgressEnergyBreakdownPopover: View {
    let source: ProgressEnergyBreakdown
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 44
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(source.rows) { row in
                    rowView(row)
                    if row.id != source.rows.last?.id {
                        Divider().padding(.leading, 20)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: EnergyBreakdownHeightKey.self, value: geometry.size.height)
                }
            }
        }
        .onPreferenceChange(EnergyBreakdownHeightKey.self) { contentHeight = $0 }
        .accessibilityIdentifier("progress-energy-breakdown-list")
        .frame(
            width: min(400, max(260, UIScreen.main.bounds.width - 32)),
            height: min(contentHeight > 0 ? contentHeight : CGFloat(source.rows.count) * rowHeight + 16, dynamicTypeSize.isAccessibilitySize ? 480 : 380)
        )
        .background(AppTheme.cardBackground)
    }

    private func rowView(_ row: ProgressEnergyBreakdown.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(accent(row.tone)).frame(width: 10, height: 10)
                .accessibilityHidden(true)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                Text(row.label).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }
                Text(row.value).font(.subheadline.monospacedDigit()).foregroundStyle(accent(row.tone))
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            }
        }
        .padding(.vertical, 10)
    }

    private func accent(_ tone: ProgressEnergyBreakdown.Tone) -> Color {
        switch tone {
        case .meal: AppTheme.mealAccent
        case .resting: AppMetricRole.body.accent
        case .activity: AppMetricRole.consistency.accent
        case .factor: AppMetricRole.performance.accent
        case .total: AppMetricRole.trainingLoad.accent
        }
    }
}

private struct EnergyBreakdownHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
