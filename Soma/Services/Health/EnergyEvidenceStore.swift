import Foundation
import SwiftData

enum EnergyEvidenceKind: String, Codable, Sendable {
    case reference, daily, calibration, healthActivity, association
}

@MainActor
enum EnergyEvidenceStore {
    static func contextKey(for date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        return "context:\(calendar.timeZone.identifier):\(day.timeIntervalSince1970)"
    }

    static func contextEntry(for date: Date, in context: ModelContext, calendar: Calendar = .current) throws -> EnergyContextEntry? {
        let key = contextKey(for: date, calendar: calendar)
        var query = FetchDescriptor<EnergyContextEntry>(predicate: #Predicate { $0.key == key })
        query.fetchLimit = 1
        return try context.fetch(query).first
    }

    static func saveConfirmation(
        _ confirmation: EnergyDayConfirmation, for date: Date, sourceTurnID: UUID? = nil,
        in context: ModelContext, now: Date = .now, calendar: Calendar = .current
    ) throws {
        guard calendar.startOfDay(for: date) <= calendar.startOfDay(for: now) else { throw EnergyLifestyleError.futureDate }
        let existing = try contextEntry(for: date, in: context, calendar: calendar)
        var confirmed = confirmation
        if confirmation.foodComplete == true {
            confirmed.mealEvidenceFingerprint = try EnergyFoodEvidence.fingerprint(on: date, in: context, calendar: calendar)
        }
        let encoded = try encode(confirmed)
        guard existing?.confirmationData != encoded else { return }
        let entry = existing ?? EnergyContextEntry(key: contextKey(for: date, calendar: calendar), date: calendar.startOfDay(for: date),
                                                   timeZoneIdentifier: calendar.timeZone.identifier, updatedAt: now)
        if existing == nil {
            context.insert(entry)
        }
        entry.confirmationData = encoded
        entry.sourceTurnID = sourceTurnID
        entry.updatedAt = now
        do { try context.save() } catch { context.rollback(); throw error }
    }

    static func saveLifestyle(_ facts: EnergyLifestyleFacts, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws {
        _ = try EnergyReferenceBuilder.initial(facts)
        guard calendar.startOfDay(for: facts.effectiveFrom) <= calendar.startOfDay(for: now) else { throw EnergyLifestyleError.futureDate }
        let existing = try contextEntry(for: facts.effectiveFrom, in: context, calendar: calendar)
        let encoded = try encode(facts)
        guard existing?.lifestyleData != encoded else { return }
        let entry = existing ?? EnergyContextEntry(key: contextKey(for: facts.effectiveFrom, calendar: calendar), date: calendar.startOfDay(for: facts.effectiveFrom),
                                                   timeZoneIdentifier: calendar.timeZone.identifier, updatedAt: now)
        if existing == nil {
            context.insert(entry)
        }
        entry.lifestyleData = encoded
        entry.updatedAt = now
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// A semantic revision includes its predecessor. Repeated reads of unchanged inputs create no row.
    @discardableResult
    static func append(
        _ value: some Encodable, kind: EnergyEvidenceKind, date: Date, reason: String,
        in context: ModelContext, now: Date = .now, saveImmediately: Bool = true
    ) throws -> EnergyEvidenceEntry {
        let payload = try encode(value)
        let raw = kind.rawValue
        var latest = FetchDescriptor<EnergyEvidenceEntry>(
            predicate: #Predicate { $0.kindRaw == raw && $0.date == date },
            sortBy: [SortDescriptor(\.revision, order: .reverse), SortDescriptor(\.key)]
        )
        latest.fetchLimit = 1
        let predecessor = try context.fetch(latest).first
        if let predecessor, predecessor.payload == payload {
            return predecessor
        }
        let material = Data((raw + ":" + String(date.timeIntervalSince1970) + ":" + (predecessor?.key ?? "")).utf8) + payload
        let key = raw + ":" + digest(material)
        var matching = FetchDescriptor<EnergyEvidenceEntry>(predicate: #Predicate { $0.key == key })
        matching.fetchLimit = 1
        if let existing = try context.fetch(matching).first {
            return existing
        }
        let entry = EnergyEvidenceEntry(key: key, kindRaw: raw, date: date, payload: payload, reason: reason,
                                        predecessorKey: predecessor?.key, revision: (predecessor?.revision ?? -1) + 1, createdAt: now)
        context.insert(entry)
        if saveImmediately {
            do { try context.save() } catch { context.rollback(); throw error }
        }
        return entry
    }

    static func encode(_ value: some Encodable) throws -> Data {
        try EnergyInputCoding.encode(value)
    }

    static func digest(_ data: Data) -> String {
        EnergyInputCoding.digest(data)
    }
}
