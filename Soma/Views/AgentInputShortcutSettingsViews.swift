import SwiftUI

/// PRD 033：输入框快捷按钮的完整 CRUD。按钮决定一次发送走哪个 Skill、能用哪些工具，
/// 以及是否出现在聊天输入区。
struct AgentInputShortcutListView: View {
    @State private var shortcuts: [AgentInputShortcut] = []
    @State private var editing: AgentInputShortcut?
    @State private var confirmsReset = false

    private var visibleCount: Int {
        shortcuts.filter(\.isVisible).count
    }

    var body: some View {
        Form {
            Section {
                ForEach(shortcuts) { shortcut in
                    Button {
                        editing = shortcut
                    } label: {
                        row(shortcut)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
                .onMove(perform: move)
                Button("新建快捷按钮", systemImage: "plus") {
                    editing = AgentInputShortcut(title: "新快捷按钮")
                }
            } header: {
                Text("快捷按钮")
            } footer: {
                Text(
                    "聊天输入区最多显示 \(AgentInputShortcutStore.maximumVisibleCount) 个，当前显示 \(visibleCount) 个。关闭显示后配置仍会保留，需要时再打开。"
                )
            }

            Section {
                Button(
                    "恢复默认快捷按钮",
                    systemImage: "arrow.counterclockwise",
                    role: .destructive
                ) {
                    confirmsReset = true
                }
            } footer: {
                Text("恢复后只保留饮食分析、训练记录、近期分析三个默认按钮。")
            }
        }
        .navigationTitle("输入框快捷按钮")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .task {
            await refreshAfterTransition()
        }
        .sheet(item: $editing, onDismiss: {
            Task { await refreshAfterTransition() }
        }) { shortcut in
            NavigationStack {
                AgentInputShortcutEditor(shortcut: shortcut)
            }
        }
        .alert("恢复默认快捷按钮？", isPresented: $confirmsReset) {
            Button("恢复默认", role: .destructive) {
                AgentInputShortcutStore.resetToDefaults()
                shortcuts = AgentInputShortcutStore.defaultShortcuts
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("你新增或修改过的快捷按钮都会被移除。")
        }
    }

    private func row(_ shortcut: AgentInputShortcut) -> some View {
        HStack(spacing: 12) {
            Image(systemName: shortcut.iconSystemName)
                .font(.body)
                .foregroundStyle(shortcut.isVisible ? AppTheme.tint : .secondary)
                // 辅助字号下图标会比固定宽度更宽，用 minWidth 保证对齐又不压到文字。
                .frame(minWidth: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(shortcut.title)
                    .foregroundStyle(.primary)
                Text(subtitle(shortcut))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Toggle("显示", isOn: visibilityBinding(shortcut))
                .appToggleStyle()
                .labelsHidden()
                .accessibilityLabel("在聊天输入区显示\(shortcut.title)")
        }
        .padding(.vertical, 4)
    }

    private func subtitle(_ shortcut: AgentInputShortcut) -> String {
        let skill = shortcut.skillID
            .flatMap { AgentSkillRegistry.descriptor(id: $0) }
            .map(\.title) ?? "未绑定 Skill"
        let toolCount = shortcut.normalizedToolNames.count
        let toolText = toolCount == AgentToolExposurePolicy.orderedTools.count
            ? "全部工具"
            : "\(toolCount) 个工具"
        return "\(skill) · \(toolText)"
    }

    private func visibilityBinding(
        _ shortcut: AgentInputShortcut
    ) -> Binding<Bool> {
        Binding(
            get: { shortcut.isVisible },
            set: { isVisible in
                guard let index = shortcuts.firstIndex(where: {
                    $0.id == shortcut.id
                }) else { return }
                shortcuts[index].isVisible = isVisible
                persistCurrentShortcuts()
            }
        )
    }

    @MainActor
    private func refreshAfterTransition() async {
        await Task.yield()
        let loaded = await Task.detached(priority: .userInitiated) {
            AgentInputShortcutStore.shortcuts()
        }.value
        guard !Task.isCancelled else { return }
        shortcuts = loaded
    }

    private func persistCurrentShortcuts() {
        shortcuts = shortcuts.enumerated().map { index, shortcut in
            var normalized = shortcut
            normalized.order = index
            normalized.toolNames = shortcut.normalizedToolNames
            return normalized
        }
        AgentInputShortcutStore.replaceAll(shortcuts)
    }

    private func delete(at offsets: IndexSet) {
        shortcuts.remove(atOffsets: offsets)
        persistCurrentShortcuts()
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        shortcuts.move(fromOffsets: offsets, toOffset: destination)
        persistCurrentShortcuts()
    }
}
