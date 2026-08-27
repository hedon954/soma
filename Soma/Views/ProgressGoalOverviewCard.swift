import SwiftUI

struct ProgressGoalOverviewCard: View {
    let goal: FitnessGoal?
    let intakeCalories: Int?
    let intakeIsPartial: Bool
    let intakeBreakdown: [ProgressMetricBreakdownItem]
    let restingCalories: Int?
    let restingUsesHealth: Bool
    let restingBreakdown: [ProgressMetricBreakdownItem]
    let dailyRestingEstimate: Double?
    let restingFormulaInput: RestingEnergyFormulaInput?
    let activeCalories: Int?
    let activeBreakdown: [ProgressMetricBreakdownItem]
    let muscleSets: [ProgressMuscleSetSummary]
    let trainingDays: Int
    let trainingDayBreakdown: [ProgressMetricBreakdownItem]
    let volume: Double?
    let volumeBreakdown: [ProgressMetricBreakdownItem]

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.map { "目标 · \($0.rawValue)" } ?? "目标尚未选择")
                        .font(.headline)
                    Text(goalDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if goal != .muscleGain {
                    energySummary
                }
                if goal != .fatLoss {
                    muscleSummary
                }
                if goal == nil {
                    Text("在身体信息里选择目标后，这里会保留相关指标。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var goalDescription: String {
        switch goal {
        case .fatLoss: "今天的摄入、消耗与全天预估"
        case .muscleGain: "最近 7 天训练覆盖与节奏"
        case .recomposition: "能量趋势与训练覆盖"
        case nil: "先明确目标，再看相关变化"
        }
    }

    private var energySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetricHeading(title: "今日能量", role: .trainingLoad)
            HStack(spacing: 0) {
                EnergyMetricTile(
                    title: intakeIsPartial ? "摄入（部分）" : "摄入",
                    value: intakeCalories,
                    valuePrefix: intakeIsPartial && intakeCalories != nil ? "≥ " : "",
                    source: .intake(intakeBreakdown)
                )
                Divider()
                EnergyMetricTile(
                    title: "静息",
                    value: restingCalories,
                    source: .resting(
                        usesHealth: restingUsesHealth,
                        components: restingBreakdown,
                        formula: restingFormulaInput
                    )
                )
                Divider()
                EnergyMetricTile(
                    title: "活动",
                    value: activeCalories,
                    source: .active(activeBreakdown)
                )
                Divider()
                EnergyMetricTile(
                    title: "全天",
                    value: dailyProjection?.dailyTotalKilocalories,
                    source: .dailyTotal(dailyProjection)
                )
            }
            .padding(.horizontal, 2)
            .background(
                AppTheme.insetBackground,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )

            HStack(spacing: 8) {
                Text("预计能量差")
                    .font(.caption)
                Text(signedEnergyBalance)
                    .font(.caption.weight(.medium).monospacedDigit())
                Spacer()
                ProgressSourceButton(
                    source: .energyBalance(
                        intake: intakeCalories,
                        expenditure: dailyProjection?.dailyTotalKilocalories
                    )
                )
            }
            .padding(.leading, 4)
            .frame(minHeight: AppTheme.minimumTapTarget)
            .foregroundStyle(.secondary)
        }
    }

    private var muscleSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                MetricHeading(title: "最近 7 天增肌训练", role: .trainingLoad)
                Spacer()
                ProgressSourceButton(
                    source: .muscleCoverage(
                        muscleSets.map {
                            ProgressMetricBreakdownItem(
                                label: $0.name,
                                value: "\($0.sets) 组"
                            )
                        }
                    )
                )
            }

            HStack(spacing: 14) {
                compactMetric(
                    "\(trainingDays) 个训练日",
                    icon: "calendar.badge.checkmark",
                    source: .trainingDays(trainingDayBreakdown)
                )
                if let volume {
                    compactMetric(
                        "\(volume.formatted(.number.precision(.fractionLength(0)))) kg",
                        icon: "scalemass",
                        source: .trainingVolume(volumeBreakdown)
                    )
                }
            }

            if muscleSets.isEmpty {
                Text("还没有可计算的主要肌群工作组。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(muscleSets.prefix(6)) { item in
                    HStack(spacing: 10) {
                        Text(item.name)
                            .font(.caption)
                            .frame(width: 72, alignment: .leading)
                        ProgressView(value: min(Double(item.sets) / 10, 1))
                            .tint(AppMetricRole.trainingLoad.accent)
                        Text("\(item.sets) 组")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func compactMetric(
        _ text: String,
        icon: String,
        source: ProgressMetricSource
    ) -> some View {
        HStack(spacing: 2) {
            Label(text, systemImage: icon)
                .font(.caption.weight(.medium))
            ProgressSourceButton(source: source)
        }
        .foregroundStyle(.secondary)
    }

    private var dailyProjection: DailyEnergyProjectionResult? {
        DailyEnergyProjectionCalculator.estimate(
            restingKilocaloriesSoFar: restingCalories,
            dailyRestingEstimate: dailyRestingEstimate,
            restingUsesHealth: restingUsesHealth,
            activeKilocaloriesSoFar: activeCalories
        )
    }

    private var signedEnergyBalance: String {
        guard let intakeCalories,
              let total = dailyProjection?.dailyTotalKilocalories
        else {
            return "—"
        }
        let value = intakeCalories - total
        return value > 0 ? "+\(value) kcal" : "\(value) kcal"
    }
}

private struct EnergyMetricTile: View {
    let title: String
    let value: Int?
    var valuePrefix = ""
    var valueSuffix = ""
    let source: ProgressMetricSource

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                ProgressSourceButton(source: source)
            }
            Text(value.map { "\(valuePrefix)\($0)" } ?? "—")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value == nil ? "kcal" : "kcal\(valueSuffix)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, minHeight: 68)
        .accessibilityElement(children: .contain)
    }
}
