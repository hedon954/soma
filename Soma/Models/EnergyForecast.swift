import Foundation

struct EnergyPlannedTrainingDay: Sendable {
    let date: Date
    let source: String
    /// nil means the confirmed plan lacks sufficient targets; [] means explicit planned rest.
    let eventsPerKilogram: [EnergyTrainingEvent]?
}

struct EnergyForecast: Identifiable, Equatable, Sendable {
    var id: Date {
        date
    }

    let date: Date
    let total: Double?
    let trainingDelta: Double?
    let source: String
    let evidenceDates: [Date]
}
