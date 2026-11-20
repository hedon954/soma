import CryptoKit
import Foundation
import SwiftOpenAI

enum AgentPromptScene: String, Codable, Sendable {
    case coach
    case performanceReview
}

/// Frozen application configuration, stored inside the existing Job context JSON.
/// Never contains API keys or media bytes.
struct AgentPromptConfiguration: Codable, Equatable, Sendable {
    var systemPrompt: String
    var skills: [AgentModelSkillSnapshot]
    var tools: [AgentModelTool]
    var selectedSkillID: String?
    var coachPersona: String? = nil
    var scene: AgentPromptScene? = nil

    var forRemoteExecution: Self {
        var copy = self
        copy.tools.removeAll { $0.name.isAppDirectOnly }
        return copy
    }

    var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func capture(
        defaults: UserDefaults,
        selectedSkillID: String?,
        selectedShortcutID: String?,
        scene: AgentPromptScene = .coach
    ) throws -> Self {
        let shortcut = selectedShortcutID.flatMap { AgentInputShortcutStore.shortcut(id: $0, defaults: defaults) }
        let names: [AgentToolName] = scene == .performanceReview
            ? [.recordPerformanceAnalysis]
            : AgentToolExposurePolicy.tools(selectedShortcut: shortcut)
        return try Self(
            systemPrompt: scene == .performanceReview
                ? SomaPrompt.text("performance_review_system_prompt")
                : ReActAgentPrompt.system,
            skills: scene == .performanceReview ? [] : AgentSkill.snapshots(defaults: defaults, selectedSkillID: selectedSkillID),
            tools: names.map { name in
                let data = try JSONEncoder().encode(name.chatTool)
                return try AgentModelTool(name: name, schemaVersion: name.schemaVersion,
                                          definition: JSONDecoder().decode(RemoteJSONValue.self, from: data))
            },
            selectedSkillID: selectedSkillID,
            coachPersona: scene == .coach ? ReActPromptSection.role.text(in: defaults) : nil,
            scene: scene
        )
    }

    var nativeTools: [ChatCompletionParameters.Tool] {
        get throws {
            struct FrozenTool: Decodable {
                var type: String
                var function: ChatCompletionParameters.ChatFunction
            }
            return try tools.map {
                let frozen = try JSONDecoder().decode(FrozenTool.self, from: JSONEncoder().encode($0.definition))
                return ChatCompletionParameters.Tool(type: frozen.type, function: frozen.function)
            }
        }
    }
}
