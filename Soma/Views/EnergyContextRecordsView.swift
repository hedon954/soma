import SwiftData
import SwiftUI

struct EnergyContextRecordsView: View {
    @Environment(\.modelContext) private var context
    @State private var rows: [EnergyContextDTO] = []
    @State private var hasMore = false
    @State private var errorMessage: String?
    @State private var currentLifestyle: EnergyContextDTO?

    var body: some View {
        List {
            if let currentLifestyle {
                NavigationLink("当前生活情况") { EnergyContextEditor(entry: currentLifestyle) }
                    .listRowBackground(AppTheme.cardBackground)
            }
            if rows.isEmpty {
                Text("还没有生活或完整性确认。可回到能量依据，向教练说明工作、通勤和家务。")
            }
            ForEach(rows, id: \.key) { row in
                NavigationLink {
                    EnergyContextEditor(entry: row)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.date.formatted(.dateTime.year().month().day()))
                        Text(row.lifestyleData != nil ? "生活情况与记录确认" : "当日记录完整性").font(.footnote)
                    }
                }.swipeActions {
                    Button("删除", role: .destructive) {
                        do {
                            try EnergyContextStore.delete(key: row.key, in: context)
                            load(reset: true)
                        } catch { errorMessage = AppErrorMessage.message(for: error, operation: .save) }
                    }
                }.listRowBackground(AppTheme.cardBackground)
            }
            if hasMore {
                Button("更早的确认") { load(reset: false) }.frame(minHeight: 44)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppTheme.warning)
            }
        }
        .font(.subheadline).foregroundStyle(AppTheme.accent)
        .scrollContentBackground(.hidden).appPageBackground()
        .navigationTitle("生活与记录确认").navigationBarTitleDisplayMode(.inline)
        .onAppear { load(reset: true) }
    }

    private func load(reset: Bool) {
        do {
            let now = Date.now
            var lifestyle = FetchDescriptor<EnergyContextEntry>(predicate: #Predicate { $0.lifestyleData != nil && $0.date <= now },
                                                                sortBy: [SortDescriptor(\.date, order: .reverse)])
            lifestyle.fetchLimit = 1
            currentLifestyle = try context.fetch(lifestyle).first.map(EnergyContextDTO.init)
            var query: FetchDescriptor<EnergyContextEntry>
            if !reset, let last = rows.last {
                let date = last.date, key = last.key
                query = .init(predicate: #Predicate {
                    ($0.lifestyleData != nil || $0.confirmationData != nil) && ($0.date < date || ($0.date == date && $0.key > key))
                })
            } else {
                query = .init(predicate: #Predicate { $0.lifestyleData != nil || $0.confirmationData != nil })
            }
            query.sortBy = [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.key)]
            query.fetchLimit = 50
            let page = try context.fetch(query).map(EnergyContextDTO.init)
            rows = reset ? page : rows + page
            hasMore = page.count == 50
            errorMessage = nil
        } catch { errorMessage = AppErrorMessage.message(for: error, operation: .load) }
    }
}

private struct EnergyContextEditor: View {
    let entry: EnergyContextDTO
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var life: EnergyLifestyleFacts?
    @State private var flags: EnergyDayConfirmation?
    @State private var workHours = ""
    @State private var workDays = ""
    @State private var walkingMinutes = ""
    @State private var houseworkMinutes = ""
    @State private var originalLife: EnergyLifestyleFacts?
    @State private var originalFlags: EnergyDayConfirmation?
    @State private var loaded = false
    @State private var reconfirmFood = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            LabeledContent("生效日期", value: entry.date.formatted(.dateTime.year().month().day()))
                .listRowBackground(AppTheme.cardBackground)
            if life != nil {
                Section("明确生活事实") {
                    Picker("工作主要", selection: Binding(get: { life?.workPosture }, set: { life?.workPosture = $0 })) {
                        Text("未记录").tag(EnergyLifestyleFacts.WorkPosture?.none)
                        Text("坐着").tag(Optional(EnergyLifestyleFacts.WorkPosture.sitting))
                        Text("站着").tag(Optional(EnergyLifestyleFacts.WorkPosture.standing))
                        Text("走动").tag(Optional(EnergyLifestyleFacts.WorkPosture.walking))
                    }
                    numeric("每工作日工时", text: $workHours)
                    numeric("每周工作天数", text: $workDays)
                    TextField("通勤方式", text: Binding(get: { life?.commutingDescription ?? "" }, set: { life?.commutingDescription = $0.isEmpty ? nil : $0 }))
                        .accessibilityIdentifier("通勤方式")
                    numeric("每工作日通勤步行分钟", text: $walkingMinutes)
                    TextField("家务情况", text: Binding(get: { life?.houseworkDescription ?? "" }, set: { life?.houseworkDescription = $0.isEmpty ? nil : $0 }))
                        .accessibilityIdentifier("家务情况")
                    numeric("平均每日家务分钟", text: $houseworkMinutes)
                }.listRowBackground(AppTheme.cardBackground)
            }
            if flags != nil {
                Section("当日完整性") {
                    confirmation("饮食", value: Binding(get: { flags?.foodComplete }, set: { flags?.foodComplete = $0; reconfirmFood = $0 == true }))
                    if flags?.foodComplete == true {
                        Button("重新确认饮食已记全") { reconfirmFood = true }
                            .frame(minHeight: 44)
                        Text("新增、修改或删除饮食后，需要重新确认完整性。").font(.footnote)
                    }
                    confirmation("训练", value: Binding(get: { flags?.trainingComplete }, set: { flags?.trainingComplete = $0 }))
                    confirmation("携带/佩戴计步设备", value: Binding(get: { flags?.walkingCoverageComplete }, set: { flags?.walkingCoverageComplete = $0 }))
                    Picker("体液变化疑问", selection: Binding(get: { flags?.fluidChangeConcern }, set: { flags?.fluidChangeConcern = $0 })) {
                        Text("未知").tag(Bool?.none)
                        Text("有疑问").tag(Optional(true))
                        Text("未发现疑问").tag(Optional(false))
                    }
                }.listRowBackground(AppTheme.cardBackground)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppTheme.warning).listRowBackground(AppTheme.cardBackground)
            }
        }
        .foregroundStyle(AppTheme.accent).scrollContentBackground(.hidden).appPageBackground()
        .labeledContentStyle(EnergyEvidenceLabelStyle())
        .navigationTitle("编辑已记录事实").navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            do {
                life = try entry.lifestyleData.map { try JSONDecoder().decode(EnergyLifestyleFacts.self, from: $0) }
                flags = try entry.confirmationData.map { try JSONDecoder().decode(EnergyDayConfirmation.self, from: $0) }
                workHours = life?.workHours.map { String($0) } ?? ""
                workDays = life?.workDaysPerWeek.map { String($0) } ?? ""
                walkingMinutes = life?.commutingWalkMinutes.map { String($0) } ?? ""
                houseworkMinutes = life?.houseworkMinutes.map { String($0) } ?? ""
                originalLife = life
                originalFlags = flags
                loaded = true
            } catch { errorMessage = AppErrorMessage.message(for: error, operation: .load) }
        }
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
        }
    }

    private var hasChanges: Bool {
        guard loaded else { return false }
        return reconfirmFood || life != originalLife || flags != originalFlags
            || workHours != (originalLife?.workHours.map { String($0) } ?? "")
            || workDays != (originalLife?.workDaysPerWeek.map { String($0) } ?? "")
            || walkingMinutes != (originalLife?.commutingWalkMinutes.map { String($0) } ?? "")
            || houseworkMinutes != (originalLife?.houseworkMinutes.map { String($0) } ?? "")
    }

    @ViewBuilder
    private func numeric(_ label: String, text: Binding<String>) -> some View {
        let input = TextField("未知", text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = $0 }))
            .keyboardType(.decimalPad).accessibilityIdentifier(label).accessibilityLabel(label)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).fixedSize(horizontal: false, vertical: true)
                input.accessibilityLabel(label)
            }
        } else {
            LabeledContent {
                input.multilineTextAlignment(.trailing).frame(maxWidth: 90)
            } label: {
                Text(label).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func confirmation(_ title: String, value: Binding<Bool?>) -> some View {
        Picker(title, selection: value) {
            Text("未知").tag(Bool?.none)
            Text("已确认完整").tag(Optional(true))
            Text("明确有缺项").tag(Optional(false))
        }
    }

    private func save() {
        do {
            func number(_ text: String) throws -> Double? {
                guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite else { throw EnergyCalculationError.invalidInput }
                return value
            }
            if life != nil {
                life?.workHours = try number(workHours)
                if let days = try number(workDays) {
                    guard days.rounded() == days, (0 ... 7).contains(days) else { throw EnergyCalculationError.invalidInput }
                    life?.workDaysPerWeek = Int(days)
                } else {
                    life?.workDaysPerWeek = nil
                }
                life?.commutingWalkMinutes = try number(walkingMinutes)
                life?.houseworkMinutes = try number(houseworkMinutes)
            }
            try EnergyContextStore.replace(key: entry.key, lifestyle: life, confirmation: flags, reconfirmFood: reconfirmFood, in: context)
            dismiss()
        } catch is EnergyCalculationError {
            errorMessage = "请检查数字和时长：每周最多 7 天，已知时段不能超过一天；未知请留空。"
        } catch { errorMessage = AppErrorMessage.message(for: error, operation: .save) }
    }
}
