import SwiftData
import SwiftUI

struct ProgressEnergySourcesView: View {
    let snapshot: ProgressHistorySnapshot
    let healthError: String?
    @Environment(\.dismiss) private var dismiss

    private var day: ProgressDailyMetrics? {
        snapshot.days.last { !$0.isFuture }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("统计范围") {
                    Text(snapshot.window.title())
                    LabeledContent("摄入有记录日", value: "\(snapshot.intakeDayCount) 天")
                    LabeledContent("可估算日", value: "\(snapshot.estimateDayCount) 天")
                    if snapshot.window.period != .day {
                        Text("日均按已结束且有对应数据的日期计算；不是各月均值的平均。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let day {
                    Section(day.date.formatted(.dateTime.year().month().day())) {
                        LabeledContent("近 30 天有效设备日", value: "\(day.energy.eligibleDayCount) 天")
                        LabeledContent("已记录训练消耗", value: "\(day.trainingCalories.value.formatted()) kcal")
                        if day.trainingCalories.missingCount > 0 {
                            Text("\(day.trainingCalories.missingCount) 条训练未计入").foregroundStyle(.secondary)
                        }
                        if day.intake.missingCount > 0 {
                            Text("\(day.intake.missingCount) 条饮食能量不完整").foregroundStyle(.secondary)
                        }
                        if let estimate = day.energy.estimate {
                            LabeledContent("静息基准", value: "\(estimate.restingKilocalories.formatted(.number.precision(.fractionLength(0)))) kcal")
                            LabeledContent("有效活动系数", value: estimate.factor.formatted(.number.precision(.fractionLength(2))))
                            LabeledContent("来源", value: estimate.sourceName)
                            Text(formulaText(estimate))
                                .font(.subheadline.monospacedDigit())
                            if let first = estimate.evidenceDays.first, let last = estimate.evidenceDays.last {
                                Text("\(first.formatted(.dateTime.month().day()))—\(last.formatted(.dateTime.month().day()))，\(estimate.evidenceDays.count) 个有效日")
                            } else {
                                LabeledContent("参考生效日期", value: estimate.effectiveFrom.formatted(.dateTime.year().month().day()))
                            }
                            Text("预估已包含活动，不再另加训练。设备能量仍是估计，不等于真实全天消耗。")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text(healthError ?? day.energy.missingReason ?? "暂时无法估算").foregroundStyle(.secondary)
                        }
                    }
                    if let formula = day.restingFormula {
                        Section("个人静息公式") {
                            Text(formula.originalFormula)
                            Text(formula.substitutedFormula)
                            if day.usesLaterProfile {
                                Text("历史回算使用当前身高等个人资料及当时体重。")
                            }
                        }.font(.footnote)
                    }
                }
                Section {
                    NavigationLink("生活方式参考") { ProgressLifestyleEditor() }
                    NavigationLink("身体资料") { PersonalBodyInfoView() }
                }
            }
            .navigationTitle("能量依据").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func formulaText(_ estimate: AdaptiveEnergyEstimate) -> String {
        let resting = estimate.restingKilocalories.formatted(.number.precision(.fractionLength(0)))
        let factor = estimate.factor.formatted(.number.precision(.fractionLength(2)))
        let total = estimate.totalKilocalories.formatted(.number.precision(.fractionLength(0)))
        return "\(resting) × \(factor) ≈ \(total) kcal"
    }
}

private struct ProgressLifestyleEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var factorText = ""
    @State private var effectiveFrom = Date.now
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("本人确认的初始参考") {
                HStack {
                    Button("久坐为主") { factorText = "1.4" }
                    Spacer()
                    Button("经常走动") { factorText = "1.7" }
                    Spacer()
                    Button("高活动") { factorText = "2.0" }
                }.buttonStyle(.borderless).font(.subheadline)
                LabeledContent("有效活动系数") {
                    TextField("例如 1.4", text: $factorText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .accessibilityLabel("有效活动系数")
                }
                DatePicker("生效日期", selection: $effectiveFrom, in: ...Date.now, displayedComponents: .date)
                Text("反映工作、走动和训练的整体生活方式。充分的设备历史会优先更新估算；未确认前不会自动套用系数。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppTheme.warning)
            }
        }
        .navigationTitle("生活方式参考").navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                var query = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
                query.fetchLimit = 1
                let profile = try context.fetch(query).first
                if let last = try EnergyLifestyleStorage.decode(profile?.energyBaselinesData).max(by: { $0.effectiveFrom < $1.effectiveFrom }) {
                    factorText = last.factor.formatted(.number.grouping(.never))
                }
            } catch { errorMessage = "生活方式参考暂时无法读取" }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    do {
                        guard let factor = Double(factorText.replacingOccurrences(of: ",", with: ".")) else { throw EnergyLifestyleError.invalidFactor }
                        try EnergyLifestyleStore.save(factor: factor, label: "本人确认的生活方式", effectiveFrom: effectiveFrom, in: context)
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }.disabled(factorText.isEmpty)
            }
        }
    }
}
