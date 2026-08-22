import Foundation
import SwiftData
import SwiftOpenAI

struct ConversationSessionTitleInput: Equatable, Sendable {
    private static let maximumUserLength = 800
    private static let maximumAssistantLength = 1200

    var userText: String
    var assistantText: String

    init(userText: String, assistantText: String) {
        self.userText = Self.bounded(
            userText,
            maximumLength: Self.maximumUserLength
        )
        self.assistantText = Self.bounded(
            assistantText,
            maximumLength: Self.maximumAssistantLength
        )
    }

    var prompt: String {
        """
        用户：
        \(userText)

        教练：
        \(assistantText)

        请为这段对话生成一个简短标题。只输出标题，不要引号、Markdown、句号或解释。
        中文控制在 6 到 18 个字；英文控制在 3 到 8 个单词。只概括已有主题，不补充事实。
        """
    }

    private static func bounded(
        _ value: String,
        maximumLength: Int
    ) -> String {
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(normalized.prefix(maximumLength))
    }
}

struct GeneratedConversationTitle: Equatable, Sendable {
    var title: String
    var tier: AIModelTier
}

@MainActor
enum ConversationSessionTitleService {
    static func firstSuccessfulInput(
        sessionID: UUID,
        messages: [CoachMessage]
    ) -> ConversationSessionTitleInput? {
        let sessionMessages = messages
            .filter { $0.sessionID == sessionID }
            .sorted { $0.date < $1.date }
        for user in sessionMessages where !user.isFromCoach {
            guard let turnID = user.turnID else { continue }
            let successfulResponses = sessionMessages.filter {
                $0.isFromCoach
                    && $0.turnID == turnID
                    && $0.agentStatus == .succeeded
            }
            guard let assistant = successfulResponses.max(by: {
                $0.attemptNumber < $1.attemptNumber
            }) else { continue }
            return ConversationSessionTitleInput(
                userText: displayText(for: user),
                assistantText: assistant.text
            )
        }
        return nil
    }

    static func fallbackText(
        sessionID: UUID,
        messages: [CoachMessage]
    ) -> String? {
        messages
            .filter { $0.sessionID == sessionID && !$0.isFromCoach }
            .min(by: { $0.date < $1.date })
            .map(displayText(for:))
    }

    static func generate(
        input: ConversationSessionTitleInput,
        ai: AIService
    ) async -> GeneratedConversationTitle? {
        if isConfigured(.small, ai: ai),
           let title = try? await request(input: input, tier: .small, ai: ai),
           let normalized = normalizeGeneratedTitle(title)
        {
            return GeneratedConversationTitle(title: normalized, tier: .small)
        }
        if isConfigured(.standard, ai: ai),
           let title = try? await request(input: input, tier: .standard, ai: ai),
           let normalized = normalizeGeneratedTitle(title)
        {
            return GeneratedConversationTitle(title: normalized, tier: .standard)
        }
        return nil
    }

    nonisolated static func normalizeGeneratedTitle(_ value: String) -> String? {
        guard let firstLine = value
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else {
            return nil
        }

        var normalized = firstLine
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["标题：", "标题:"] where normalized.hasPrefix(prefix) {
            normalized.removeFirst(prefix.count)
            break
        }
        let quotes = CharacterSet(charactersIn: "\"'“”‘’《》")
        let trailingPunctuation = CharacterSet(charactersIn: "。！？!?；;，,、：:")
        normalized = normalized
            .trimmingCharacters(in: .whitespacesAndNewlines.union(quotes))
            .trimmingCharacters(in: trailingPunctuation)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(quotes))
        guard let result = ConversationSession.normalizedTitle(
            normalized,
            maximumLength: ConversationSession.maximumGeneratedTitleLength
        ), result != ConversationSession.defaultTitle
        else {
            return nil
        }
        return result
    }

    private static func isConfigured(
        _ tier: AIModelTier,
        ai: AIService
    ) -> Bool {
        guard ai.isTierEnabled(tier) else { return false }
        let provider = ai.provider(for: tier)
        return !ai.apiKey(for: provider, tier: tier)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !ai.baseURL(for: provider, tier: tier)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !ai.model(for: provider, tier: tier)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func request(
        input: ConversationSessionTitleInput,
        tier: AIModelTier,
        ai: AIService
    ) async throws -> String {
        let provider = ai.provider(for: tier)
        let model = ai.model(for: provider, tier: tier)
        AgentDiagnostics.modelRequest(
            step: 0,
            provider: provider.displayName,
            model: model,
            tier: tier.title,
            skillID: nil,
            toolNames: [],
            messageCount: 2
        )
        return try await ai.completeConversationTitle(
            prompt: input.prompt,
            tier: tier
        )
    }

    private static func displayText(for message: CoachMessage) -> String {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty else { return text }
        let imageCount = message.mediaAttachments.count { $0.kind == .image }
        let videoCount = message.mediaAttachments.count { $0.kind == .video }
        let parts = [
            imageCount > 0 ? "\(imageCount) 张图片" : nil,
            videoCount > 0 ? "\(videoCount) 个视频" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "媒体对话" : parts.joined(separator: "和")
    }
}

extension AIService {
    func completeConversationTitle(
        prompt: String,
        tier: AIModelTier
    ) async throws -> String {
        let provider = provider(for: tier)
        let route = AIModelRoute(
            tier: tier,
            provider: provider,
            baseURL: baseURL(for: provider, tier: tier),
            model: model(for: provider, tier: tier),
            reason: "会话标题生成"
        )
        let resolved = try resolvedRoute(
            requested: route,
            text: prompt,
            hasMedia: false,
            hasVideo: false
        )
        var messages = [
            ChatCompletionParameters.Message(
                role: .system,
                content: .text(
                    "你是 Soma 的会话标题生成器。只概括输入，只输出一行短标题，不回答用户。"
                )
            ),
            ChatCompletionParameters.Message(role: .user, content: .text(prompt))
        ]
        let outcome = try await consumeAgentStepWithRetry(
            messages: &messages,
            request: AgentStreamStepRequest(
                tools: [],
                model: resolved.route.model,
                provider: resolved.route.provider,
                images: [],
                videos: [],
                hasVideo: false,
                step: 0,
                route: resolved.route,
                apiKey: resolved.apiKey,
                userPrompt: prompt,
                textItemID: UUID()
            ),
            videoFrameFallback: nil,
            trace: nil
        )
        let text = outcome.passage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ReActAgentError.emptyResponse }
        return text
    }
}
