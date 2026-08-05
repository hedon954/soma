import Foundation
import SwiftOpenAI

/// LLM 失效的三种处置。ADR 0045 规定只有这三条路径，不允许在调用点临时判断。
enum LLMFailureDisposition: Equatable {
    /// 传输层抖动：沿用既有 `waitingForNetwork` 与短退避。
    case retryNetwork
    /// 可由“等待供应商恢复”或“用户改配置”修复：落入 `staged`。
    case stage(message: String)
    /// 重试不会改变结果：进入终态并保留手动重试。
    case fail
}

/// 归一化后的失败信号。把 SDK 与 `AIServiceError` 的差异挡在分类规则之外，
/// 让规则本身可以脱离网络与供应商单独测试。
struct LLMFailureSignal: Equatable {
    var isTransportFailure = false
    var isMissingConfiguration = false
    var isInvalidEndpoint = false
    var isUnsupportedRequest = false
    var httpStatusCode: Int?
}

enum LLMOutageClassifier {
    /// 供应商侧“现在不行、待会儿可能行”的状态码。401/403 归入这里是因为
    /// 用户换一个有效 Key 就能恢复，属于配置问题而不是请求问题。
    private static let recoverableStatusCodes: Set<Int> = [
        401, 403, 408, 409, 425, 429
    ]

    static func disposition(for error: Error) -> LLMFailureDisposition {
        disposition(for: signal(for: error))
    }

    static func disposition(for signal: LLMFailureSignal) -> LLMFailureDisposition {
        if signal.isTransportFailure {
            return .retryNetwork
        }
        if signal.isMissingConfiguration {
            return .stage(message: "还没有可用的 LLM 配置，消息已暂存。")
        }
        if signal.isInvalidEndpoint {
            return .stage(message: "模型服务地址无效，消息已暂存。")
        }
        if signal.isUnsupportedRequest {
            return .fail
        }
        guard let status = signal.httpStatusCode else {
            return .fail
        }
        if status == 429 {
            return .stage(message: "模型服务额度或频率受限，消息已暂存。")
        }
        if status == 401 || status == 403 {
            return .stage(message: "模型服务拒绝了当前凭据，消息已暂存。")
        }
        if recoverableStatusCodes.contains(status) || (500 ..< 600).contains(status) {
            return .stage(message: "模型服务暂时不可用，消息已暂存。")
        }
        return .fail
    }

    static func signal(for error: Error) -> LLMFailureSignal {
        var signal = LLMFailureSignal()

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
            case let .responseUnsuccessful(_, statusCode):
                signal.httpStatusCode = statusCode
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

    /// 暂存退避：指数增长、上限 5 分钟。等待用户改配置的场景不设退避。
    /// 指数先夹到 16 只是为了让计算保持有限，真正的上限由 `maximumStagingRetryDelay` 决定。
    static let maximumStagingRetryDelay: TimeInterval = 300

    static func stagingRetryDelay(attemptCount: Int) -> TimeInterval {
        let exponent = min(max(attemptCount, 0), 16)
        return min(pow(2, Double(exponent)), maximumStagingRetryDelay)
    }
}
