import Foundation

struct EnergyContextFacts: Sendable {
    let date: Date
    let timeZoneIdentifier: String
    let lifestyle: EnergyLifestyleFacts?
    let confirmation: EnergyDayConfirmation?
    let learningPaused: Bool?
}
