import Foundation

enum WorkoutCalorieScope: String, Codable, CaseIterable, Hashable, Sendable {
    case active, metGross, gross, unknown

    var label: String {
        switch self {
        case .active: "活动消耗（不含静息）"
        case .metGross: "本地 MET 毛消耗"
        case .gross: "总消耗（含静息）"
        case .unknown: "口径待确认"
        }
    }
}
