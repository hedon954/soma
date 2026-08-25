import Foundation

/// 带练录像的对外状态机。View 只读这个状态，不直接接触 `AVCaptureSession`。
enum WorkoutCameraState: Equatable {
    case idle
    case requestingPermission
    case configuring
    case startingSession
    case previewing
    case startingRecording
    case recording
    case unavailable(String)

    var message: String {
        switch self {
        case .idle:
            "相机尚未启动"
        case .requestingPermission:
            "正在请求相机权限"
        case .configuring:
            "正在配置相机"
        case .startingSession:
            "正在启动相机"
        case .previewing:
            "相机已就绪"
        case .startingRecording:
            "正在开始录像"
        case .recording:
            "正在录制本动作目标组"
        case let .unavailable(message):
            message
        }
    }
}

/// 录像失败对用户的表述。BUG 0025：`recordingFailed` 的 message 由
/// `WorkoutRecordingFailureDiagnosis` 生成，必须带具体原因与技术标识。
enum WorkoutCameraError: LocalizedError {
    case permissionDenied
    case frontCameraUnavailable
    case configurationFailed
    case activationTimedOut
    case activationSuperseded
    case recordingConnectionUnavailable(String)
    case insufficientStorage
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "没有相机权限；训练仍可继续，可在系统设置中开启。"
        case .frontCameraUnavailable:
            "当前设备没有可用的前置摄像头。"
        case .configurationFailed:
            "相机启动失败；训练仍可继续。"
        case .activationTimedOut:
            "相机未能在限定时间内启动；请重试，训练仍可继续。"
        case .activationSuperseded:
            "本次相机启动已被新的请求替代。"
        case let .recordingConnectionUnavailable(reason):
            "相机录像连接不可用（\(reason)）；请重试，训练仍可继续。"
        case .insufficientStorage:
            "可用存储空间不足，已跳过本次录像。"
        case let .recordingFailed(message):
            "录像失败：\(message)"
        }
    }
}
