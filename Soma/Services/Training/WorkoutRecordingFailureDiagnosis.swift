@preconcurrency import AVFoundation
import Foundation

/// BUG 0025：录像提前结束时原来只显示一句固定文案，AVFoundation 给的错误被丢掉，用户和
/// 维护者都无法判断到底是存储不足、别的 App 抢了相机，还是编码器被系统回收。这里把错误域、
/// 错误码和中断原因翻译成具体中文原因，并保留可检索的技术标识。
struct WorkoutRecordingFailureDiagnosis: Equatable, Sendable {
    /// 用户能理解的具体原因，不含句尾标点。
    let cause: String
    /// 可检索的技术标识，例如 `AVFoundationErrorDomain -11818 · finish`。
    let technical: String

    /// 已经拿到可用部分视频时的文案。
    var partialRecordingMessage: String {
        "\(cause)；已保留可用的部分视频，训练数据不受影响。请检查相机与存储空间后重试。"
    }

    /// 完全没有可用视频时的文案。
    var failureMessage: String {
        "\(cause)；训练数据不受影响。请检查相机与存储空间后重试。"
    }
}

extension WorkoutRecordingFailureDiagnosis {
    static let unknownCause = "系统提前结束了录像，未给出错误原因"

    static func make(error: Error?, stage: String) -> Self {
        guard let error else {
            return Self(
                cause: unknownCause,
                technical: "no_error · \(stage)"
            )
        }
        let nsError = error as NSError
        return Self(
            cause: cause(for: nsError),
            technical: technical(for: nsError, stage: stage)
        )
    }

    static func interruption(
        reasonCode: Int?,
        stage: String
    ) -> Self {
        guard let reasonCode,
              let reason = AVCaptureSession.InterruptionReason(
                  rawValue: reasonCode
              )
        else {
            return Self(
                cause: "相机被系统中断，未给出中断原因",
                technical: "interruption_reason=\(reasonCode.map(String.init) ?? "none") · \(stage)"
            )
        }
        return Self(
            cause: cause(for: reason),
            technical: "interruption_reason=\(reasonCode) · \(stage)"
        )
    }

    static func cause(for reason: AVCaptureSession.InterruptionReason) -> String {
        switch reason {
        case .videoDeviceNotAvailableInBackground:
            "App 退到后台后系统收回了摄像头"
        case .audioDeviceInUseByAnotherClient:
            "麦克风被其它 App 占用"
        case .videoDeviceInUseByAnotherClient:
            "摄像头被其它 App 占用"
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            "分屏或画中画状态下系统不允许使用摄像头"
        case .videoDeviceNotAvailableDueToSystemPressure:
            "设备发热或资源紧张，系统暂停了摄像头"
        default:
            // 新系统会继续添加中断原因（例如敏感内容拦截）。最低支持 iOS 17，不能直接引用
            // 更高版本的 case，所以这里保留原始值让日志仍可定位。
            "相机被系统中断，未给出可确认的原因"
        }
    }

    /// AVFoundation 录像错误码到中文原因的固定映射。用表而不是 switch，既方便测试逐条覆盖，
    /// 也避免把所有分支塞进一个高复杂度函数。
    private static let avErrorCauses: [AVError.Code: String] = [
        .diskFull: "设备存储空间不足，无法继续写入视频",
        .sessionWasInterrupted: "相机会话被系统中断（来电、其它 App 抢占相机或分屏）",
        .maximumDurationReached: "本次录像达到了系统允许的最长时长",
        .maximumFileSizeReached: "本次录像达到了系统允许的最大文件体积",
        .deviceWasDisconnected: "摄像头在录像过程中断开",
        .deviceInUseByAnotherApplication: "摄像头被其它 App 占用",
        .deviceLockedForConfigurationByAnotherProcess: "摄像头正被其它进程配置占用",
        .mediaServicesWereReset: "系统媒体服务被重置，相机需要重新启动",
        .sessionNotRunning: "相机会话在录像期间停止运行",
        .sessionConfigurationChanged: "录像过程中相机配置被改动（预览或方向重建）",
        .noDataCaptured: "系统没有采集到任何画面数据",
        .outOfMemory: "内存不足，系统停止了视频编码",
        // 退到后台被收回摄像头由 `interruption(reasonCode:)` 的
        // `videoDeviceNotAvailableInBackground` 覆盖；同名 AVError 自 iOS 9 起不再产生。
        .deviceNotConnected: "找不到可用的摄像头",
        .fileAlreadyExists: "录像目标文件已存在",
        .mediaDiscontinuity: "视频数据流出现断点",
        .mediaChanged: "录像期间媒体格式发生变化",
        .operationNotAllowed: "系统不允许本次录像操作",
        .applicationIsNotAuthorized: "系统未授权本次录像",
        .contentIsNotAuthorized: "系统未授权本次录像",
        .unknown: "系统未说明录像失败的具体原因"
    ]

    private static func cause(for nsError: NSError) -> String {
        if let file = AppFileFailure(nsError) {
            return file.cause
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           let file = AppFileFailure(underlying)
        {
            return file.cause
        }
        guard nsError.domain == AVFoundationErrorDomain else {
            return "录像发生错误，系统没有提供可确认的原因"
        }
        guard let code = AVError.Code(rawValue: nsError.code) else {
            return "系统未说明录像失败的具体原因"
        }
        if let mapped = avErrorCauses[code] {
            return mapped
        }
        return "系统未说明录像失败的具体原因"
    }

    private static func technical(for nsError: NSError, stage: String) -> String {
        var parts = ["\(nsError.domain) \(nsError.code)"]
        if let successKey = nsError.userInfo[
            AVErrorRecordingSuccessfullyFinishedKey
        ] {
            let finished = (successKey as? NSNumber)?.boolValue
                ?? (successKey as? Bool)
                ?? false
            parts.append("finished=\(finished)")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("under=\(underlying.domain) \(underlying.code)")
        }
        parts.append(stage)
        return parts.joined(separator: " · ")
    }
}
