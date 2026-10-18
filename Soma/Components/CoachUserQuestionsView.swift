import SwiftUI

struct CoachUserQuestionsView: View {
    let request: AgentUserQuestionRequest
    var isEnabled = true
    var onSubmit: (String, String?, String?) throws -> Bool
    var onCompose: (String) throws -> Bool = { _ in false }
    @State private var drafts: [String: String] = [:]
    @State private var selected: [String: Set<String>] = [:]
    @State private var failure: String?

    private var usesSelection: Bool {
        request.questions.allSatisfy { $0.selection != nil }
            && request.questions.contains { $0.selection != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(request.questions) { question in
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.question)
                        .font(.subheadline.weight(.light))
                        .foregroundStyle(AppTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    if !question.options.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            options(for: question)
                        }
                    }
                    if question.allowsCustomInput {
                        customField(for: question)
                    }
                }
            }
            if usesSelection {
                Button("发送", action: submitSelection)
                    .appPrimaryButtonStyle()
                    .disabled(composedText == nil)
                    .accessibilityIdentifier("question-compose-send")
            }
        }
        .disabled(!isEnabled)
        .alert("暂时无法发送", isPresented: Binding(get: { failure != nil }, set: {
            if !$0 {
                failure = nil
            }
        })) {
            Button("好", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private var composedText: String? {
        ScheduleDraftAnswerText.compose(request.questions.map { question in
            let chosen = question.options.filter {
                selected[question.id, default: []].contains($0.id)
            }.map(\.text)
            return ScheduleDraftAnswerText.Item(
                question: question.question,
                selections: chosen,
                supplement: drafts[question.id] ?? ""
            )
        })
    }

    private func customField(for question: AgentUserQuestion) -> some View {
        HStack(alignment: .bottom, spacing: 4) {
            TextField("自己写", text: Binding(
                get: { drafts[question.id] ?? "" },
                set: { drafts[question.id] = $0 }
            ), prompt: Text("自己写").foregroundStyle(AppTheme.accent.opacity(0.7)), axis: .vertical)
                .font(.subheadline.weight(.light))
                .foregroundStyle(AppTheme.accent)
                .lineLimit(1 ... 4)
                .padding(.leading, 12)
                .padding(.vertical, 12)
                .accessibilityLabel("\(question.question)，自己写")
                .accessibilityIdentifier("question-input-\(question.id)")
            if !usesSelection {
                Button {
                    submit(question.id, nil, drafts[question.id])
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: AppTheme.minimumTapTarget, height: AppTheme.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled((drafts[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("发送自定义回答")
                .accessibilityIdentifier("question-send-\(question.id)")
            }
        }
        .background(AppTheme.insetBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func options(for question: AgentUserQuestion) -> some View {
        ForEach(question.options) { option in
            let isSelected = selected[question.id, default: []].contains(option.id)
            Button {
                if let mode = question.selection {
                    selected[question.id] = ScheduleDraftAnswerText.toggle(
                        mode: mode,
                        selected: selected[question.id, default: []],
                        optionID: option.id
                    )
                } else {
                    submit(question.id, option.id, nil)
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if question.selection != nil {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                    }
                    Text(option.text)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.accent)
                .padding(12)
                .frame(minHeight: AppTheme.minimumTapTarget)
                .background(
                    isSelected ? AppTheme.accent : AppTheme.insetBackground,
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("question-option-\(question.id)-\(option.id)")
            .accessibilityLabel(option.text)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint(question.selection == nil ? "发送这句话" : (isSelected ? "取消选择" : "选择这个选项"))
        }
    }

    private func submitSelection() {
        guard let composedText else { return }
        do {
            if try onCompose(composedText) {
                drafts = [:]
                selected = [:]
            } else {
                failure = "回答未能保存，请重试。"
            }
        } catch {
            failure = AppErrorMessage.message(for: error, operation: .save)
        }
    }

    private func submit(_ question: String, _ option: String?, _ text: String?) {
        do {
            if try onSubmit(question, option, text) {
                drafts[question] = nil
            } else {
                failure = "回答未能保存，请重试。"
            }
        } catch {
            failure = AppErrorMessage.message(for: error, operation: .save)
        }
    }
}
