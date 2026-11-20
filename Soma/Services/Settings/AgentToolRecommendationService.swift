import Foundation

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
        AppErrorMessage.message(for: error, operation: .model)
    }

    static func prompt(
        shortcutTitle: String,
        skill: AgentSkillDescriptor
    ) -> String {
        SomaPrompt.text("shortcut_tool_recommendation_user_prompt", [
            "shortcut_title": shortcutTitle,
            "skill_title": skill.title,
            "skill_description": skill.summary,
            "when_to_use": skill.whenToUse,
            "skill_markdown": skill.markdown,
            "tools": catalog
        ])
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
        let text = try await ai.completeTextPrompt(
            system: SomaPrompt.text("shortcut_tool_recommendation_system_prompt"),
            user: prompt,
            reason: "快捷按钮工具推荐",
            tier: tier
        )
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
