import Foundation
import SwiftOpenAI

enum AgentModelMessageRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
}

struct AgentModelMessage: Codable, Equatable, Sendable {
    var role: AgentModelMessageRole
    var text: String
    var mediaIDs: [String] = []
}

struct AgentModelSkillSnapshot: Codable, Equatable, Sendable {
    var id: String
    var name: String? = nil
    var description: String? = nil
    var whenToUse: String? = nil
    var content: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, content
        case whenToUse = "when_to_use"
    }
}

struct AgentModelTool: Codable, Equatable, Sendable {
    var name: AgentToolName
    var schemaVersion: Int
    var definition: RemoteJSONValue
}

struct AgentModelDeadlinePolicy: Codable, Equatable, Sendable {
    var textTTFT: TimeInterval
    var imageTTFT: TimeInterval
    var directVideoTTFT: TimeInterval
    var textLoopTotal: TimeInterval
    var imageLoopTotal: TimeInterval
    var videoLoopTotal: TimeInterval

    init(_ policy: AgentStreamDeadlinePolicy) {
        textTTFT = policy.textTTFT
        imageTTFT = policy.imageTTFT
        directVideoTTFT = policy.directVideoTTFT
        textLoopTotal = policy.textLoopTotal
        imageLoopTotal = policy.imageLoopTotal
        videoLoopTotal = policy.videoLoopTotal
    }
}

struct AgentModelRuntimeOptions: Codable, Equatable, Sendable {
    var toolChoice = "auto"
    var parallelToolCalls = true
    var maxSteps: Int
    var deadlines: AgentModelDeadlinePolicy
}

/// 本地与远程 Provider 共用的版本化模型输入。Server 只能消费本结构，不能重新拼 Prompt。
struct AgentModelInputEnvelope: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion = currentSchemaVersion
    var messages: [AgentModelMessage]
    var skills: [AgentModelSkillSnapshot]
    var tools: [AgentModelTool]
    var activeTools: [AgentToolName]
    var selectedSkillID: String? = nil
    var runtime: AgentModelRuntimeOptions
}

enum AgentModelMediaPayload: Equatable, @unchecked Sendable {
    case image(id: String, data: Data)
    case video(id: String, input: AgentVideoInput)

    var id: String {
        switch self {
        case let .image(id, _), let .video(id, _): id
        }
    }
}

struct PreparedAgentModelInput: Equatable, @unchecked Sendable {
    var envelope: AgentModelInputEnvelope
    var media: [AgentModelMediaPayload]
}

enum AgentModelInputBuilder {
    static func build(
        systemPrompt: String,
        history: [AgentConversationExchange],
        userPrompt: String,
        currentImages: [Data],
        currentVideos: [AgentVideoInput],
        skills: [AgentModelSkillSnapshot],
        tools: [AgentToolName],
        selectedSkillID: String? = nil,
        maxSteps: Int,
        deadlinePolicy: AgentStreamDeadlinePolicy
    ) throws -> PreparedAgentModelInput {
        var messages = [AgentModelMessage(role: .system, text: systemPrompt)]
        var media: [AgentModelMediaPayload] = []

        for (exchangeIndex, exchange) in history.enumerated() {
            let mediaIDs = exchange.images.indices.map {
                "history-\(exchangeIndex)-image-\($0)"
            }
            media.append(contentsOf: zip(mediaIDs, exchange.images).map {
                .image(id: $0.0, data: $0.1)
            })
            messages.append(AgentModelMessage(
                role: .user,
                text: ReActAgentPrompt.historicalUser(
                    text: exchange.userText,
                    imageCount: exchange.images.count,
                    imageAttachmentCount: exchange.imageAttachmentCount,
                    videoAttachmentCount: exchange.videoAttachmentCount,
                    canReferenceImagesAsRecentGymTurn: exchangeIndex == history.count - 1
                        && exchange.imageAttachmentCount > 0
                ),
                mediaIDs: mediaIDs
            ))
            guard let assistant = exchange.assistantText?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !assistant.isEmpty
            else {
                continue
            }
            messages.append(AgentModelMessage(role: .assistant, text: assistant))
        }

        let currentImageIDs = currentImages.indices.map { "current-image-\($0)" }
        let currentVideoIDs = currentVideos.indices.map { "current-video-\($0)" }
        media.append(contentsOf: zip(currentImageIDs, currentImages).map {
            .image(id: $0.0, data: $0.1)
        })
        media.append(contentsOf: zip(currentVideoIDs, currentVideos).map {
            .video(id: $0.0, input: $0.1)
        })
        messages.append(AgentModelMessage(
            role: .user,
            text: userPrompt,
            mediaIDs: currentImageIDs + currentVideoIDs
        ))

        return try PreparedAgentModelInput(
            envelope: AgentModelInputEnvelope(
                messages: messages,
                skills: skills,
                tools: tools.map { name in
                    let data = try JSONEncoder().encode(name.chatTool)
                    return try AgentModelTool(
                        name: name,
                        schemaVersion: name.schemaVersion,
                        definition: JSONDecoder().decode(
                            RemoteJSONValue.self,
                            from: data
                        )
                    )
                },
                activeTools: tools,
                selectedSkillID: selectedSkillID,
                runtime: AgentModelRuntimeOptions(
                    maxSteps: maxSteps,
                    deadlines: AgentModelDeadlinePolicy(deadlinePolicy)
                )
            ),
            media: media
        )
    }
}

extension AgentSkill {
    static func snapshots(defaults: UserDefaults) -> [AgentModelSkillSnapshot] {
        AgentSkillRegistry.allDescriptors(defaults: defaults).map {
            AgentModelSkillSnapshot(
                id: $0.id,
                name: $0.title,
                description: $0.summary,
                whenToUse: $0.whenToUse,
                content: $0.markdown
            )
        }
    }
}

extension AIService {
    func chatMessages(
        from input: PreparedAgentModelInput
    ) -> [ChatCompletionParameters.Message] {
        let imagePairs: [(String, Data)] = input.media.compactMap {
            if case let .image(id, data) = $0 {
                return (id, data)
            }
            return nil
        }
        let imagesByID = Dictionary(uniqueKeysWithValues: imagePairs)
        return input.envelope.messages.map { message in
            let role: ChatCompletionParameters.Message.Role = switch message.role {
            case .system: .system
            case .user: .user
            case .assistant: .assistant
            }
            let images = message.mediaIDs.compactMap { imagesByID[$0] }
            return ChatCompletionParameters.Message(
                role: role,
                content: message.role == .user
                    ? agentUserContent(
                        prompt: message.text,
                        images: images,
                        maximumImageCount: images.count
                    )
                    : .text(message.text)
            )
        }
    }
}
