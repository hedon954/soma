import Foundation

struct EnergyContextPatch: Codable, Equatable, Sendable {
    var workPosture: EnergyLifestyleFacts.WorkPosture?
    var workHours: Double?
    var workDaysPerWeek: Int?
    var commutingDescription: String?
    var commutingWalkMinutes: Double?
    var houseworkDescription: String?
    var houseworkMinutes: Double?
    var foodComplete: Bool?
    var trainingComplete: Bool?
    var walkingCoverageComplete: Bool?
    var fluidChangeConcern: Bool?

    enum CodingKeys: String, CodingKey {
        case workPosture = "work_posture", workHours = "work_hours", workDaysPerWeek = "work_days_per_week"
        case commutingDescription = "commuting_description", commutingWalkMinutes = "commuting_walk_minutes"
        case houseworkDescription = "housework_description", houseworkMinutes = "housework_minutes"
        case foodComplete = "food_complete", trainingComplete = "training_complete"
        case walkingCoverageComplete = "walking_coverage_complete", fluidChangeConcern = "fluid_change_concern"
    }

    var hasLifestyle: Bool {
        workPosture != nil || workHours != nil || workDaysPerWeek != nil || commutingDescription != nil
            || commutingWalkMinutes != nil || houseworkDescription != nil || houseworkMinutes != nil
    }

    var hasConfirmation: Bool {
        foodComplete != nil || trainingComplete != nil || walkingCoverageComplete != nil || fluidChangeConcern != nil
    }
}
