import Foundation
import SwiftData

struct EnergyContextDTO: Codable, Equatable, Sendable {
    let key: String
    let date: Date
    let timeZoneIdentifier: String
    let lifestyleData: Data?
    let confirmationData: Data?
    let learningPaused: Bool?
    let sourceTurnID: UUID?
    let updatedAt: Date

    init(_ entry: EnergyContextEntry) {
        key = entry.key
        date = entry.date
        timeZoneIdentifier = entry.timeZoneIdentifier
        lifestyleData = entry.lifestyleData
        confirmationData = entry.confirmationData
        learningPaused = entry.learningPaused
        sourceTurnID = entry.sourceTurnID
        updatedAt = entry.updatedAt
    }

    func insert(in context: ModelContext) {
        let entry = EnergyContextEntry(key: key, date: date, timeZoneIdentifier: timeZoneIdentifier, updatedAt: updatedAt)
        entry.lifestyleData = lifestyleData
        entry.confirmationData = confirmationData
        entry.learningPaused = learningPaused
        entry.sourceTurnID = sourceTurnID
        context.insert(entry)
    }
}

struct EnergyEvidenceDTO: Codable, Equatable, Sendable {
    let key: String
    let kindRaw: String
    let date: Date
    let payload: Data
    let reason: String
    let predecessorKey: String?
    let revision: Int
    let createdAt: Date

    init(_ entry: EnergyEvidenceEntry) {
        key = entry.key
        kindRaw = entry.kindRaw
        date = entry.date
        payload = entry.payload
        reason = entry.reason
        predecessorKey = entry.predecessorKey
        revision = entry.revision
        createdAt = entry.createdAt
    }

    func insert(in context: ModelContext) {
        context.insert(EnergyEvidenceEntry(key: key, kindRaw: kindRaw, date: date, payload: payload,
                                           reason: reason, predecessorKey: predecessorKey, revision: revision, createdAt: createdAt))
    }
}
