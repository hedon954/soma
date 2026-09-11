import Foundation
import SwiftOpenAI

/// LLM 失败一旦越过 ReAct Loop，就只剩用户恢复或终止两种处置。
enum LLMFailureDisposition: Equatable {
    /// 失败已对用户可见，只能由用户显式重试。
    case waitForUser(message: String)
    /// 重试不会改变结果：进入终态并保留手动重试。
    case fail

    func message(fallback: String) -> String {
        switch self {
        case let .waitForUser(message): message
        case .fail: fallback
        }
    }
}

/// 归一化后的失败信号。把 SDK 与 `AIServiceError` 的差异挡在分类规则之外，
/// 让规则本身可以脱离网络与供应商单独测试。
struct LLMFailureSignal: Equatable {
    var isTransportFailure = false
    var isMissingConfiguration = false
    var isInvalidEndpoint = false
    var isUnsupportedRequest = false
    var httpStatusCode: Int?
    var responseDescription: String?
}

enum LLMOutageClassifier {
    /// 只允许在 ReAct Loop 内部短暂重试的瞬态状态码。
    private static let loopRetryableStatusCodes: Set<Int> = [
        408, 409, 425, 429
    ]

    static func disposition(for error: Error) -> LLMFailureDisposition {
        disposition(for: signal(for: error))
    }

    static func disposition(for signal: LLMFailureSignal) -> LLMFailureDisposition {
        if signal.isTransportFailure {
            return .waitForUser(message: "网络连接中断。请检查网络后手动重试。")
        }
        if signal.isMissingConfiguration {
            return .waitForUser(message: "还没有可用的 LLM 配置。请完成设置后手动重试。")
        }
        if signal.isInvalidEndpoint {
            return .waitForUser(message: "模型服务地址无效。请修改设置后手动重试。")
        }
        if signal.isUnsupportedRequest {
            return .fail
        }
        guard let status = signal.httpStatusCode else {
            return .fail
        }
        if status == 429 {
            if isQuotaExhaustion(signal.responseDescription) {
                return .waitForUser(
                    message: "模型服务额度已用尽。请处理额度后手动重试；Soma 不会自动继续。"
                )
            }
            return .waitForUser(message: "模型服务当前频率受限。请稍后手动重试。")
        }
        if status == 401 || status == 403 {
            return .waitForUser(message: "模型服务拒绝了当前凭据。请更新设置后手动重试。")
        }
        if loopRetryableStatusCodes.contains(status) || (500 ..< 600).contains(status) {
            return .waitForUser(message: "模型服务暂时不可用。请稍后手动重试。")
        }
        return .fail
    }

    /// 内部 ReAct 模型步骤可以在尚未产生任何可见增量时重试；一旦错误越过
    /// 这条边界，`disposition` 会把控制权交还给用户。
    static func isLoopRetryable(_ error: Error) -> Bool {
        if error is AgentStreamTimeoutError {
            return true
        }
        let signal = signal(for: error)
        if signal.isTransportFailure {
            return true
        }
        guard let status = signal.httpStatusCode else { return false }
        if status == 429, isQuotaExhaustion(signal.responseDescription) {
            return false
        }
        return loopRetryableStatusCodes.contains(status) || (500 ..< 600).contains(status)
    }

    static func signal(for error: Error) -> LLMFailureSignal {
        var signal = LLMFailureSignal()
        if let failure = error as? ModelRequestFailure {
            signal.httpStatusCode = failure.statusCode
            signal.responseDescription = failure.responseMessage
            return signal
        }

        if let serviceError = error as? AIServiceError {
            switch serviceError {
            case .missingAPIKey:
                signal.isMissingConfiguration = true
            case .invalidURL:
                signal.isInvalidEndpoint = true
            case .multimodalUnsupported:
                signal.isUnsupportedRequest = true
            case .invalidResponse,
                 .remote,
                 .imageGenerationUnsupported,
                 .imageGenerationBlocked,
                 .multimodalRequestFailed:
                break
            }
            return signal
        }

        if let apiError = error as? APIError {
            switch apiError {
            case .timeOutError:
                signal.isTransportFailure = true
            case let .responseUnsuccessful(description, statusCode):
                signal.httpStatusCode = statusCode
                signal.responseDescription = description
            case .requestFailed,
                 .invalidData,
                 .jsonDecodingFailure,
                 .dataCouldNotBeReadMissingData,
                 .bothDecodingStrategiesFailed:
                break
            }
            return signal
        }

        if error is URLError {
            signal.isTransportFailure = true
            return signal
        }

        let value = error as NSError
        if value.domain == NSURLErrorDomain {
            signal.isTransportFailure = true
        }
        return signal
    }

    private static func isQuotaExhaustion(_ description: String?) -> Bool {
        guard let normalized = description?.lowercased() else { return false }
        return [
            "insufficient_quota",
            "quota_exhausted",
            "billing",
            "payment_required",
            "credit balance",
            "余额不足",
            "欠费",
            "额度已用尽"
        ].contains { normalized.contains($0) }
    }
}
