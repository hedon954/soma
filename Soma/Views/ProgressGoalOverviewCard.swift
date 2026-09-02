import SwiftUI

struct ProgressGoalOverviewCard: View {
    let goal: FitnessGoal?
    let onSelectGoal: (FitnessGoal?) -> Void
    let intakeCalories: Int?
    let intakeIsPartial: Bool
    let intakeBreakdown: [ProgressMetricBreakdownItem]
    let restingCalories: Int?
    let restingUsesHealth: Bool
    let restingBreakdown: [ProgressMetricBreakdownItem]
    let dailyRestingEstimate: Double?
    let restingFormulaInput: RestingEnergyFormulaInput?
    let activeCalories: Int?
    let activeUsesHealth: Bool
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
                    Menu {
                        Button {
                            onSelectGoal(nil)
                        } label: {
                            if goal == nil {
                                Label("暂不选择", systemImage: "checkmark")
                            } else {
                                Text("暂不选择")
                            }
                        }
                        ForEach(FitnessGoal.allCases) { option in
                            Button {
                                onSelectGoal(option)
                            } label: {
                                if option == goal {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(goal.map { "目标 · \($0.rawValue)" } ?? "目标尚未选择")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: AppTheme.minimumTapTarget)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("当前目标：\(goal?.rawValue ?? "未选择")")
                    .accessibilityHint("直接选择进展页关注的目标")
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
            }
        }
    }

    private var goalDescription: String {
        switch goal {
        case .fatLoss: "今天已记录的摄入与截至当前消耗"
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
                    title: "已记录摄入",
                    value: intakeCalories,
                    valuePrefix: intakeIsPartial && intakeCalories != nil ? "≥ " : "",
                    source: .intake(intakeBreakdown)
                )
                Divider()
                EnergyMetricTile(
                    title: "截至当前总消耗",
                    value: currentExpenditure,
                    source: .currentTotal(
                        resting: restingCalories,
                        active: activeCalories,
                        activeUsesHealth: activeUsesHealth
                    )
                )
            }
            .padding(.horizontal, 2)
            .background(
                AppTheme.insetBackground,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )

            HStack(spacing: 0) {
                EnergyMetricTile(
                    title: "静息消耗",
                    value: restingCalories,
                    source: .resting(
                        usesHealth: restingUsesHealth,
                        components: restingBreakdown,
                        formula: restingFormulaInput
                    )
                )
                Divider()
                EnergyMetricTile(
                    title: activeUsesHealth ? "活动消耗" : "训练消耗",
                    value: activeCalories,
                    source: .active(activeBreakdown)
                )
            }
            .padding(.horizontal, 2)
            .background(
                AppTheme.insetBackground,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )

            ProgressSourceDisclosure(
                source: .energyBalance(
                    intake: intakeCalories,
                    expenditure: currentExpenditure
                )
            ) {
                HStack(spacing: 8) {
                    Text("截至当前能量差")
                        .font(.caption)
                    Text(signedEnergyBalance)
                        .font(.caption.weight(.medium).monospacedDigit())
                    Spacer()
                }
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, minHeight: AppTheme.minimumTapTarget)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var muscleSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressSourceDisclosure(
                source: .muscleCoverage(
                    muscleSets.map {
                        ProgressMetricBreakdownItem(
                            label: $0.name,
                            value: "\($0.sets) 组"
                        )
                    }
                )
            ) {
                MetricHeading(title: "最近 7 天增肌训练", role: .trainingLoad)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: AppTheme.minimumTapTarget)
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
        ProgressSourceDisclosure(source: source) {
            Label(text, systemImage: icon)
                .font(.caption.weight(.medium))
                .frame(minHeight: AppTheme.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.secondary)
    }

    private var currentExpenditure: Int? {
        guard let restingCalories, let activeCalories else { return nil }
        return restingCalories + activeCalories
    }

    private var signedEnergyBalance: String {
        guard let intakeCalories,
              let total = currentExpenditure
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
        ProgressSourceDisclosure(source: source) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(value.map { "\(valuePrefix)\($0)" } ?? "—")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(value == nil ? "kcal" : "kcal\(valueSuffix)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 68)
        }
        .frame(maxWidth: .infinity)
    }
}
