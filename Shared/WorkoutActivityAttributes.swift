import ActivityKit
import Foundation

struct SomaWorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phaseRaw: String
        var completedSetCount: Int
        var totalSetCount: Int
        var restEndAt: Date?

        var phaseTitle: String {
            switch phaseRaw {
            case "resting":
                "组间休息"
            case "paused":
                "训练已暂停"
            case "completed":
                "训练已完成"
            default:
                "训练进行中"
            }
        }

        var symbolName: String {
            switch phaseRaw {
            case "resting":
                "timer"
            case "paused":
                "pause.circle.fill"
            case "completed":
                "checkmark.circle.fill"
            default:
                "figure.strengthtraining.traditional"
            }
        }
    }

    var sessionID: UUID
}
