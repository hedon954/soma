import Foundation

/// ReAct 循环门面：用户可配置的步骤上限、活动超时，以及循环错误。
///
/// 各段唯一所有者：
/// - 循环本体：`AIService+ReActLoop`
/// - 无可见增量重试：`AgentStepRetryPolicy`
/// - 原生 tool_calls 流式累积：`AgentStreamingToolCall` / `AgentStreamWorker`
/// - 会话滚动压缩：`ConversationCompactionMiddleware`
enum ReActAgentPreference {
    static let maxStepsKey = "agent.react.maxSteps"
    static let textRuntimeTimeoutMinutesKey = "agent.react.textRuntimeTimeoutMinutes"
    static let imageRuntimeTimeoutMinutesKey = "agent.react.imageRuntimeTimeoutMinutes"
    static let videoRuntimeTimeoutMinutesKey = "agent.react.videoRuntimeTimeoutMinutes"
    private static let legacyRuntimeTimeoutMinutesKey = "agent.react.runtimeTimeoutMinutes"
    static let defaultMaxSteps = 100
    static let minimumMaxSteps = 1
    static let maximumMaxSteps = 500
    static let minimumRuntimeTimeoutMinutes = 3
    static let maximumRuntimeTimeoutMinutes = 60
    static let defaultTextRuntimeTimeoutMinutes = 3
    static let defaultImageRuntimeTimeoutMinutes = 5
    static let defaultVideoRuntimeTimeoutMinutes = 10

    static func maxSteps(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.object(forKey: maxStepsKey) as? Int
        let raw = stored ?? defaultMaxSteps
        return min(maximumMaxSteps, max(minimumMaxSteps, raw))
    }

    static func setMaxSteps(_ value: Int, defaults: UserDefaults = .standard) {
        defaults.set(
            min(maximumMaxSteps, max(minimumMaxSteps, value)),
            forKey: maxStepsKey
        )
    }

    static func textRuntimeTimeoutMinutes(defaults: UserDefaults = .standard) -> Int {
        timeoutMinutes(
            key: textRuntimeTimeoutMinutesKey,
            defaultValue: defaultTextRuntimeTimeoutMinutes,
            defaults: defaults
        )
    }

    static func imageRuntimeTimeoutMinutes(defaults: UserDefaults = .standard) -> Int {
        timeoutMinutes(
            key: imageRuntimeTimeoutMinutesKey,
            defaultValue: defaultImageRuntimeTimeoutMinutes,
            defaults: defaults
        )
    }

    static func videoRuntimeTimeoutMinutes(defaults: UserDefaults = .standard) -> Int {
        timeoutMinutes(
            key: videoRuntimeTimeoutMinutesKey,
            defaultValue: defaultVideoRuntimeTimeoutMinutes,
            defaults: defaults
        )
    }

    static func setRuntimeTimeoutMinutes(
        text: Int,
        image: Int,
        video: Int,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(clampedTimeout(text), forKey: textRuntimeTimeoutMinutesKey)
        defaults.set(clampedTimeout(image), forKey: imageRuntimeTimeoutMinutesKey)
        defaults.set(clampedTimeout(video), forKey: videoRuntimeTimeoutMinutesKey)
        defaults.removeObject(forKey: legacyRuntimeTimeoutMinutesKey)
    }

    static func migrateLegacyRuntimeTimeoutIfNeeded(
        defaults: UserDefaults = .standard
    ) {
        guard let legacy = defaults.object(forKey: legacyRuntimeTimeoutMinutesKey) as? Int,
              legacy > 0
        else { return }
        let migrated = clampedTimeout(legacy)
        if defaults.object(forKey: textRuntimeTimeoutMinutesKey) == nil {
            defaults.set(migrated, forKey: textRuntimeTimeoutMinutesKey)
        }
        if defaults.object(forKey: imageRuntimeTimeoutMinutesKey) == nil {
            defaults.set(migrated, forKey: imageRuntimeTimeoutMinutesKey)
        }
        if defaults.object(forKey: videoRuntimeTimeoutMinutesKey) == nil {
            defaults.set(migrated, forKey: videoRuntimeTimeoutMinutesKey)
        }
        defaults.removeObject(forKey: legacyRuntimeTimeoutMinutesKey)
    }

    static func deadlinePolicy(
        _ policy: AgentStreamDeadlinePolicy,
        defaults: UserDefaults = .standard
    ) -> AgentStreamDeadlinePolicy {
        var result = policy
        result.textLoopTotal = TimeInterval(textRuntimeTimeoutMinutes(defaults: defaults) * 60)
        result.imageLoopTotal = TimeInterval(imageRuntimeTimeoutMinutes(defaults: defaults) * 60)
        result.videoLoopTotal = TimeInterval(videoRuntimeTimeoutMinutes(defaults: defaults) * 60)
        return result
    }

    private static func timeoutMinutes(
        key: String,
        defaultValue: Int,
        defaults: UserDefaults
    ) -> Int {
        if let stored = defaults.object(forKey: key) as? Int {
            return clampedTimeout(stored)
        }
        if let legacy = defaults.object(forKey: legacyRuntimeTimeoutMinutesKey) as? Int,
           legacy > 0
        {
            return clampedTimeout(legacy)
        }
        return defaultValue
    }

    private static func clampedTimeout(_ value: Int) -> Int {
        min(maximumRuntimeTimeoutMinutes, max(minimumRuntimeTimeoutMinutes, value))
    }
}

enum ReActAgentError: LocalizedError {
    case invalidToolCall(String)
    case emptyResponse
    case stepLimit(maxSteps: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidToolCall(message):
            "模型发出了无效工具调用：\(message)"
        case .emptyResponse:
            "模型没有返回文字或工具调用，请重试或切换模型"
        case let .stepLimit(maxSteps):
            "Agent 在 \(maxSteps) 步内没有完成任务，请简化描述后重试，或在高级设置中提高步骤上限"
        }
    }
}

enum AgentFinalAnswerRecoveryPrompt {
    static let text = "请现在只输出面向用户的最终答复：直接给结论、必要依据和下一步，不要输出分析草稿或自我对话。"
}

/// Some compatible models occasionally place their internal scratchpad in
/// `content` instead of a reasoning field. Only classify text when several
/// strong self-directed planning markers co-occur; one conversational phrase
/// is never enough to hide a legitimate answer.
enum AgentInternalDraftClassifier {
    private static let highConfidencePrefixes = [
        "用户问了", "用户的问题是", "先分析用户", "分析用户的", "我们需要回答",
        "we need answer", "we need to answer", "need answer", "analyze the user"
    ]
    private static let markers = [
        "让我核实", "让我确认", "让我检查", "让我退一步", "让我组织", "让我整理",
        "我不应", "我需要先", "接下来我", "正确的做法是", "最终回复应该",
        "let me verify", "let me check", "let me step back", "i should not",
        "i need to inspect", "final answer should"
    ]

    static func isLikelyInternalDraft(_ text: String) -> Bool {
        let normalized = normalized(text)
        guard normalized.count >= 60 else { return false }
        if highConfidencePrefixes.contains(where: normalized.hasPrefix) {
            return true
        }
        return markerScore(in: normalized) >= 3
            || markerScore(in: normalized) >= 2
            && containsMetaAnswerLanguage(normalized)
    }

    static func isLikelyInternalDraftPrefix(_ text: String) -> Bool {
        let normalized = normalized(text)
        if highConfidencePrefixes.contains(where: normalized.hasPrefix) {
            return true
        }
        guard normalized.count >= 48 else { return false }
        return markerScore(in: normalized) >= 2
            && containsMetaAnswerLanguage(normalized)
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func markerScore(in normalized: String) -> Int {
        markers.reduce(into: 0) { score, marker in
            if normalized.contains(marker) {
                score += 1
            }
        }
    }

    private static func containsMetaAnswerLanguage(_ normalized: String) -> Bool {
        [
            "最终回复", "最终答复", "回复应该", "组织回复", "回答用户",
            "final answer", "respond to the user", "answer the user"
        ].contains(where: normalized.contains)
    }
}

/// 兼容端点偶尔把 scratchpad 错放到 `content`。先只缓冲一个很短的前缀：
/// 有协议级 reasoning 时立即确认 content 是正文；强内部草稿前缀改投 reasoning；
/// 其余正文达到阈值后一次性放行，之后保持严格增量。
struct AgentProvisionalContentGate {
    enum Destination: Equatable {
        case undecided
        case visible
        case reasoning
    }

    struct Projection: Equatable {
        var visible = ""
        var reasoning = ""
    }

    static let decisionCharacterCount = 96

    private(set) var destination = Destination.undecided
    private var pending = ""

    mutating func append(
        _ delta: String,
        hasProtocolReasoning: Bool
    ) -> Projection {
        guard !delta.isEmpty else { return Projection() }
        switch destination {
        case .visible:
            return Projection(visible: delta)
        case .reasoning:
            return Projection(reasoning: delta)
        case .undecided:
            pending += delta
            if hasProtocolReasoning {
                return resolve(.visible)
            }
            if AgentInternalDraftClassifier.isLikelyInternalDraftPrefix(pending) {
                return resolve(.reasoning)
            }
            if pending.count >= Self.decisionCharacterCount {
                return resolve(.visible)
            }
            return Projection()
        }
    }

    mutating func finish() -> Projection {
        guard destination == .undecided else { return Projection() }
        let target: Destination = AgentInternalDraftClassifier
            .isLikelyInternalDraft(pending)
            ? .reasoning
            : .visible
        return resolve(target)
    }

    private mutating func resolve(_ target: Destination) -> Projection {
        destination = target
        defer { pending = "" }
        return switch target {
        case .visible:
            Projection(visible: pending)
        case .reasoning:
            Projection(reasoning: pending)
        case .undecided:
            Projection()
        }
    }
}
