import Foundation
import SwiftOpenAI

struct AgentToolRecommendation: Equatable, Sendable {
    /// 已按工具目录校验过的工具名，未知名称会被丢弃。
    var toolNames: [String]
    var reason: String
}

enum AgentToolRecommendationError: LocalizedError {
    case unusableResponse

    var errorDescription: String? {
        switch self {
        case .unusableResponse:
            "模型没有给出可用的工具清单。"
        }
    }
}

/// PRD 033：勾选 32 个工具对用户太重。这里让模型读 Skill 正文和工具目录，给出建议清单与理由，
/// 用户一键采纳。只发送按钮名称、Skill 正文和工具目录，不含任何身体数据。
enum AgentToolRecommendationService {
    @MainActor
    static func recommend(
        shortcutTitle: String,
        skill: AgentSkillDescriptor,
        ai: AIService
    ) async throws -> AgentToolRecommendation {
        let prompt = prompt(shortcutTitle: shortcutTitle, skill: skill)
        // 小模型优先；未启用或调用失败时回落标准档，不让推荐能力依赖可选配置。
        if let recommendation = try? await request(prompt: prompt, tier: .small, ai: ai) {
            return recommendation
        }
        return try await request(prompt: prompt, tier: .standard, ai: ai)
    }

    static func failureMessage(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return "推荐失败：\(error.localizedDescription)"
    }

    static func prompt(
        shortcutTitle: String,
        skill: AgentSkillDescriptor
    ) -> String {
        """
        快捷按钮名称：\(shortcutTitle)

        Skill 名称：\(skill.title)
        Skill 说明：\(skill.summary)
        使用时机：\(skill.whenToUse)

        Skill 正文：
        \(skill.markdown)

        可选工具目录（工具名=用途）：
        \(catalog)

        请选出这个快捷按钮真正需要的最小工具集合。
        只输出一个 JSON 对象，不要代码块、不要额外说明：
        {"tools":["工具名"],"reason":"一到两句中文理由"}
        规则：
        1. 工具名必须逐字来自上面的目录，不要发明新名字。
        2. 需要写入时必须同时包含对应的查询工具，例如更新训练要同时给出 list_workouts 与
           get_workout。
        3. 与这个按钮无关的领域一律不选；load_skill 总是要选。
        """
    }

    static func parse(_ text: String) -> AgentToolRecommendation? {
        guard let data = jsonObjectData(in: text),
              let root = try? JSONSerialization.jsonObject(with: data)
              as? [String: Any]
        else { return nil }
        let rawTools = (root["tools"] as? [Any])?.compactMap { $0 as? String } ?? []
        let names = AgentToolExposurePolicy.tools(names: rawTools).map(\.rawValue)
        guard !rawTools.isEmpty, !names.isEmpty else { return nil }
        let reason = (root["reason"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AgentToolRecommendation(
            toolNames: names,
            reason: reason.isEmpty ? "模型未给出理由。" : reason
        )
    }

    private static var catalog: String {
        AgentToolExposurePolicy.orderedTools
            .map { "- \($0.rawValue)=\($0.displayTitle)" }
            .joined(separator: "\n")
    }

    @MainActor
    private static func request(
        prompt: String,
        tier: AIModelTier,
        ai: AIService
    ) async throws -> AgentToolRecommendation {
        let text = try await ai.completeToolRecommendation(prompt: prompt, tier: tier)
        guard let recommendation = parse(text) else {
            throw AgentToolRecommendationError.unusableResponse
        }
        return recommendation
    }

    /// 模型偶尔会在 JSON 前后加解释文字，这里只截取第一个完整对象。
    private static func jsonObjectData(in text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end
        else { return nil }
        return String(text[start ... end]).data(using: .utf8)
    }
}

extension AIService {
    func completeToolRecommendation(
        prompt: String,
        tier: AIModelTier
    ) async throws -> String {
        let provider = provider(for: tier)
        let route = AIModelRoute(
            tier: tier,
            provider: provider,
            baseURL: baseURL(for: provider, tier: tier),
            model: model(for: provider, tier: tier),
            reason: "快捷按钮工具推荐"
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
                    "你是 Soma 的工具编排助手。只输出 JSON，不解释，不臆造工具名。"
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
