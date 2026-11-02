import SwiftData
import SwiftUI

struct EnergyTrainingLinksView: View {
    let calculation: EnergyDayCalculation
    @Environment(\.modelContext) private var context
    @State private var links: [EnergyTrainingAssociation] = []
    @State private var errorMessage: String?

    private var local: [EnergyTrainingEvent] {
        calculation.input.training.filter { $0.id.hasPrefix("soma") }
    }

    private var health: [EnergyTrainingEvent] {
        calculation.input.training.filter { $0.id.hasPrefix("health:") }
    }

    var body: some View {
        List {
            Section {
                Text("只在确定是同一场训练时关联。关联后优先采用健康记录中口径明确的活动消耗，Soma 的动作记录保留。")
                    .font(.footnote).foregroundStyle(AppTheme.accent)
            }
            if local.isEmpty || health.isEmpty {
                Text("该日没有可配对的 Soma 与 Apple 健康训练。").foregroundStyle(AppTheme.accent)
            }
            ForEach(local) { event in
                Section {
                    Text(description(event))
                    Picker("同一场健康训练", selection: Binding(get: {
                        links.first { $0.localID == event.id }?.healthID ?? ""
                    }, set: { save(localID: event.id, healthID: $0.isEmpty ? nil : $0) })) {
                        Text("未关联").tag("")
                        ForEach(health) { candidate in
                            Text(description(candidate)).tag(candidate.id)
                                .disabled(links.contains { $0.healthID == candidate.id && $0.localID != event.id })
                        }
                    }
                    .accessibilityIdentifier("energy-training-association")
                }.listRowBackground(AppTheme.cardBackground)
            }
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden).appPageBackground()
        .navigationTitle("同场训练关联").navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .alert("暂时无法保存", isPresented: Binding(get: { errorMessage != nil }, set: {
            if !$0 {
                errorMessage = nil
            }
        })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func description(_ event: EnergyTrainingEvent) -> String {
        let time = event.start.map { $0.formatted(.dateTime.hour().minute()) } ?? "时段待确认"
        let energy = event.netEnergy(resting: calculation.input.resting).map { " · \($0.formatted(.number.precision(.fractionLength(0)))) kcal" } ?? " · 热量待确认"
        return "\(event.source) · \(event.activityType ?? "训练") · \(time)\(energy)"
    }

    private func reload() {
        do {
            links = try EnergyTrainingAssociationStore.load(on: calculation.input.date, in: context).links
        } catch { errorMessage = AppErrorMessage.message(for: error, operation: .load) }
    }

    private func save(localID: String, healthID: String?) {
        do {
            links = try EnergyTrainingAssociationStore.set(localID: localID, healthID: healthID, on: calculation.input.date, in: context).links
        } catch { errorMessage = "这条健康训练可能已关联，或记录暂不可用。已有记录保留，请重试。" }
    }
}
