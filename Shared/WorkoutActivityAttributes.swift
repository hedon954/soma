import ActivityKit
import Foundation

struct SomaWorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phaseRaw: String
        var completedSetCount: Int
        var totalSetCount: Int
        var restEndAt: Date?
        var progressFraction: Double
        var updateSequence: Int

        private enum CodingKeys: String, CodingKey {
            case phaseRaw
            case completedSetCount
            case totalSetCount
            case restEndAt
            case progressFraction
            case updateSequence
        }

        init(
            phaseRaw: String,
            completedSetCount: Int,
            totalSetCount: Int,
            restEndAt: Date?,
            progressFraction: Double = 0,
            updateSequence: Int = 0
        ) {
            self.phaseRaw = phaseRaw
            self.completedSetCount = completedSetCount
            self.totalSetCount = totalSetCount
            self.restEndAt = restEndAt
            self.progressFraction = min(max(progressFraction, 0), 1)
            self.updateSequence = updateSequence
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            phaseRaw = try container.decode(String.self, forKey: .phaseRaw)
            completedSetCount = try container.decode(Int.self, forKey: .completedSetCount)
            totalSetCount = try container.decode(Int.self, forKey: .totalSetCount)
            restEndAt = try container.decodeIfPresent(Date.self, forKey: .restEndAt)
            progressFraction = try container.decodeIfPresent(Double.self, forKey: .progressFraction) ?? 0
            updateSequence = try container.decodeIfPresent(Int.self, forKey: .updateSequence) ?? 0
        }

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
