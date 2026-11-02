import SwiftData
import SwiftUI

struct EnergyHistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(EnergyRefreshCoordinator.self) private var refresh
    @State private var kind = EnergyEvidenceKind.daily
    @State private var rows: [EnergyEvidenceDTO] = []
    @State private var hasMore = false
    @State private var paused = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Toggle("暂停自动校准", isOn: Binding(get: { paused }, set: { value in
                    do {
                        try EnergyControlStore.setPaused(value, in: context)
                        paused = value
                    } catch { errorMessage = AppErrorMessage.message(for: error, operation: .save) }
                })).appToggleStyle()
                Text("暂停后保留已有修正，每日步行与训练仍正常参与估算。")
                    .font(.footnote)
                if let failure = refresh.errorMessage {
                    Text(failure).foregroundStyle(AppTheme.warning)
                }
            }.listRowBackground(AppTheme.cardBackground)
            Section {
                Picker("历史类型", selection: $kind) {
                    Text("每日系数").tag(EnergyEvidenceKind.daily)
                    Text("长期调整").tag(EnergyEvidenceKind.calibration)
                }.pickerStyle(.segmented)
                ForEach(rows, id: \.key) { row in
                    NavigationLink {
                        EnergyEvidenceDetail(entry: row)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.date.formatted(.dateTime.year().month().day()))
                            Text(summary(row)).font(.subheadline)
                            if row.revision > 0 {
                                Text("更正记录").font(.caption)
                            }
                        }
                    }.accessibilityIdentifier("energy-history-row")
                }
                if hasMore {
                    Button("更早的记录") { load(reset: false) }.frame(minHeight: 44)
                }
                if rows.isEmpty {
                    Text(kind == .daily ? "打开 Soma 后会保留当天的估算依据。" : "尚无长期调整。记录不足时会保留当前估算，并说明暂停原因。")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppTheme.warning)
                }
            }.listRowBackground(AppTheme.cardBackground)
        }
        .font(.subheadline).foregroundStyle(AppTheme.accent)
        .labeledContentStyle(EnergyEvidenceLabelStyle())
        .scrollContentBackground(.hidden).appPageBackground()
        .navigationTitle("系数与调整历史").navigationBarTitleDisplayMode(.inline)
        .task(id: kind) { load(reset: true) }
    }

    private func load(reset: Bool) {
        do {
            paused = try EnergyControlStore.isPaused(in: context)
            let raw = kind.rawValue
            var query: FetchDescriptor<EnergyEvidenceEntry>
            if !reset, let last = rows.last {
                let date = last.date, revision = last.revision, key = last.key
                query = .init(predicate: #Predicate {
                    $0.kindRaw == raw && ($0.date < date || ($0.date == date && $0.revision < revision)
                        || ($0.date == date && $0.revision == revision && $0.key > key))
                })
            } else {
                query = .init(predicate: #Predicate { $0.kindRaw == raw })
            }
            query.sortBy = [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.revision, order: .reverse), SortDescriptor(\.key)]
            query.fetchLimit = 50
            let page = try context.fetch(query).map(EnergyEvidenceDTO.init)
            rows = reset ? page : rows + page
            hasMore = page.count == 50
            errorMessage = nil
        } catch { errorMessage = AppErrorMessage.message(for: error, operation: .load) }
    }

    private func summary(_ row: EnergyEvidenceDTO) -> String {
        if row.kindRaw == EnergyEvidenceKind.daily.rawValue,
           let value = try? JSONDecoder().decode(EnergyDayCalculation.self, from: row.payload)
        {
            return "系数约 " + value.factor.formatted(.number.precision(.fractionLength(2))) + " · " + energyText(value.total)
        }
        if let review = try? JSONDecoder().decode(EnergyCalibrationReview.self, from: row.payload) {
            return review.delta == 0 ? "保持不变 · " + review.reason : energyText(review.previousCorrection) + " → " + energyText(review.nextCorrection)
        }
        return "依据暂时无法读取，请重新打开"
    }
}

private struct EnergyEvidenceDetail: View {
    let entry: EnergyEvidenceDTO
    @Environment(\.modelContext) private var context
    @State private var errorMessage: String?
    @State private var restored = false
    @State private var previousFactor: Double?

    var body: some View {
        List {
            if entry.kindRaw == EnergyEvidenceKind.daily.rawValue,
               let value = try? JSONDecoder().decode(EnergyDayCalculation.self, from: entry.payload)
            {
                Section("当天估算") {
                    LabeledContent("日期", value: value.input.date.formatted(.dateTime.year().month().day()))
                    LabeledContent("有效系数", value: value.factor.formatted(.number.precision(.fractionLength(2))))
                    if let previousFactor {
                        LabeledContent("上次估算系数", value: previousFactor.formatted(.number.precision(.fractionLength(2))))
                    }
                    LabeledContent("静息估算", value: energyText(value.input.resting))
                    LabeledContent("参考生活消耗", value: energyText(value.baseline))
                    LabeledContent("非训练步行差额", value: energyText(value.walkingDelta))
                    LabeledContent("训练增量", value: energyText(value.trainingDelta))
                    LabeledContent("长期修正", value: energyText(value.input.correction))
                    LabeledContent("全天估算", value: energyText(value.total))
                    LabeledContent("算法", value: value.algorithmVersion ?? "版本未记录")
                    LabeledContent("参考系数", value: value.input.reference.factor.formatted(.number.precision(.fractionLength(3))))
                    LabeledContent("参考非训练距离", value: value.input.reference.walkingKilometers.map {
                        $0.formatted(.number.precision(.fractionLength(2))) + " km"
                    } ?? "尚未建立")
                    LabeledContent("被训练替代的时段活动", value: value.displacedActivityPerHour.formatted(.number.precision(.fractionLength(1))) + " kcal/小时")
                    Text("总消耗 = 参考生活消耗 + 非训练步行差额 + 训练增量 + 长期修正")
                        .font(.footnote)
                    Text(value.input.reference.reason)
                    if let formula = value.input.restingFormula {
                        Text(formula.substitutedFormula).font(.footnote)
                    }
                    if let weightDate = value.input.weightRecordDate {
                        LabeledContent("采用体重日期", value: weightDate.formatted(.dateTime.year().month().day()))
                    }
                    Text("本次计算于 " + entry.createdAt.formatted(.dateTime.year().month().day().hour().minute()) + "，按当时可用记录估算。")
                        .font(.footnote)
                }.listRowBackground(AppTheme.cardBackground)
                Section("采用与未采用的依据") {
                    if let distance = value.input.nonTrainingKilometers {
                        LabeledContent("非训练距离", value: distance.formatted(.number.precision(.fractionLength(2))) + " km")
                    }
                    ForEach(value.input.training) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text((event.activityType ?? "训练") + " · " + event.source)
                            Text(value.adoptedTrainingIDs.contains(event.id) ? "已计入一次" : event.linkedIdentity != nil
                                ? "同场关联后仅采用一份能量" : "未计入，需确认口径或关联")
                            Text(event.components == nil ? event.scope.label : "本地各动作净能量之和").font(.footnote)
                        }
                    }
                    ForEach(Array(Set(value.reasons)).sorted(), id: \.self) { Text($0) }
                }.listRowBackground(AppTheme.cardBackground)
            } else if let review = try? JSONDecoder().decode(EnergyCalibrationReview.self, from: entry.payload) {
                Section("本次判断") {
                    Text(review.reason)
                    LabeledContent("此前修正", value: energyText(review.previousCorrection))
                    LabeledContent("采用修正", value: energyText(review.nextCorrection))
                    LabeledContent("生效日期", value: review.date.formatted(.dateTime.year().month().day()))
                    LabeledContent("算法", value: review.algorithmVersion ?? "版本未记录")
                    LabeledContent("观察开始", value: review.windowStart.formatted(.dateTime.year().month().day()))
                    LabeledContent("观察结束前", value: review.windowEnd.formatted(.dateTime.year().month().day()))
                    LabeledContent("称重日期数", value: "\(review.weightDayCount) 天")
                    if let intake = review.meanIntake {
                        LabeledContent("日均摄入", value: energyText(intake))
                    }
                    if let model = review.meanModel {
                        LabeledContent("日均原始估算", value: energyText(model))
                    }
                    if let slope = review.slope {
                        LabeledContent("体重趋势", value: (slope * 7).formatted(.number.precision(.fractionLength(2))) + " kg/周")
                    }
                    if let low = review.minimumCandidate, let high = review.maximumCandidate {
                        LabeledContent("偏差估算范围", value: energyText(low) + " 至 " + energyText(high))
                        Text("范围反映不同模型假设，不表示测量精度。")
                    }
                }.listRowBackground(AppTheme.cardBackground)
                if let days = review.inputDays, !days.isEmpty {
                    Section {
                        DisclosureGroup("冻结的每日依据") {
                            ForEach(days, id: \.date) { day in
                                NavigationLink(day.date.formatted(.dateTime.year().month().day())) {
                                    EnergyCalibrationDayDetail(day: day)
                                }.accessibilityIdentifier("energy-review-day")
                            }
                        }
                    }.listRowBackground(AppTheme.cardBackground)
                }
                Section {
                    Button(restored ? "已恢复" : "恢复到这次修正") {
                        do {
                            try EnergyControlStore.restore(key: entry.key, in: context)
                            restored = true
                        } catch { errorMessage = AppErrorMessage.message(for: error, operation: .save) }
                    }.disabled(restored).frame(minHeight: 44)
                }.listRowBackground(AppTheme.cardBackground)
            } else {
                Text("依据暂时无法读取，请返回后重试。")
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppTheme.warning)
            }
        }
        .font(.subheadline).foregroundStyle(AppTheme.accent)
        .scrollContentBackground(.hidden).appPageBackground()
        .navigationTitle("调整依据").navigationBarTitleDisplayMode(.inline)
        .task {
            guard entry.kindRaw == EnergyEvidenceKind.daily.rawValue else { return }
            do {
                var query: FetchDescriptor<EnergyEvidenceEntry>
                if let key = entry.predecessorKey {
                    query = .init(predicate: #Predicate { $0.key == key })
                } else {
                    let date = entry.date
                    query = .init(predicate: #Predicate { $0.kindRaw == "daily" && $0.date < date },
                                  sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.revision, order: .reverse)])
                }
                query.fetchLimit = 1
                if let row = try context.fetch(query).first {
                    previousFactor = try JSONDecoder().decode(EnergyDayCalculation.self, from: row.payload).factor
                }
            } catch { errorMessage = AppErrorMessage.message(for: error, operation: .load) }
        }
    }
}

private func energyText(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0))) + " kcal/天"
}
