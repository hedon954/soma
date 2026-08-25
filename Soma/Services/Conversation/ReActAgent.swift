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
    static let runtimeTimeoutMinutesKey = "agent.react.runtimeTimeoutMinutes"
    static let defaultMaxSteps = 100
    static let minimumMaxSteps = 1
    static let maximumMaxSteps = 500
    static let automaticRuntimeTimeoutMinutes = 0
    static let minimumRuntimeTimeoutMinutes = 3
    static let maximumRuntimeTimeoutMinutes = 60

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

    /// `nil` 表示沿用文字/图片/视频 3/5/10 分钟的媒体自适应预算。
    static func runtimeTimeoutMinutes(defaults: UserDefaults = .standard) -> Int? {
        guard let stored = defaults.object(forKey: runtimeTimeoutMinutesKey) as? Int,
              stored != automaticRuntimeTimeoutMinutes
        else {
            return nil
        }
        return min(
            maximumRuntimeTimeoutMinutes,
            max(minimumRuntimeTimeoutMinutes, stored)
        )
    }

    static func setRuntimeTimeoutMinutes(
        _ value: Int?,
        defaults: UserDefaults = .standard
    ) {
        guard let value else {
            defaults.removeObject(forKey: runtimeTimeoutMinutesKey)
            return
        }
        defaults.set(
            min(
                maximumRuntimeTimeoutMinutes,
                max(minimumRuntimeTimeoutMinutes, value)
            ),
            forKey: runtimeTimeoutMinutesKey
        )
    }

    static func deadlinePolicy(
        _ policy: AgentStreamDeadlinePolicy,
        defaults: UserDefaults = .standard
    ) -> AgentStreamDeadlinePolicy {
        guard let minutes = runtimeTimeoutMinutes(defaults: defaults) else {
            return policy
        }
        var result = policy
        let seconds = TimeInterval(minutes * 60)
        result.textLoopTotal = seconds
        result.imageLoopTotal = seconds
        result.videoLoopTotal = seconds
        return result
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
