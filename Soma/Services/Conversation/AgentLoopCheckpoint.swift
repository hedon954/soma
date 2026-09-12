import Foundation
import SwiftOpenAI

/// ADR 0062：每个 LLM invoke / tool call 都是可恢复 step。
///
/// `toolBatches == nil` 代表旧版压缩检查点；新检查点保留原生 assistant.tool_calls
/// 与 role=tool 结果，恢复时不重新调用已经成功的模型或工具。
struct AgentLoopCheckpoint: Codable, Equatable, Sendable {
    var lastCompletedStep: Int
    var assistantPassages: [String]
    var observations: [AgentCheckpointObservation]
    /// ADR 0082：恢复时按工具名还原曝光集合。
    var exposedToolNames: [String]
    /// 在盘的旧 checkpoint 只记录了分组；解码后转换成工具名，不再写入新值。
    var legacyExposedGroups: [String]
    var nextModelStep: Int?
    var toolBatches: [AgentCheckpointToolBatch]?
    var extraConfigJSON: String? = nil
    var initialInput: AgentModelInputEnvelope? = nil
    var route: AIModelRoute? = nil
    var videoInputMode: AgentMediaMode? = nil

    init(
        lastCompletedStep: Int,
        assistantPassages: [String],
        observations: [AgentCheckpointObservation],
        exposedToolNames: [String],
        legacyExposedGroups: [String] = [],
        nextModelStep: Int? = nil,
        toolBatches: [AgentCheckpointToolBatch]? = nil
    ) {
        self.lastCompletedStep = lastCompletedStep
        self.assistantPassages = assistantPassages
        self.observations = observations
        self.exposedToolNames = exposedToolNames
        self.legacyExposedGroups = legacyExposedGroups
        self.nextModelStep = nextModelStep
        self.toolBatches = toolBatches
    }

    private enum CodingKeys: String, CodingKey {
        case lastCompletedStep
        case assistantPassages
        case observations
        case exposedToolNames
        case legacyExposedGroups = "exposedGroups"
        case nextModelStep
        case toolBatches
        case videoInputMode, initialInput, route, extraConfigJSON
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastCompletedStep = try container.decode(Int.self, forKey: .lastCompletedStep)
        assistantPassages = try container.decode(
            [String].self,
            forKey: .assistantPassages
        )
        observations = try container.decode(
            [AgentCheckpointObservation].self,
            forKey: .observations
        )
        exposedToolNames = try container.decodeIfPresent(
            [String].self,
            forKey: .exposedToolNames
        ) ?? []
        legacyExposedGroups = try container.decodeIfPresent(
            [String].self,
            forKey: .legacyExposedGroups
        ) ?? []
        extraConfigJSON = try container.decodeIfPresent(String.self, forKey: .extraConfigJSON)
        initialInput = try container.decodeIfPresent(AgentModelInputEnvelope.self, forKey: .initialInput)
        route = try container.decodeIfPresent(AIModelRoute.self, forKey: .route)
        videoInputMode = try container.decodeIfPresent(AgentMediaMode.self, forKey: .videoInputMode)
        nextModelStep = try container.decodeIfPresent(Int.self, forKey: .nextModelStep)
        toolBatches = try container.decodeIfPresent(
            [AgentCheckpointToolBatch].self,
            forKey: .toolBatches
        )
    }

    /// 恢复时的有效曝光集合：新 checkpoint 直接用工具名，旧 checkpoint 由分组展开。
    var restoredToolNames: [String] {
        if !exposedToolNames.isEmpty {
            return exposedToolNames
        }
        let groups = Set(legacyExposedGroups.compactMap(AgentToolGroup.init(rawValue:)))
        return groups.isEmpty
            ? []
            : AgentToolExposurePolicy.toolNames(for: groups)
    }

    static let empty = AgentLoopCheckpoint(
        lastCompletedStep: 0,
        assistantPassages: [],
        observations: [],
        exposedToolNames: []
    )
}

struct AgentCheckpointToolCall: Codable, Equatable, @unchecked Sendable {
    var id: String
    var argumentsJSON: String
    var action: AgentToolCall
    var preflightResult: AgentToolResult? = nil

    var native: ToolCall {
        ToolCall(
            id: id,
            function: FunctionCall(
                arguments: argumentsJSON,
                name: action.name.rawValue
            )
        )
    }
}

struct AgentCheckpointToolResult: Codable, Equatable, @unchecked Sendable {
    var step: Int
    var call: AgentCheckpointToolCall
    var result: AgentToolResult
}

struct AgentCheckpointToolBatch: Codable, Equatable, @unchecked Sendable {
    var modelStep: Int
    var modelOperationStep: Int
    var passage: String
    var reasoning: String? = nil
    var calls: [AgentCheckpointToolCall]
    var completedResults: [AgentCheckpointToolResult]

    var isComplete: Bool {
        completedResults.count == calls.count
    }
}

struct AgentCheckpointObservation: Codable, Equatable, Sendable {
    var step: Int
    var toolName: String
    var signature: String
    var observation: String
    var ok: Bool
    var recordTypeRaw: String?

    var recordType: ConversationIntent? {
        recordTypeRaw.flatMap(ConversationIntent.init(rawValue:))
    }

    init(step: Int, action: AgentToolCall, result: AgentToolResult) {
        self.step = step
        toolName = action.name.rawValue
        signature = action.signature
        observation = result.observation
        ok = result.ok
        recordTypeRaw = result.recordType?.rawValue
    }
}

struct AgentConversationExchange: Sendable {
    var turnID: UUID?
    var sentAt: Date?
    var trustedTime: TrustedTurnContext?
    var canonicalMessages: [AgentModelMessage]?
    var userText: String
    var assistantText: String?
    var images: [Data]
    var videos: [AgentVideoInput] = []
    var videoPreparationFailed = false
    var imageAttachmentCount: Int
    var videoAttachmentCount: Int

    var traceSummary: String {
        let user = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAssistant = assistantText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let assistant = if let trimmedAssistant, !trimmedAssistant.isEmpty {
            trimmedAssistant
        } else {
            "无"
        }
        return """
        [HISTORY USER]
        \(user.isEmpty ? "无文字" : user)
        原始附件：\(imageAttachmentCount) 张图片、\(videoAttachmentCount) 个视频；本次重新提供 \(images.count) 张图片、\(videos.count) 个完整视频。
        [HISTORY ASSISTANT]
        \(assistant)
        """
    }
}
