import SwiftUI

enum AssistantFeedbackScroller {
    static func scrollAfterLayout(
        to target: AssistantFeedbackScrollTarget,
        using proxy: ScrollViewProxy
    ) {
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }
}

struct ConversationStarterSuggestion {
    let title: String
    let prompt: String
    var quickRecord: ExerciseInputSuggestion?

    init(
        title: String,
        prompt: String,
        quickRecord: ExerciseInputSuggestion? = nil
    ) {
        self.title = title
        self.prompt = prompt
        self.quickRecord = quickRecord
    }
}

enum ConversationStarterPolicy {
    static func shouldShow(for messages: [CoachMessage]) -> Bool {
        messages.isEmpty
    }

    static func customPrompts(from rawValue: String) -> [String] {
        let normalized = rawValue
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return Array(normalized.filter { seen.insert($0).inserted }.suffix(6))
    }

    static func adding(_ value: String, to prompts: [String]) -> [String] {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return prompts }
        return Array((prompts.filter { $0 != normalized } + [normalized]).suffix(6))
    }
}

struct ConversationStarter: View {
    let suggestions: [ConversationStarterSuggestion]
    let onSelect: (ConversationStarterSuggestion) -> Void
    @AppStorage("coach.customStarterPrompts") var customPromptsRaw = ""
    @State var customDraft = ""
    @State var customizationExpanded = false

    var customPrompts: [String] {
        ConversationStarterPolicy.customPrompts(from: customPromptsRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("像聊天一样描述训练、饮食或身体变化，Soma 会理解并记录。")
                .font(.title3.weight(.medium))
                .lineSpacing(3)
            VStack(spacing: 8) {
                ForEach(Array(allSuggestions.enumerated()), id: \.offset) { _, suggestion in
                    starter(suggestion)
                }
            }
            DisclosureGroup("自定义快捷语", isExpanded: $customizationExpanded) {
                HStack {
                    TextField("例如：记录晨起体重", text: $customDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("添加", action: addCustomPrompt)
                        .disabled(customDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(customPrompts, id: \.self) { prompt in
                    HStack {
                        Text(prompt).font(.caption).lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            removeCustomPrompt(prompt)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除快捷语 \(prompt)")
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    func addCustomPrompt() {
        let value = customDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        customPromptsRaw = ConversationStarterPolicy.adding(value, to: customPrompts)
            .joined(separator: "\n")
        customDraft = ""
    }

    func removeCustomPrompt(_ prompt: String) {
        customPromptsRaw = customPrompts.filter { $0 != prompt }
            .joined(separator: "\n")
    }

    var allSuggestions: [ConversationStarterSuggestion] {
        suggestions + customPrompts.map {
            ConversationStarterSuggestion(title: $0, prompt: $0)
        }
    }

    func starter(_ suggestion: ConversationStarterSuggestion) -> some View {
        Button {
            onSelect(suggestion)
        } label: {
            Text(suggestion.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .somaCardSurface(radius: 14)
        }
        .buttonStyle(.plain)
    }
}
