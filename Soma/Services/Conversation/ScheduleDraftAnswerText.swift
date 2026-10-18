import Foundation

enum ScheduleDraftAnswerText {
    static let opening = "帮我排一份训练计划。先看我已有的课程和最近训练，只问会改变这轮安排的问题；确认后再给计划草稿，先不要保存。"
    static let answerPrefix = "关于这份训练计划："

    struct Item: Equatable, Sendable {
        var question: String
        var selections: [String]
        var supplement: String
    }

    static func requiresSelection(userText: String) -> Bool {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == opening || trimmed.hasPrefix(answerPrefix)
    }

    static func compose(_ items: [Item]) -> String? {
        let blocks = items.compactMap { item -> String? in
            let selections = item.selections.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            let supplement = item.supplement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selections.isEmpty || !supplement.isEmpty else { return nil }
            var lines = ["【\(item.question)】"]
            lines.append(contentsOf: selections)
            if !supplement.isEmpty {
                lines.append("我补充：\(supplement)")
            }
            return lines.joined(separator: "\n")
        }
        guard !blocks.isEmpty else { return nil }
        return ([answerPrefix] + blocks).joined(separator: "\n\n")
    }

    static func toggle(
        mode: AgentQuestionSelection,
        selected: Set<String>,
        optionID: String
    ) -> Set<String> {
        var next = selected
        switch mode {
        case .single:
            next = next.contains(optionID) ? [] : [optionID]
        case .multiple:
            if next.contains(optionID) {
                next.remove(optionID)
            } else {
                next.insert(optionID)
            }
        }
        return next
    }
}
