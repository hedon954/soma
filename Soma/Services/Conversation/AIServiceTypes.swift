import Foundation
import SwiftOpenAI

typealias AIRequestLoader = (URLRequest) async throws -> (Data, URLResponse)
typealias AgentStreamLoader = (
    ChatCompletionParameters,
    AIProvider,
    String,
    String
) async throws -> AsyncThrowingStream<ChatCompletionChunkObject, Error>
typealias AgentRetrySleeper = @Sendable (TimeInterval) async throws -> Void

enum AIServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case remote(String)
    case missingAPIKey(String)
    case imageGenerationUnsupported(String)
    case imageGenerationBlocked
    case multimodalUnsupported(provider: String, model: String)
    case multimodalRequestFailed(provider: String, model: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "模型服务地址无效"
        case .invalidResponse: "模型返回了无法识别的响应"
        case let .remote(message): message
        case let .missingAPIKey(provider): "请先在设置中保存 \(provider) 的 API Key"
        case let .imageGenerationUnsupported(provider):
            "\(provider) 尚未配置兼容的图片生成模型，请先在 AI 设置中填写图片生成模型 ID。"
        case .imageGenerationBlocked:
            "这次图片生成没有通过安全检查。请调整动作名称或肌群描述后重试。"
        case let .multimodalUnsupported(provider, model):
            "\(provider) 的 \(model) 不支持图片或视频分析。请切换到支持视觉的模型，文字对话仍可继续使用。"
        case let .multimodalRequestFailed(provider, model, reason):
            "\(provider) 的 \(model) 没能处理这次图片或视频：\(reason)"
        }
    }
}

struct AgentStreamOutcome {
    var passage = ""
    var reasoning = ""
    var toolCalls: [AgentStreamingToolCall] = []
    var usage: ChatUsage?
    var firstDeltaAt: Date?
    var projectionSeconds: TimeInterval = 0
    var requestAttempt = 1
    var mediaMode: AgentMediaMode = .text
    var fallbackReason: String?
    var ttftBudgetMilliseconds = 0
}

/// 流式中断时保留已产出的文本，让失败 Span 仍能解释这一步做到哪里。
enum StreamingFailure: Error {
    case interrupted(
        Error,
        passage: String,
        reasoning: String,
        receivedMeaningfulDelta: Bool
    )
}

struct AgentToolLoopState {
    var messages: [ChatCompletionParameters.Message]
    var tools: [ChatCompletionParameters.Tool]
    /// PRD 033：本次调用真正交给模型的工具名，也是恢复时要还原的曝光集合。
    /// `ChatCompletionParameters.Tool` 读不回名字，所以在组装时一并保存，供 Trace
    /// metadata、诊断日志与 checkpoint 使用。
    var exposedToolNames: [String] = []
    var observations: [AgentObservation] = []
    var executedMutations = Set<String>()
    var executedReads: [String: AgentToolResult] = [:]
}
