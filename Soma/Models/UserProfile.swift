import Foundation
import SwiftData

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case unspecified = "未填写"
    case female = "女性"
    case male = "男性"
    case other = "其他或不愿填写"

    var id: String {
        rawValue
    }
}

@Model
final class UserProfile: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var updatedAt: Date
    var displayName: String
    var biologicalSexRaw: String
    var birthDate: Date?
    // 仅用于兼容早期本地数据；界面与 Agent 均使用 birthDate 动态计算年龄。
    var age: Int?
    var height: Double?
    var referenceWeight: Double?
    var fitnessGoal: String
    var healthNotes: String

    var biologicalSex: BiologicalSex {
        get { BiologicalSex(rawValue: biologicalSexRaw) ?? .unspecified }
        set { biologicalSexRaw = newValue.rawValue }
    }

    var currentAge: Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: .now).year
    }

    init(
        updatedAt: Date = .now,
        displayName: String = "",
        biologicalSex: BiologicalSex = .unspecified,
        birthDate: Date? = nil,
        age: Int? = nil,
        height: Double? = nil,
        referenceWeight: Double? = nil,
        fitnessGoal: String = "",
        healthNotes: String = ""
    ) {
        id = UUID()
        self.updatedAt = updatedAt
        self.displayName = displayName
        biologicalSexRaw = biologicalSex.rawValue
        self.birthDate = birthDate
        self.age = age
        self.height = height
        self.referenceWeight = referenceWeight
        self.fitnessGoal = fitnessGoal
        self.healthNotes = healthNotes
    }
}
