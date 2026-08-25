import Foundation

enum ConversationIntent: String, Codable {
    case gym
    case meal
    case body
    case workout
    case switchGym
    case coach

    var recordedLabel: String? {
        switch self {
        case .gym: "已更新健身房"
        case .meal: "已记录饮食"
        case .body: "已记录身体数据"
        case .workout: "已记录训练"
        case .switchGym: "已切换健身房"
        case .coach: nil
        }
    }
}
