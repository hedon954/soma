import Foundation

struct EnergyTimeAllocation: Codable, Equatable, Sendable {
    let label: String
    let hours: Double
    let physicalActivityRatio: Double
}

struct EnergyLifestyleFacts: Codable, Equatable, Sendable, Identifiable {
    enum WorkPosture: String, Codable, CaseIterable, Sendable {
        case sitting, standing, walking
    }

    var id: UUID = .init()
    let effectiveFrom: Date
    var workPosture: WorkPosture?
    var workHours: Double?
    var workDaysPerWeek: Int?
    var commutingDescription: String?
    var houseworkDescription: String?
    var commutingWalkMinutes: Double?
    var houseworkMinutes: Double?
    /// Only complete explicit 24h allocations use the factorial calculation.
    var allocations: [EnergyTimeAllocation] = []
}
