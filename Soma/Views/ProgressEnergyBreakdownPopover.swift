import SwiftUI

struct ProgressEnergyBreakdownDisclosure<Label: View>: View {
    let snapshot: ProgressHistorySnapshot
    let kind: ProgressEnergyBreakdown.Kind
    var disclosureIdentifier = ""
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
        .accessibilityIdentifier(
            disclosureIdentifier.isEmpty
                ? "progress-\(kind.rawValue)-breakdown"
                : disclosureIdentifier
        )
        .accessibilityHint("查看组成明细")
    }
}

private struct ProgressEnergyBreakdownPopover: View {
    let source: ProgressEnergyBreakdown
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 44
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let maxHeight: CGFloat = dynamicTypeSize.isAccessibilitySize
            ? min(UIScreen.main.bounds.height * 0.75, 720) : 380
        let measured = contentHeight > 0 ? contentHeight : CGFloat(max(source.rows.count, 1)) * rowHeight + 16
        let slack: CGFloat = dynamicTypeSize.isAccessibilitySize ? 16 : 0
        let height = min(measured + slack, maxHeight)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(source.rows) { row in
                    rowView(row)
                    if row.id != source.rows.last?.id {
                        Divider().padding(.leading, 20)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .overlay {
                GeometryReader { geometry in
                    Color.clear.preference(key: EnergyBreakdownHeightKey.self, value: geometry.size.height)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(EnergyBreakdownHeightKey.self) { reported in
            let estimate = CGFloat(max(source.rows.count, 1)) * rowHeight + 16
            let limit = dynamicTypeSize.isAccessibilitySize ? max(estimate * 4, 600) : max(estimate * 2, estimate)
            if reported > 0, reported <= limit {
                contentHeight = reported
            }
        }
        .accessibilityIdentifier("progress-energy-breakdown-list")
        .frame(
            width: min(400, max(260, UIScreen.main.bounds.width - 32)),
            height: dynamicTypeSize.isAccessibilitySize ? maxHeight : height,
            alignment: .top
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
        case let .mealType(type): MealTypePresentation.accent(type)
        case .intakeTotal: AppTheme.accent
        case .resting: AppMetricRole.body.accent
        case .activity: AppMetricRole.consistency.accent
        case .factor: AppMetricRole.performance.accent
        case .total, .workout: AppMetricRole.trainingLoad.accent
        case .protein: AppTheme.vitalAccent
        case .carbs: AppTheme.trainingAccent
        case .fat: AppTheme.trendAccent
        }
    }
}

private struct EnergyBreakdownHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
