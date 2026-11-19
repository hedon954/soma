#if DEBUG
    import SwiftData
    import SwiftUI

    struct WorkoutWeightCorrectionView: View {
        @Environment(\.modelContext) private var context
        @State private var plan: WorkoutWeightCorrectionPlan?
        @State private var state: WorkoutWeightCorrection.State = .before
        @State private var confirms = false
        @State private var error: String?

        static var enabled: Bool {
            #if targetEnvironment(simulator)
                false
            #else
                ProcessInfo.processInfo.environment["SOMA_ENABLE_WEIGHT_CORRECTION"] == "1"
            #endif
        }

        var body: some View {
            List {
                if let plan, !plan.changes.isEmpty {
                    Section {
                        if state == .conflict {
                            Text("记录有变化，需要逐项复核。")
                        } else {
                            Button(state == .after ? "撤销本次校正" : "应用重量校正") { confirms = true }
                        }
                        if plan.conflicts > 0 {
                            Text("\(plan.conflicts) 条记录的实际组与投影不一致，待核对。")
                        }
                    } header: {
                        Text("\(plan.changes.count) 个重量值")
                    }

                    ForEach(plan.changes) { change in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(change.name).font(.headline)
                            Text(change.date.formatted(.dateTime.year().month().day()))
                            let group = change.group.map { "第 \($0) 组" } ?? "旧记录"
                            let side = change.side == .left ? " · 左侧" : change.side == .right ? " · 右侧" : ""
                            Text("\(group)\(side) · \(change.previous.formatted()) → \(change.corrected.formatted()) kg")
                                .monospacedDigit()
                            if let difference = change.volumeDifference {
                                Text("容量 \(difference.formatted()) kg").monospacedDigit()
                            }
                        }
                    }
                } else if let plan {
                    Text(plan.conflicts > 0 ? "有 \(plan.conflicts) 条记录待核对。" : "没有匹配的训练记录。")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("重量校正")
            .navigationBarTitleDisplayMode(.inline)
            .task { load() }
            .confirmationDialog(state == .after ? "撤销本次校正？" : "应用预览中的重量校正？", isPresented: $confirms, titleVisibility: .visible) {
                Button(state == .after ? "撤销校正" : "确认校正") { commit() }
                Button("取消", role: .cancel) {}
            }
            .alert("重量校正未完成", isPresented: Binding(get: { error != nil }, set: {
                if !$0 {
                    error = nil
                }
            })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }

        private var journalURL: URL? {
            context.container.configurations.first { $0.name == "PersonalData" && !$0.isStoredInMemoryOnly }?
                .url.deletingLastPathComponent().appending(path: "workout-weight-correction-082.json")
        }

        private func load() {
            do {
                guard let url = journalURL else { return }
                let loaded = try WorkoutWeightCorrection.loadPlan(in: context, journalURL: url)
                plan = loaded.plan
                state = loaded.state
            } catch {
                self.error = AppErrorMessage.message(for: error, operation: .load)
            }
        }

        private func commit() {
            guard let plan, let url = journalURL else { return }
            do {
                try WorkoutWeightCorrection.commit(plan, undo: state == .after, in: context, journalURL: url)
                load()
            } catch {
                load()
                self.error = AppErrorMessage.message(for: error, operation: .save)
            }
        }
    }
#endif
