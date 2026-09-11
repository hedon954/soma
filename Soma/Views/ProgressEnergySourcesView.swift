import SwiftData
import SwiftUI

struct ProgressEnergySourcesView: View {
    let snapshot: ProgressHistorySnapshot
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedDate: Date?

    private var day: ProgressDailyMetrics? {
        snapshot.days.first { $0.date == selectedDate && !$0.isFuture } ?? snapshot.days.last { !$0.isFuture }
    }

    var body: some View {
        NavigationStack {
            List {
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
                    NavigationLink {
                        ProgressLifestyleEditor()
                    } label: {
                        LabeledContent("活动系数", value: factorText(day.energy.estimate))
                    }
                    LabeledContent("预估总消耗", value: energy(day.energy.estimate?.totalKilocalories))
                    LabeledContent("已记录摄入", value: day.intake.knownCount > 0 ? energy(day.intake.value) : "未记录")
                    LabeledContent("预估热量缺口", value: day.estimatedEnergyDeficit.map { energy($0) }
                        ?? day.energyDeficitMissingReason ?? "待估算")
                    LabeledContent("已记录训练消耗", value: energy(day.trainingCalories.value))
                    if let net = day.energy.estimate?.trainingNetKilocalories, net > 0 || day.trainingCalories.knownCount > 0 {
                        LabeledContent("计入总消耗的训练", value: energy(net))
                    }
                    if day.energy.estimate == nil {
                        NavigationLink("补充身体资料") { PersonalBodyInfoView() }
                    }
                    DisclosureGroup("计算明细") {
                        calculationDetails(day)
                    }
                }
            }
            .font(.subheadline)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .appPageBackground()
            .navigationTitle("能量依据").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }

    @ViewBuilder
    private func calculationDetails(_ day: ProgressDailyMetrics) -> some View {
        if let estimate = day.energy.estimate {
            Text(formulaText(estimate)).monospacedDigit()
            LabeledContent("静息来源", value: estimate.restingSourceName)
            if estimate.method == .confirmedLifestyle {
                LabeledContent("参考生效", value: estimate.effectiveFrom.formatted(.dateTime.year().month().day()))
            }
            Text("记录写整段训练；总消耗只加去掉与静息重叠后的部分。系数不含当天训练。")
                .foregroundStyle(.secondary)
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
        value.map { $0.formatted(.number.precision(.fractionLength(0))) + " kcal" } ?? "缺少静息资料"
    }

    private func factorText(_ estimate: AdaptiveEnergyEstimate?) -> String {
        guard let estimate else { return "默认参考 1.40" }
        let source = switch estimate.method {
        case .confirmedLifestyle: "个人设置"
        case .defaultReference: "默认参考"
        }
        return estimate.factor.formatted(.number.precision(.fractionLength(2))) + " · " + source
    }

    private func formulaText(_ estimate: AdaptiveEnergyEstimate) -> String {
        let resting = estimate.restingKilocalories.formatted(.number.precision(.fractionLength(0)))
        let factor = estimate.factor.formatted(.number.precision(.fractionLength(2)))
        let total = estimate.totalKilocalories.formatted(.number.precision(.fractionLength(0)))
        if estimate.trainingNetKilocalories > 0 {
            let net = estimate.trainingNetKilocalories.formatted(.number.precision(.fractionLength(0)))
            return "\(resting) × \(factor) + \(net) ≈ \(total) kcal"
        }
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
                Text("只描述日常怎么过，不含当天训练。默认参考 1.4；已确认的个人设置优先。")
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
            } catch { errorMessage = AppErrorMessage.message(for: error, operation: .load) }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    do {
                        guard let factor = Double(factorText.replacingOccurrences(of: ",", with: ".")) else { throw EnergyLifestyleError.invalidFactor }
                        try EnergyLifestyleStore.save(factor: factor, label: "本人确认的生活方式", effectiveFrom: effectiveFrom, in: context)
                        dismiss()
                    } catch { errorMessage = AppErrorMessage.message(for: error, operation: .save) }
                }.disabled(factorText.isEmpty)
            }
        }
    }
}
