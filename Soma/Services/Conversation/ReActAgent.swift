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
