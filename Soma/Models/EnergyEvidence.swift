import Foundation
import SwiftData

struct EnergyDayConfirmation: Codable, Equatable, Sendable {
    var foodComplete: Bool?
    var trainingComplete: Bool?
    var walkingCoverageComplete: Bool?
    var fluidChangeConcern: Bool?
    var mealEvidenceFingerprint: String?
}

/// Explicit user facts. Absence of a confirmation never means false or complete.
@Model
final class EnergyContextEntry {
    @Attribute(.unique) var key: String
    var date: Date
    var timeZoneIdentifier: String
    var lifestyleData: Data?
    var confirmationData: Data?
    var learningPaused: Bool?
    var sourceTurnID: UUID?
    var updatedAt: Date

    init(key: String, date: Date, timeZoneIdentifier: String, updatedAt: Date = .now) {
        self.key = key
        self.date = date
        self.timeZoneIdentifier = timeZoneIdentifier
        self.updatedAt = updatedAt
    }
}

/// Private derived evidence. Excluded from model context, export and application backup.
@Model
final class EnergyEvidenceEntry {
    @Attribute(.unique) var key: String
    var kindRaw: String
    var date: Date
    var payload: Data
    var reason: String
    var predecessorKey: String?
    var revision: Int
    var createdAt: Date

    init(key: String, kindRaw: String, date: Date, payload: Data, reason: String, predecessorKey: String?, revision: Int = 0, createdAt: Date = .now) {
        self.key = key
        self.kindRaw = kindRaw
        self.date = date
        self.payload = payload
        self.reason = reason
        self.predecessorKey = predecessorKey
        self.revision = revision
        self.createdAt = createdAt
    }
}
