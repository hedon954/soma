import SwiftUI

struct CoachUserQuestionsView: View {
    let request: AgentUserQuestionRequest
    var isEnabled = true
    var onSubmit: (String, String?, String?) throws -> Bool
    @State private var drafts: [String: String] = [:]
    @State private var failure: String?

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
                        HStack(alignment: .bottom, spacing: 4) {
                            TextField("补充你的情况", text: Binding(
                                get: { drafts[question.id] ?? "" },
                                set: { drafts[question.id] = $0 }
                            ), prompt: Text("补充你的情况").foregroundStyle(AppTheme.accent.opacity(0.7)), axis: .vertical)
                                .font(.subheadline.weight(.light))
                                .foregroundStyle(AppTheme.accent)
                                .lineLimit(1 ... 4)
                                .padding(.leading, 12)
                                .padding(.vertical, 12)
                                .accessibilityLabel("\(question.question)，自定义回答")
                                .accessibilityIdentifier("question-input-\(question.id)")
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
                        .background(AppTheme.insetBackground, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
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

    private func options(for question: AgentUserQuestion) -> some View {
        ForEach(question.options) { option in
            Button {
                submit(question.id, option.id, nil)
            } label: {
                Text(option.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .frame(minHeight: AppTheme.minimumTapTarget)
                    .background(AppTheme.insetBackground, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("question-option-\(question.id)-\(option.id)")
            .accessibilityHint("发送这句话")
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
