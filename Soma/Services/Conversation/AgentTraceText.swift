import Foundation

enum AgentTraceText {
    static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8)
        else {
            return "无法编码"
        }
        return text
    }

    static func jsonObject(_ value: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(
                  withJSONObject: value,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let text = String(data: data, encoding: .utf8)
        else {
            return "无法编码"
        }
        return text
    }

    static func modelInput(
        systemPrompt: String,
        history: [AgentConversationExchange] = [],
        userPrompt: String
    ) -> String {
        let historyText = history
            .map(\.traceSummary)
            .joined(separator: "\n\n")
        let historySection = historyText.isEmpty
            ? ""
            : "\n\n[RECENT SESSION HISTORY]\n\(historyText)"
        return """
        [SYSTEM]
        \(systemPrompt)
        \(historySection)
        [USER]
        \(userPrompt)
        """
    }
}
