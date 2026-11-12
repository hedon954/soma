import SwiftData
import SwiftUI

struct EnergyCalibrationDayDetail: View {
    let day: EnergyCalibrationDay
    @Environment(\.modelContext) private var context
    @State private var meals: [MealEntry] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("本次评估采用的快照") {
                LabeledContent("日期", value: day.date.formatted(.dateTime.year().month().day()))
                LabeledContent("已确认完整饮食", value: day.foodComplete ? "是" : "否")
                LabeledContent("活动依据完整", value: day.activityComplete ? "是" : "否")
                LabeledContent("采用摄入", value: day.intake.map(energy) ?? "缺项")
                LabeledContent("校准前消耗估算", value: day.uncalibratedTotal.map(energy) ?? "缺项")
                LabeledContent("当天称重记录", value: "\(day.weights.count) 次")
                if let calculation = day.calculation {
                    LabeledContent("参考生活", value: energy(calculation.baseline))
                    LabeledContent("非训练步行差额", value: energy(calculation.walkingDelta))
                    LabeledContent("去重训练增量", value: energy(calculation.trainingDelta))
                    LabeledContent("采用体重", value: calculation.input.weightKG.formatted(.number.precision(.fractionLength(2))) + " kg")
                    ForEach(calculation.input.training) { event in
                        Text((event.activityType ?? "训练") + " · " + event.source)
                    }
                    ForEach(Array(Set(calculation.reasons)).sorted(), id: \.self) { Text($0).font(.footnote) }
                }
                Text("这里保留评估当时的输入。更正原记录会参与后续计算，不会改写这份历史。当前预估总消耗是静息 × 残差系数 + 所选日活动能量 + Soma 已记录训练消耗，不把日活动能量排除在外。")
                    .font(.footnote)
            }.listRowBackground(AppTheme.cardBackground)
            Section("饮食来源记录") {
                ForEach(meals) { meal in
                    NavigationLink(meal.title) { MealRecordDetailView(meal: meal) }
                }
                let missing = max(0, (day.sourceMealIDs?.count ?? 0) - meals.count)
                if missing > 0 {
                    Text("\(missing) 条原引用已不可用，计算依据仍按当时快照保留。").font(.footnote)
                }
            }.listRowBackground(AppTheme.cardBackground)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppTheme.warning)
            }
        }
        .font(.subheadline).foregroundStyle(AppTheme.accent).labeledContentStyle(EnergyEvidenceLabelStyle())
        .scrollContentBackground(.hidden).appPageBackground()
        .navigationTitle("每日评估依据").navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let ids = day.sourceMealIDs ?? []
                guard !ids.isEmpty else { return }
                var query = FetchDescriptor<MealEntry>(predicate: #Predicate { ids.contains($0.id) }, sortBy: [SortDescriptor(\.date)])
                query.fetchLimit = 256
                var values: [MealEntry] = []
                while true {
                    try Task.checkCancellation()
                    let page = try context.fetch(query)
                    values += page
                    guard page.count == 256 else { break }
                    query.fetchOffset = (query.fetchOffset ?? 0) + page.count
                }
                meals = values
            } catch is CancellationError {
                return
            } catch { errorMessage = AppErrorMessage.message(for: error, operation: .load) }
        }
    }

    private func energy(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + " kcal"
    }
}
