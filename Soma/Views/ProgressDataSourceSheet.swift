import SwiftUI

enum ProgressPopoverLayout {
    static let maximumWidth: CGFloat = 400
    static let minimumWidth: CGFloat = 260
    static let screenMargin: CGFloat = 24

    static func width(for screenWidth: CGFloat) -> CGFloat {
        min(maximumWidth, max(minimumWidth, screenWidth - screenMargin))
    }
}

struct ProgressSourceRow: Equatable {
    let label: String
    let value: String
}

enum ProgressMetricSource: Identifiable, Equatable {
    case intake([ProgressMetricBreakdownItem])
    case resting(
        usesHealth: Bool,
        components: [ProgressMetricBreakdownItem],
        formula: RestingEnergyFormulaInput?
    )
    case active([ProgressMetricBreakdownItem])
    case dailyTotal(DailyEnergyProjectionResult?)
    case energyBalance(intake: Int?, expenditure: Int?)
    case trainingDays([ProgressMetricBreakdownItem])
    case trainingVolume([ProgressMetricBreakdownItem])
    case muscleCoverage([ProgressMetricBreakdownItem])
    case trend(ProgressTrendSeries)

    var id: String {
        switch self {
        case .intake: "intake"
        case .resting: "resting"
        case .active: "active"
        case .dailyTotal: "daily-total"
        case .energyBalance: "energy-balance"
        case .trainingDays: "training-days"
        case .trainingVolume: "training-volume"
        case .muscleCoverage: "muscle-coverage"
        case let .trend(series): "trend-\(series.metric.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .intake: "摄入来源"
        case .resting: "静息消耗来源"
        case .active: "活动消耗来源"
        case .dailyTotal: "全天总消耗预估"
        case .energyBalance: "能量差来源"
        case .trainingDays: "训练日来源"
        case .trainingVolume: "训练容量来源"
        case .muscleCoverage: "肌群工作组来源"
        case let .trend(series): "\(series.metric.title)明细"
        }
    }

    var rows: [ProgressSourceRow] {
        switch self {
        case let .intake(components):
            return componentRows(components)
        case let .resting(usesHealth, components, formula):
            if usesHealth {
                return componentRows(components)
            }
            guard let formula else {
                return [ProgressSourceRow(label: "缺少身体资料", value: "暂不估算")]
            }
            let sexAdjustment = formula.biologicalSex == .male ? 5 : -161
            return [
                ProgressSourceRow(
                    label: "体重项 · 10 × \(formula.weightKG.formatted()) kg",
                    value: "\(Int((10 * formula.weightKG).rounded())) kcal"
                ),
                ProgressSourceRow(
                    label: "身高项 · 6.25 × \(formula.heightCM.formatted()) cm",
                    value: "\(Int((6.25 * formula.heightCM).rounded())) kcal"
                ),
                ProgressSourceRow(
                    label: "年龄项 · −5 × \(formula.age)",
                    value: "−\(5 * formula.age) kcal"
                ),
                ProgressSourceRow(
                    label: "生理性别项",
                    value: signedKilocalories(sexAdjustment)
                ),
                ProgressSourceRow(
                    label: "24h 静息",
                    value: "\(Int(formula.dailyKilocalories.rounded())) kcal"
                )
            ]
        case let .active(components):
            return componentRows(components)
        case let .dailyTotal(projection):
            guard let projection else {
                return [ProgressSourceRow(label: "必要数据不足", value: "暂不估算")]
            }
            return [
                ProgressSourceRow(
                    label: "全天静息预估",
                    value: "\(projection.projectedRestingKilocalories) kcal"
                ),
                ProgressSourceRow(
                    label: "全天活动预估",
                    value: "\(projection.projectedActiveKilocalories) kcal"
                )
            ]
        case let .energyBalance(intake, expenditure):
            guard let intake, let expenditure else {
                return [ProgressSourceRow(label: "必要数据不足", value: "暂不计算")]
            }
            return [
                ProgressSourceRow(label: "今日摄入", value: "+\(intake) kcal"),
                ProgressSourceRow(label: "全天总消耗预估", value: "−\(expenditure) kcal")
            ]
        case let .trainingDays(components):
            return componentRows(components, emptyLabel: "最近 7 天没有训练")
        case let .trainingVolume(components):
            return componentRows(
                components,
                emptyLabel: "最近 7 天没有可计算容量"
            )
        case let .muscleCoverage(components):
            return components.isEmpty
                ? [ProgressSourceRow(label: "最近 7 天没有主要肌群工作组", value: "—")]
                : components.map { ProgressSourceRow(label: $0.label, value: $0.value) }
        case let .trend(series):
            return trendRows(series)
        }
    }

    var formulaLines: [String] {
        switch self {
        case let .resting(usesHealth, _, formula):
            guard !usesHealth, let formula else { return [] }
            return [formula.originalFormula, formula.substitutedFormula]
        case let .dailyTotal(projection):
            guard let projection else {
                return ["静息 + 活动", "必要数据不足，暂不估算"]
            }
            return [projection.originalFormula, projection.substitutedFormula]
        default:
            return []
        }
    }

    var accent: Color {
        switch self {
        case .intake: AppSemanticRole.meal.accent
        case .resting, .active, .dailyTotal, .energyBalance, .trainingVolume:
            AppMetricRole.trainingLoad.accent
        case .trainingDays: AppMetricRole.consistency.accent
        case .muscleCoverage: AppSemanticRole.training.accent
        case let .trend(series): series.metric.accent
        }
    }

    private func componentRows(
        _ components: [ProgressMetricBreakdownItem],
        emptyLabel: String = "暂无可计算明细"
    ) -> [ProgressSourceRow] {
        guard !components.isEmpty else {
            return [ProgressSourceRow(label: emptyLabel, value: "—")]
        }
        return components.map {
            ProgressSourceRow(label: $0.label, value: $0.value)
        }
    }

    private func trendRows(_ series: ProgressTrendSeries) -> [ProgressSourceRow] {
        guard !series.points.isEmpty else {
            return [ProgressSourceRow(label: "最近 30 天没有记录", value: "—")]
        }
        return series.points.reversed().map { point in
            ProgressSourceRow(
                label: point.date.formatted(.dateTime.month().day()),
                value: series.metric.valueText(point)
            )
        }
    }

    private func signedKilocalories(_ value: Int) -> String {
        value > 0 ? "+\(value) kcal" : "\(value) kcal"
    }
}

struct ProgressSourceDisclosure<Label: View>: View {
    let source: ProgressMetricSource
    @ViewBuilder let label: () -> Label
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看\(source.title)")
        .accessibilityHint("在当前位置展开组成明细")
        .popover(
            isPresented: $isPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            ProgressDataSourcePopover(source: source)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct ProgressDataSourcePopover: View {
    let source: ProgressMetricSource

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(Array(source.rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(rowAccent(index))
                                .frame(width: 10, height: 10)
                            Text(row.label)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            Spacer(minLength: 8)
                            Text(row.value)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(rowAccent(index))
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.vertical, 10)
                        if index < source.rows.count - 1 {
                            Divider()
                                .padding(.leading, 22)
                        }
                    }
                }

                if !source.formulaLines.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(source.formulaLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(index == 0 ? .subheadline : .caption)
                                .foregroundStyle(index == 0 ? .primary : .secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .allowsTightening(true)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        AppTheme.insetBackground,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .frame(width: preferredWidth, height: preferredHeight)
        .background(AppTheme.cardBackground)
        .accessibilityElement(children: .contain)
    }

    private var preferredWidth: CGFloat {
        ProgressPopoverLayout.width(for: UIScreen.main.bounds.width)
    }

    private var preferredHeight: CGFloat {
        let rowsHeight = CGFloat(max(source.rows.count, 1)) * 45
        let formulaHeight: CGFloat = source.formulaLines.isEmpty ? 0 : 78
        return min(rowsHeight + formulaHeight + 24, 380)
    }

    private func rowAccent(_ index: Int) -> Color {
        let palette = [
            source.accent,
            AppMetricRole.consistency.accent,
            AppMetricRole.performance.accent,
            AppMetricRole.body.accent,
            AppMetricRole.vital.accent
        ]
        return palette[index % palette.count]
    }
}

extension ProgressTrendMetric {
    var title: String {
        switch self {
        case .trainingVolume: "训练容量"
        case .calorieIntake: "能量摄入"
        case .weight: "体重"
        }
    }

    var accent: Color {
        switch self {
        case .trainingVolume: AppMetricRole.trainingLoad.accent
        case .calorieIntake: AppSemanticRole.meal.accent
        case .weight: AppMetricRole.body.accent
        }
    }

    func valueText(_ point: ProgressTrendPoint) -> String {
        switch self {
        case .trainingVolume:
            "\(point.value.formatted(.number.precision(.fractionLength(0)))) kg"
        case .calorieIntake:
            "\(point.isPartial ? "≥ " : "")\(Int(point.value.rounded())) kcal"
        case .weight:
            "\(point.value.formatted(.number.precision(.fractionLength(1)))) kg"
        }
    }
}
