import SwiftUI

struct FixedAgentContractView: View {
    var body: some View {
        ScrollView {
            MarkdownText(ReActAgentPrompt.fixedContract)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("固定安全契约")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// PRD 030：内置 Skill、本地 Skill 与最多 6 个快捷入口共享同一注册表。
struct AgentSkillsListView: View {
    @State private var customizedSkills = Set<AgentSkill>()
    @State private var customSkills: [AgentCustomSkill] = []
    @State private var quickSkillIDs: [String] = []
    @State private var editingCustomSkill: AgentCustomSkill?
    @State private var confirmsResetAll = false

    var body: some View {
        Form {
            Section {
                ForEach(AgentSkill.allCases) { skill in
                    NavigationLink {
                        AgentSkillEditor(skill: skill)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(skill.title)
                                    .font(.headline)
                                Spacer()
                                Text(customizedSkills.contains(skill) ? "已自定义" : "默认")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(customizedSkills.contains(skill) ? AppTheme.tint : .secondary)
                            }
                            Text(skill.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } footer: {
                Text("系统提示词只披露 name、description 和 when_to_use；选中快捷 Skill 时首轮直接注入全文。")
            }

            Section {
                ForEach(customSkills) { skill in
                    Button {
                        editingCustomSkill = skill
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.name)
                                .foregroundStyle(.primary)
                            Text(skill.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .onDelete(perform: deleteCustomSkills)
                Button("新建 Skill", systemImage: "plus") {
                    editingCustomSkill = AgentCustomSkill(
                        id: "custom_\(UUID().uuidString.prefix(8).lowercased())",
                        name: "新 Skill",
                        description: "",
                        whenToUse: "",
                        content: "# 执行规则\n",
                        toolGroupIDs: []
                    )
                }
            } header: {
                Text("自定义 Skills")
            } footer: {
                Text("自定义 Skill 只能获得 App 白名单工具组，不能声明代码或任意工具。")
            }

            Section {
                ForEach(quickSkillIDs, id: \.self) { id in
                    if let skill = AgentSkillRegistry.descriptor(id: id) {
                        Label(skill.title, systemImage: "line.3.horizontal")
                    }
                }
                .onMove(perform: moveQuickSkills)
            } header: {
                Text("输入框快捷按钮")
            } footer: {
                Text("最多显示 6 个；在自定义 Skill 编辑页可加入或移出快捷按钮。")
            }

            Section {
                Button("全部恢复默认 Skills", systemImage: "arrow.counterclockwise", role: .destructive) {
                    confirmsResetAll = true
                }
            }
        }
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear(perform: reload)
        .sheet(item: $editingCustomSkill, onDismiss: reload) { skill in
            NavigationStack {
                AgentCustomSkillEditor(skill: skill)
            }
        }
        .alert("恢复全部默认 Skills？", isPresented: $confirmsResetAll) {
            Button("恢复默认", role: .destructive) {
                AgentSkill.allCases.forEach { $0.reset() }
                customizedSkills = []
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("你保存的全部自定义 Skill 内容都会被移除。")
        }
    }

    private func reload() {
        customizedSkills = Set(AgentSkill.allCases.filter { $0.isCustomized() })
        customSkills = AgentSkillRegistry.customSkills()
        quickSkillIDs = AgentSkillRegistry.quickSkillIDs()
    }

    private func deleteCustomSkills(at offsets: IndexSet) {
        for offset in offsets {
            AgentSkillRegistry.delete(id: customSkills[offset].id)
        }
        reload()
    }

    private func moveQuickSkills(from offsets: IndexSet, to destination: Int) {
        quickSkillIDs.move(fromOffsets: offsets, toOffset: destination)
        AgentSkillRegistry.setQuickSkillIDs(quickSkillIDs)
    }
}

enum MarkdownEditorMode: String, CaseIterable, Identifiable {
    case edit = "编辑"
    case preview = "预览"

    var id: String {
        rawValue
    }
}

struct ReActPromptEditor: View {
    let section: ReActPromptSection
    @State private var text: String
    @State private var savedText: String
    @State private var mode: MarkdownEditorMode = .edit
    @State private var confirmsReset = false

    init(section: ReActPromptSection) {
        self.section = section
        let initial = section.text()
        _text = State(initialValue: initial)
        _savedText = State(initialValue: initial)
    }

    var body: some View {
        Form {
            Section {
                Picker("显示方式", selection: $mode) {
                    ForEach(MarkdownEditorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section {
                if mode == .edit {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 360)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    MarkdownText(text)
                        .frame(minHeight: 360, alignment: .topLeading)
                        .padding(.vertical, 6)
                }
            } header: {
                Text(section.title)
            } footer: {
                Text(section.summary)
            }
            Section {
                Button("恢复这一段的默认值", systemImage: "arrow.counterclockwise") {
                    confirmsReset = true
                }
                .disabled(!section.isCustomized() && text == section.defaultText)
            }
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isDirty {
                    Button("保存", action: save)
                        .disabled(normalizedText.isEmpty)
                }
            }
        }
        .alert("恢复默认提示词？", isPresented: $confirmsReset) {
            Button("恢复默认", role: .destructive) {
                section.reset()
                text = section.defaultText
                savedText = section.defaultText
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("“\(section.title)”的自定义内容会被移除。")
        }
    }

    private var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDirty: Bool {
        normalizedText != savedText
    }

    private func save() {
        section.save(text)
        let persisted = section.text()
        text = persisted
        savedText = persisted
    }
}
