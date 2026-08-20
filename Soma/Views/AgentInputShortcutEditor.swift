import SwiftUI

/// PRD 033：一个快捷按钮 = 名称 + 图标 + 绑定 Skill + 工具白名单 + 是否显示。
/// 工具默认全选，用户可以按分组删减，也可以让小模型推荐后一键采纳。
struct AgentInputShortcutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AIService.self) private var ai

    private let shortcutID: String
    private let order: Int
    @State private var title: String
    @State private var iconSystemName: String
    @State private var skillID: String?
    @State private var selectedTools: Set<String>
    @State private var isVisible: Bool
    @State private var recommendation: AgentToolRecommendation?
    @State private var recommendationError: String?
    @State private var isRecommending = false

    init(shortcut: AgentInputShortcut) {
        shortcutID = shortcut.id
        order = shortcut.order
        _title = State(initialValue: shortcut.title)
        _iconSystemName = State(initialValue: shortcut.iconSystemName)
        _skillID = State(initialValue: shortcut.skillID)
        _selectedTools = State(initialValue: Set(shortcut.normalizedToolNames))
        _isVisible = State(initialValue: shortcut.isVisible)
    }

    private var skills: [AgentSkillDescriptor] {
        AgentSkillRegistry.allDescriptors()
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedTools.isEmpty
    }

    var body: some View {
        Form {
            Section("基础信息") {
                TextField("名称", text: $title)
                Picker("图标", selection: $iconSystemName) {
                    ForEach(AgentInputShortcut.iconChoices, id: \.self) { name in
                        // 图标本身就是选项，符号名对用户没有意义，不上屏。
                        Image(systemName: name)
                            .accessibilityLabel(AgentInputShortcut.iconLabel(name))
                            .tag(name)
                    }
                }
                Toggle("显示在聊天输入区", isOn: $isVisible)
            }

            Section {
                Picker("Skill", selection: $skillID) {
                    Text("不绑定").tag(String?.none)
                    ForEach(skills) { skill in
                        Text(skill.title).tag(String?.some(skill.id))
                    }
                }
            } header: {
                Text("绑定 Skill")
            } footer: {
                Text(skillFooter)
            }

            recommendationSection

            Section {
                HStack {
                    Button("全选") {
                        selectedTools = Set(AgentToolName.allToolNames)
                    }
                    Spacer()
                    Button("全不选") { selectedTools = [] }
                        .foregroundStyle(.red)
                }
                .font(.footnote.weight(.semibold))
                ForEach(AgentToolGroup.allCases, id: \.rawValue) { group in
                    toolGroupRow(group)
                }
            } header: {
                Text("工具权限（已选 \(selectedTools.count) 个）")
            } footer: {
                Text("发送时只把选中的工具交给模型。至少要选一个工具，否则模型无法完成写入。")
            }
        }
        .navigationTitle("快捷按钮")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(!isValid)
            }
        }
    }

    private var skillFooter: String {
        guard let skillID,
              let skill = skills.first(where: { $0.id == skillID })
        else {
            return "不绑定 Skill 时只按下面的工具权限收窄，不注入专业方法正文。"
        }
        return skill.summary
    }

    private var recommendationSection: some View {
        Section {
            Button {
                requestRecommendation()
            } label: {
                HStack {
                    Label("让 AI 推荐工具", systemImage: "wand.and.stars")
                    Spacer()
                    if isRecommending {
                        ProgressView()
                    }
                }
            }
            .disabled(isRecommending || skillID == nil)
            if let recommendation {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recommendation.reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(recommendationTitles(recommendation))
                        .font(.footnote.weight(.semibold))
                }
                Button("采纳这份推荐") {
                    selectedTools = Set(recommendation.toolNames)
                }
                .disabled(recommendation.toolNames.isEmpty)
            }
            if let recommendationError {
                Text(recommendationError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("AI 推荐")
        } footer: {
            Text("推荐只发送按钮名称、Skill 正文与工具目录，不发送任何身体数据；优先使用小模型。")
        }
    }

    @ViewBuilder
    private func toolGroupRow(_ group: AgentToolGroup) -> some View {
        let names = group.tools.map(\.rawValue)
        let allSelected = names.allSatisfy { selectedTools.contains($0) }
        DisclosureGroup {
            ForEach(group.tools, id: \.rawValue) { tool in
                Toggle(tool.displayTitle, isOn: toolBinding(tool.rawValue))
                    .font(.callout)
            }
        } label: {
            HStack {
                Text(group.title)
                Spacer()
                Button(allSelected ? "取消本组" : "选中本组") {
                    if allSelected {
                        names.forEach { selectedTools.remove($0) }
                    } else {
                        selectedTools.formUnion(names)
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.tint)
                Text("\(names.filter { selectedTools.contains($0) }.count)/\(names.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toolBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { selectedTools.contains(name) },
            set: { selected in
                if selected {
                    selectedTools.insert(name)
                } else {
                    selectedTools.remove(name)
                }
            }
        )
    }

    private func recommendationTitles(
        _ recommendation: AgentToolRecommendation
    ) -> String {
        AgentToolExposurePolicy.tools(names: recommendation.toolNames)
            .map(\.displayTitle)
            .joined(separator: "、")
    }

    private func requestRecommendation() {
        guard let skillID,
              let skill = skills.first(where: { $0.id == skillID })
        else { return }
        isRecommending = true
        recommendationError = nil
        Task {
            do {
                recommendation = try await AgentToolRecommendationService.recommend(
                    shortcutTitle: title,
                    skill: skill,
                    ai: ai
                )
            } catch {
                recommendation = nil
                recommendationError = AgentToolRecommendationService
                    .failureMessage(error)
            }
            isRecommending = false
        }
    }

    private func save() {
        AgentInputShortcutStore.save(AgentInputShortcut(
            id: shortcutID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            iconSystemName: iconSystemName,
            skillID: skillID,
            toolNames: AgentToolExposurePolicy.normalize(
                toolNames: Array(selectedTools)
            ),
            isVisible: isVisible,
            order: order
        ))
        dismiss()
    }
}
