import SwiftData
import SwiftUI

struct ProgressEnergySourcesView: View {
    let snapshot: ProgressHistorySnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date?

    private var day: ProgressDailyMetrics? {
        snapshot.days.first { $0.date == selectedDate && !$0.isFuture } ?? snapshot.days.last { !$0.isFuture }
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    if let day {
                        if snapshot.window.period == .day {
                            LabeledContent("日期", value: day.date.formatted(.dateTime.year().month().day()))
                        } else {
                            Picker("日期", selection: Binding(get: { day.date }, set: { selectedDate = $0 })) {
                                ForEach(snapshot.days.filter { !$0.isFuture }) { item in
                                    Text(item.date.formatted(.dateTime.year().month().day())).tag(item.date)
                                }
                            }
                        }
                        LabeledContent("静息消耗", value: energy(day.energy.estimate?.restingKilocalories ?? day.restingFormula?.dailyKilocalories))
                        LabeledContent("残差系数", value: factorText(day.energy.estimate))
                        if let components = day.energy.estimate?.components {
                            let displayed = EnergyKilocalorieDisplay.parts(components)
                            LabeledContent("基准额外消耗", value: EnergyKilocalorieDisplay.kcal(displayed.baselineExtra))
                            activityContent(displayed.activity)
                        }
                        LabeledContent("预估总消耗", value: day.energy.estimate?.components.map {
                            EnergyKilocalorieDisplay.kcal(EnergyKilocalorieDisplay.parts($0).total)
                        } ?? energy(day.energy.estimate?.totalKilocalories))
                        LabeledContent("已记录摄入", value: day.intake.knownCount > 0 ? energy(day.intake.value) : "未记录")
                        LabeledContent(day.foodConfirmedComplete ? "预估热量缺口" : "已记饮食差额", value: day.recordedEnergyDifference.map { energy($0) }
                            ?? day.energyDeficitMissingReason ?? "待估算")
                        if day.energy.estimate == nil {
                            NavigationLink("补充身体资料") { PersonalBodyInfoView() }
                        }
                        DisclosureGroup("计算明细") {
                            calculationDetails(day)
                        }
                        NavigationLink("系数与调整历史") { EnergyHistoryView() }
                        NavigationLink("生活与记录确认") { EnergyContextRecordsView() }
                        if let calculation = day.energy.estimate?.calculation, !calculation.input.training.isEmpty {
                            NavigationLink("同场训练关联") { EnergyTrainingLinksView(calculation: calculation) }
                        }
                        Button("完善生活信息") {
                            dismiss()
                            CoachComposerCommand.pendingSend = CoachComposerCommand.energyContextOpening
                            NotificationCenter.default.post(name: .sendCoachMessage, object: nil)
                        }.frame(minHeight: 44)
                    }
                    Section("近期习惯水平") {
                        if let factor = snapshot.habitualEnergyFactor {
                            LabeledContent("近 28 天有效系数", value: factor.formatted(.number.precision(.fractionLength(2))))
                            Text("这是历史参考日差额的汇总，不加入当前预估总消耗，也不会再加到休息日。")
                                .font(.footnote).foregroundStyle(AppTheme.accent)
                        } else {
                            Text("需要近 28 天至少 21 个活动依据完整的结束日，且每周都有覆盖。")
                                .font(.footnote).foregroundStyle(AppTheme.accent)
                        }
                    }
                    if !snapshot.energyForecasts.isEmpty {
                        Section("未来 7 天预测") {
                            ForEach(snapshot.energyForecasts) { forecast in
                                VStack(alignment: .leading, spacing: 6) {
                                    LabeledContent(forecast.date.formatted(.dateTime.month().day().weekday()),
                                                   value: forecast.total.map { energy($0) } ?? "依据不足")
                                    Text(forecast.source).font(.footnote).foregroundStyle(AppTheme.accent)
                                }
                            }
                            Text("未来日期没有所选日活动能量，不编造该读数。预测只在静息 × 残差系数上加上计划或同星期训练的活动能量，不按训练时长扣减，也不进入已发生消耗、缺口或校准。")
                                .font(.footnote).foregroundStyle(AppTheme.accent)
                        }
                    }
                }.listRowBackground(AppTheme.cardBackground)
            }
            .font(.subheadline)
            .labeledContentStyle(EnergyEvidenceLabelStyle())
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .appPageBackground()
            .navigationTitle("能量依据").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationBackground(AppTheme.pageBackground)
    }

    @ViewBuilder
    private func calculationDetails(_ day: ProgressDailyMetrics) -> some View {
        if let estimate = day.energy.estimate {
            Text(formulaText(estimate)).monospacedDigit()
            LabeledContent("静息来源", value: estimate.restingSourceName)
            if estimate.method == .confirmedLifestyle {
                LabeledContent("参考生效", value: estimate.effectiveFrom.formatted(.dateTime.year().month().day()))
            }
            Text("预估总消耗 = 静息 × 残差系数 + 所选日活动能量。系数表示静息，以及所选活动能量没有覆盖的估算消耗，不是传统全天活动水平。已经包含在日活动能量里的训练不会再加一次；没有读数时不编造。")
                .foregroundStyle(AppTheme.accent)
            if let calculation = estimate.calculation {
                Text(calculation.input.reference.reason).font(.footnote)
                ForEach(Array(Set(calculation.reasons)).sorted(), id: \.self) { reason in
                    Text(reason).font(.footnote).foregroundStyle(AppTheme.accent)
                }
            }
        } else {
            Text(day.energy.missingReason ?? "缺少静息资料").foregroundStyle(.secondary)
        }
        if let formula = day.restingFormula {
            Text(formula.originalFormula).font(.footnote)
            Text(formula.substitutedFormula).font(.footnote)
            if day.usesLaterProfile {
                Text("历史回算使用当前身高等资料及当时体重。").font(.footnote).foregroundStyle(.secondary)
            }
        }
        if day.trainingCalories.missingCount > 0 {
            LabeledContent("训练能量缺项", value: "\(day.trainingCalories.missingCount) 条")
        }
        if day.intake.missingCount > 0 {
            LabeledContent("饮食能量缺项", value: "\(day.intake.missingCount) 条")
        }
        NavigationLink("身体资料") { PersonalBodyInfoView() }
    }

    private func energy(_ value: Double?) -> String {
        value.map { EnergyKilocalorieDisplay.kcal($0) } ?? "缺少静息资料"
    }

    private func factorText(_ estimate: AdaptiveEnergyEstimate?) -> String {
        guard let estimate else {
            let fallback = ResidualEnergyCoefficient.initialFallback.formatted(.number.precision(.fractionLength(2)))
            return fallback + " · 初始回退"
        }
        let source = switch estimate.method {
        case .confirmedLifestyle: "个人设置"
        case .defaultReference: "初始回退"
        case .dynamicActivity: "动态估算"
        }
        return estimate.factor.formatted(.number.precision(.fractionLength(2))) + " · " + source
    }

    private func formulaText(_ estimate: AdaptiveEnergyEstimate) -> String {
        let factor = estimate.factor.formatted(.number.precision(.fractionLength(2)))
        let displayed = estimate.components.map(EnergyKilocalorieDisplay.parts)
        let resting = displayed.map { EnergyKilocalorieDisplay.text($0.resting) }
            ?? EnergyKilocalorieDisplay.text(estimate.restingKilocalories)
        let total = displayed.map { EnergyKilocalorieDisplay.text($0.total) }
            ?? EnergyKilocalorieDisplay.text(estimate.totalKilocalories)
        if let displayed, displayed.displayedActivity > 0 {
            return "\(resting) × \(factor) + \(EnergyKilocalorieDisplay.text(displayed.displayedActivity)) ≈ \(total) kcal"
        }
        return "\(resting) × \(factor) ≈ \(total) kcal"
    }

    @ViewBuilder
    private func activityContent(_ activity: DailyEnergyTotal.Activity) -> some View {
        switch activity {
        case .absent:
            LabeledContent("活动消耗", value: "未记录")
        case let .selected(value), let .recordedTraining(value):
            LabeledContent("活动消耗", value: energy(value))
        case let .disaggregated(training, remaining):
            Group {
                LabeledContent("训练活动消耗", value: energy(training))
                LabeledContent("其余活动消耗", value: energy(remaining))
            }
        }
    }
}
