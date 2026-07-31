import ActivityKit
import Foundation

struct SomaAgentJobAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phaseRaw: String
        var operationCount: Int
        var queuedCount: Int
        var sequence: Int
        var isStale: Bool

        var phaseTitle: String {
            switch phaseRaw {
            case "queued":
                "任务已排队"
            case "waitingForNetwork":
                "等待网络"
            case "running":
                "Soma 正在处理"
            case "waitingForForeground":
                "等待返回 Soma"
            case "waitingForDevice":
                "等待设备工具"
            case "succeeded":
                "任务已完成"
            case "failed":
                "任务未完成"
            case "cancelled":
                "任务已取消"
            default:
                "任务状态已更新"
            }
        }

        var symbolName: String {
            switch phaseRaw {
            case "succeeded":
                "checkmark.circle.fill"
            case "failed":
                "exclamationmark.triangle.fill"
            case "cancelled":
                "xmark.circle.fill"
            case "waitingForForeground", "waitingForDevice", "waitingForNetwork":
                "pause.circle.fill"
            default:
                "waveform.path.ecg"
            }
        }
    }

    var jobID: UUID
    var turnID: UUID
}
