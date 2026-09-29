import Foundation
import SwiftOpenAI

enum AppErrorOperation {
    case general, model, load, save, delete, media, recording, speech
    case backup, restore, startup, configuration, feedback

    var recovery: String {
        switch self {
        case .model: "请重试或在设置的「LLM 配置」中更换模型；已保存的记录仍保留。"
        case .load: "请返回后重新打开；若仍失败，可在设置中发送反馈。"
        case .save: "请保留当前填写内容，检查后再保存。"
        case .delete: "请刷新列表确认当前状态，再重试删除。"
        case .media: "请重新选择可播放的视频或可打开的图片后重试。"
        case .recording: "请重试录像；训练仍可继续。"
        case .speech: "请检查系统语音与麦克风权限后重试，也可以继续键盘输入。"
        case .backup: "请检查备份文件夹与可用空间后重试。"
        case .restore: "请重新选择完整备份并确认密码后重试。"
        case .startup: "请重新打开 App；若仍失败，请保留现有数据，点击「导出诊断」后联系维护者。"
        case .configuration: "请检查填写的设置后重试。"
        case .feedback: "请保留反馈内容，稍后再试。"
        case .general: "请重试；若仍失败，可在设置中发送反馈。"
        }
    }

    var fallback: String {
        let cause = switch self {
        case .model: "模型未能完成这次请求，暂时无法确定具体原因。"
        case .load: "暂时无法读取这项内容。"
        case .save: "保存未完成，暂时无法确定具体原因。"
        case .delete: "删除未完成，暂时无法确定具体原因。"
        case .media: "暂时无法读取这项图片或视频。"
        case .recording: "录像未能完成，系统没有提供可确认的原因。"
        case .speech: "本地语音识别未能继续。"
        case .backup: "备份未完成。"
        case .restore: "备份恢复未完成。"
        case .startup: "本机数据暂时无法打开，已停止继续载入。"
        case .configuration: "设置未能生效。"
        case .feedback: "反馈暂时无法发送。"
        case .general: "这次操作未完成，暂时无法确定具体原因。"
        }
        return cause + recovery
    }
}

/// 用户呈现边界：保留可确认原因和恢复办法，不回显 SDK、服务商或持久化旧错误原文。
enum AppErrorMessage {
    static func message(for error: Error, operation: AppErrorOperation = .general) -> String {
        if case let StreamingFailure.interrupted(underlying, _, _, _) = error {
            return message(for: underlying, operation: operation)
        }
        if error is CancellationError {
            return "操作已取消，需要时可以重新开始。"
        }
        if let remote = error as? RemoteAgentError {
            switch remote {
            case let .server(code, text): return remoteMessage(code: code, detail: text)
            case .toolRejected: return "这次操作未通过记录检查。请核对内容后重试；已经保存的记录仍保留。"
            default: return withRecovery(remote.errorDescription ?? "", operation: operation)
            }
        }
        if let service = error as? AIServiceError {
            switch service {
            case let .remote(raw): return message(from: raw, operation: .model)
            case let .multimodalRequestFailed(_, _, reason): return message(from: reason, operation: .model)
            case .multimodalUnsupported:
                return "当前模型不支持图片或视频。请在设置的「LLM 配置」中更换支持图片的模型后重试；原附件仍保留。"
            case .missingAPIKey:
                return "还没有设置可用的模型密钥。请在设置的「LLM 配置」中保存 API Key 后重试。"
            default: return withRecovery(service.errorDescription ?? "", operation: .configuration)
            }
        }
        let signal = LLMOutageClassifier.signal(for: error)
        if let classified = modelMessage(status: signal.httpStatusCode, response: signal.responseDescription ?? "") {
            return classified
        }
        if error is APIError {
            return AppErrorOperation.model.fallback
        }
        if let business = businessMessage(for: error, operation: operation) {
            return business
        }
        let systemDomain = (error as NSError).domain
        if systemDomain == NSURLErrorDomain || systemDomain == NSCocoaErrorDomain || systemDomain == NSPOSIXErrorDomain {
            return systemMessage(error, operation: operation)
        }
        if let localized = (error as? LocalizedError)?.errorDescription, isSafeLocalized(localized) {
            return withRecovery(localized, operation: operation)
        }
        return systemMessage(error, operation: operation)
    }

    private static func businessMessage(for error: Error, operation: AppErrorOperation) -> String? {
        if let plan = error as? TrainingPlanError {
            switch plan {
            case .missingExercise: return "课程中的一个动作已不存在或已归档。请替换该动作后再开始训练。"
            default: return message(from: plan.errorDescription ?? "", operation: operation)
            }
        }
        if let migration = error as? DataMigrationError {
            switch migration {
            case let .stepFailed(_, underlying):
                return "本机数据更新尚未完成。" + systemMessage(underlying, operation: .startup)
            case .invalidTrainingSnapshot:
                return "部分训练数据无法读取，已停止更新以保护原数据。请更新 App 后重试；若仍失败，请点击「导出诊断」后联系维护者。"
            case .markerVerificationFailed:
                return "本机数据更新未通过完整性检查，暂时不能进入 App。请重新打开 App；若仍失败，请点击「导出诊断」后联系维护者。"
            }
        }
        if error is SomaStorePreflightError {
            return AppErrorOperation.startup.fallback
        }
        if let agent = error as? ReActAgentError {
            switch agent {
            case .invalidToolCall:
                return "模型给出的操作内容不符合记录要求，未能完成这一步。请重试或更换模型；已经保存的记录仍保留。"
            case .emptyResponse:
                return "模型没有返回可用的答复。请重试或在设置中更换模型。"
            case .stepLimit:
                return "这次请求包含的处理步骤过多，尚未完成。请把任务分成几次发送；已经保存的记录仍保留。"
            }
        }
        if let configuration = error as? AIExtraConfigError {
            switch configuration {
            case .invalidJSON, .notObject:
                return "高级模型配置的格式不正确。请填写合法的 JSON 对象，或清空此项以使用默认配置。"
            case .reservedKeys:
                return "高级模型配置包含由 App 管理的请求字段。请移除这些字段，或清空此项以使用默认配置。"
            }
        }
        return nil
    }

    /// 兼容已落盘的旧失败卡；仅作展示，不更改记录或恢复所需的机器错误。
    static func message(from raw: String, operation: AppErrorOperation = .general) -> String {
        if let classified = modelMessage(status: nil, response: raw) {
            return classified
        }
        guard isSafeLocalized(raw) else { return operation.fallback }
        return withRecovery(raw, operation: operation)
    }

    static func remoteMessage(code: String, detail: String = "") -> String {
        switch code {
        case "unauthorized_device", "replay_detected":
            "远程服务未能验证这台设备。请重新打开 App 后重试；若仍失败，可在设置中发送反馈。"
        case "protocol_unsupported", "tool_schema_unsupported":
            "App 与远程服务的版本不兼容。请更新 App 后重试；若仍失败，可在设置中发送反馈。"
        case "provider_authentication_failed":
            "远程模型的授权已失效。请在设置中发送反馈，以便恢复服务授权。"
        case "provider_quota_exhausted":
            "远程模型的可用额度已用尽。请稍后重试；若仍失败，可在设置中发送反馈。"
        case "provider_rate_limited":
            "远程模型当前请求过多。请稍后重试。"
        case "provider_context_exceeded":
            "这次内容超过远程模型可处理的长度。请减少附件或分开发送后重试。"
        case "provider_vision_unsupported", "direct_video_unsupported":
            "远程模型暂不支持这次图片或视频输入。请减少附件或改用文字补充，并在设置中反馈模型能力问题；原附件仍保留。"
        case "video_fallback_unavailable", "full_video_unavailable":
            "视频未能转换为可分析的输入。原视频仍保留，请减少视频数量、重新选择可播放文件，或更换支持完整视频的模型。"
        case "provider_configuration_invalid":
            "远程模型配置无法使用。请在设置中发送反馈，以便检查服务地址和模型设置。"
        case "provider_timeout":
            "远程模型等待超时。请检查网络后重试；已经保存的记录仍保留。"
        case "provider_unavailable":
            "远程模型暂时不可用。请稍后重试；若仍失败，可在设置中发送反馈。"
        case "upload_incomplete":
            "附件尚未上传完整。请检查网络并重新发送；原附件仍在本机。"
        case "job_expired", "not_found":
            "这项远程任务已过期或无法找到。请重新发送需要处理的内容；本机记录仍保留。"
        case "job_cancelled": "远程任务已取消，需要时可以重新发送。"
        case "waiting_for_device": "这一步需要在本机完成。请保持 App 打开并连接网络后继续。"
        case "idempotency_conflict": "这次提交与已有任务不一致。请返回教练页查看任务状态，再重新发送。"
        default:
            message(from: detail, operation: .model)
        }
    }

    private static func systemMessage(_ error: Error, operation: AppErrorOperation) -> String {
        let value = error as NSError
        if value.domain == NSURLErrorDomain {
            switch value.code {
            case URLError.cancelled.rawValue: return "请求已取消，需要时可以重试。"
            case URLError.timedOut.rawValue: return "连接等待超时。请检查网络后重试；如果一直超时，请稍后再试。"
            case URLError.dataNotAllowed.rawValue:
                return "当前不允许使用蜂窝数据。请改用 Wi-Fi，或在系统设置中允许 Soma 使用蜂窝网络后重试。"
            case URLError.cannotFindHost.rawValue, URLError.cannotConnectToHost.rawValue:
                return "无法连接到服务地址。请检查网络和设置中的服务地址后重试。"
            case URLError.secureConnectionFailed.rawValue, URLError.serverCertificateUntrusted.rawValue,
                 URLError.serverCertificateHasBadDate.rawValue, URLError.serverCertificateHasUnknownRoot.rawValue:
                return "无法与服务建立安全连接。请检查设备日期和服务地址；如果仍失败，请联系服务提供方。"
            default: return "网络连接不可用或已中断。请检查 Wi-Fi 或蜂窝网络后重试。"
            }
        }
        if let file = AppFileFailure(value) {
            return file.cause + "。" + file.recovery
        }
        if error is DecodingError {
            return "返回或保存的内容与当前版本不兼容，暂时无法读取。请更新 App 后重试；原始记录和附件请继续保留。"
        }
        if let underlying = value.userInfo[NSUnderlyingErrorKey] as? NSError,
           let file = AppFileFailure(underlying)
        {
            return file.cause + "。" + file.recovery
        }
        return operation.fallback
    }

    private static func withRecovery(_ text: String, operation: AppErrorOperation) -> String {
        guard !text.isEmpty else { return operation.fallback }
        if text.range(of: "请(?!求)", options: .regularExpression) != nil
            || ["重试", "可以", "可在", "更换", "重新", "检查", "稍后"].contains(where: text.contains)
        {
            return text
        }
        return text + (text.hasSuffix("。") ? "" : "。") + operation.recovery
    }

    private static func isSafeLocalized(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 600,
              text.range(of: "[\\u4E00-\\u9FFF]", options: .regularExpression) != nil else { return false }
        let internalMarkers = ["{", "}", "Error Domain=", "NSCocoa", "SwiftData", "APIError", "Trace",
                               "video_url", "tool_call", "record_id", "request_id", "Bearer ", "sk-", "AVFoundation"]
        guard !internalMarkers.contains(where: text.contains),
              text.range(of: "(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f-]{20,}", options: .regularExpression) == nil,
              text.range(of: "[a-z]+_[a-z_]+", options: .regularExpression) == nil else { return false }
        return true
    }
}
