import SwiftData
import SwiftUI

struct WidgetSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataSpaceController.self) private var dataSpace
    @Query(sort: \TrainingProgram.updatedAt, order: .reverse)
    private var programs: [TrainingProgram]
    @State private var preferences = SomaWidgetSharedStore.loadPreferences()

    private var activePrograms: [TrainingProgram] {
        programs.filter { $0.status == .active }
    }

    var body: some View {
        Form {
            Section {
                Picker("显示内容", selection: $preferences.displayMode) {
                    ForEach(SomaWidgetDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if showsFixedProgramPicker {
                    fixedProgramPicker
                }
            } header: {
                Text("主屏组件")
            } footer: {
                Text("自动模式会优先显示可继续的带练，其次是固定计划，再是本周训练节奏。")
            }

            Section("显示隐私") {
                Picker("信息等级", selection: $preferences.privacyLevel) {
                    ForEach(SomaWidgetPrivacyLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                Text(privacyDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("系统表面") {
                Label("锁屏、待机显示和灵动岛始终只显示私密状态。", systemImage: "lock.fill")
                Label("组件不会直接创建训练、完成组次或调用 AI。", systemImage: "checkmark.shield")
            }
        }
        .navigationTitle("主屏组件")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: normalizeFixedProgram)
        .onChange(of: preferences) {
            persist()
        }
        .onChange(of: programs.map(\.id)) {
            normalizeFixedProgram()
        }
    }

    private var privacyDescription: String {
        switch preferences.privacyLevel {
        case .privateMode:
            "只显示通用状态与进入训练/记录的入口。"
        case .overview:
            "可显示本周训练次数、已完成组数与距上次训练的相对天数。"
        case .trainingDetail:
            "仅主屏可显示计划名与组进度；不会显示体重、饮食、媒体或 AI 内容。"
        }
    }

    private var showsFixedProgramPicker: Bool {
        switch preferences.displayMode {
        case .automatic, .fixedPlan:
            true
        case .trainingRhythm, .quickCapture:
            false
        }
    }

    private var fixedProgramPicker: some View {
        Picker("固定计划", selection: fixedProgramSelection) {
            Text("不固定，按当前情境显示").tag("")
            ForEach(activePrograms) { program in
                Text(program.name).tag(program.id.uuidString)
            }
        }
    }

    private var fixedProgramSelection: Binding<String> {
        Binding(
            get: { preferences.fixedProgramID?.uuidString ?? "" },
            set: { rawValue in
                preferences.fixedProgramID = UUID(uuidString: rawValue)
            }
        )
    }

    private func normalizeFixedProgram() {
        guard let id = preferences.fixedProgramID,
              !activePrograms.contains(where: { $0.id == id })
        else {
            persist()
            return
        }
        preferences.fixedProgramID = nil
    }

    private func persist() {
        SomaWidgetSharedStore.savePreferences(preferences)
        SomaWidgetSnapshotProjector.refresh(
            in: modelContext,
            dataSpace: dataSpace.activeSpace
        )
    }
}
