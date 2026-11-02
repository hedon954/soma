import Foundation
import SwiftData

@MainActor
enum EnergyContextStore {
    static func replace(key: String, lifestyle: EnergyLifestyleFacts?, confirmation: EnergyDayConfirmation?, reconfirmFood: Bool = false, in context: ModelContext) throws {
        var query = FetchDescriptor<EnergyContextEntry>(predicate: #Predicate { $0.key == key })
        query.fetchLimit = 1
        guard let row = try context.fetch(query).first else { throw EnergyCalculationError.invalidInput }
        if let lifestyle {
            _ = try EnergyReferenceBuilder.initial(lifestyle)
        }
        let lifeData = try lifestyle.map { try EnergyInputCoding.encode($0) }
        var flags = confirmation
        if reconfirmFood, flags?.foodComplete == true {
            var calendar = Calendar(identifier: .gregorian)
            guard let zone = TimeZone(identifier: row.timeZoneIdentifier) else { throw EnergyCalculationError.invalidInput }
            calendar.timeZone = zone
            flags?.mealEvidenceFingerprint = try EnergyFoodEvidence.fingerprint(on: row.date, in: context, calendar: calendar)
        }
        let flagsData = try flags.map { try EnergyInputCoding.encode($0) }
        row.lifestyleData = lifeData
        row.confirmationData = flagsData
        row.updatedAt = .now
        do { try context.save() } catch { context.rollback(); throw error }
    }

    static func delete(key: String, in context: ModelContext) throws {
        var query = FetchDescriptor<EnergyContextEntry>(predicate: #Predicate { $0.key == key })
        query.fetchLimit = 1
        guard let row = try context.fetch(query).first, row.key != "control:energy-learning" else { return }
        context.delete(row)
        do { try context.save() } catch { context.rollback(); throw error }
    }

    static func dates(from: String?, to: String?, anchor: Date, calendar: Calendar = .current) throws -> [Date] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        func parse(_ raw: String?, fallback: Date) throws -> Date {
            guard let raw else { return calendar.startOfDay(for: fallback) }
            guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else { throw EnergyCalculationError.invalidInput }
            return date
        }
        let first = try parse(from, fallback: anchor), last = try parse(to, fallback: first)
        guard let span = calendar.dateComponents([.day], from: first, to: last).day,
              (0 ... 30).contains(span), last <= calendar.startOfDay(for: anchor) else { throw EnergyCalculationError.invalidInput }
        return (0 ... span).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    @discardableResult
    static func save(
        _ patch: EnergyContextPatch, dates: [Date], sourceTurnID: UUID? = nil,
        in context: ModelContext, now: Date = .now, calendar: Calendar = .current
    ) throws -> Int {
        guard !dates.isEmpty, dates.count <= 31, patch.hasLifestyle || patch.hasConfirmation,
              dates.allSatisfy({ $0 <= calendar.startOfDay(for: now) }) else { throw EnergyCalculationError.invalidInput }
        for (value, maximum) in [(patch.workHours, 24.0), (patch.commutingWalkMinutes, 1440), (patch.houseworkMinutes, 1440)] {
            if let value, !value.isFinite || !(0 ... maximum).contains(value) {
                throw EnergyCalculationError.invalidInput
            }
        }
        if let count = patch.workDaysPerWeek, !(0 ... 7).contains(count) {
            throw EnergyCalculationError.invalidInput
        }
        for text in [patch.commutingDescription, patch.houseworkDescription] {
            if let text, text.count > 1000 {
                throw EnergyCalculationError.invalidInput
            }
        }
        var changed = 0
        do {
            for (index, date) in dates.enumerated() where index == 0 || patch.hasConfirmation {
                let existing = try EnergyEvidenceStore.contextEntry(for: date, in: context, calendar: calendar)
                let row = existing ?? EnergyContextEntry(key: EnergyEvidenceStore.contextKey(for: date, calendar: calendar), date: date,
                                                         timeZoneIdentifier: calendar.timeZone.identifier)
                var lifestyle = try row.lifestyleData.map { try JSONDecoder().decode(EnergyLifestyleFacts.self, from: $0) }
                if index == 0, patch.hasLifestyle {
                    var value = try lifestyle ?? inheritedLifestyle(on: date, in: context)
                    value.workPosture = patch.workPosture ?? value.workPosture
                    value.workHours = patch.workHours ?? value.workHours
                    value.workDaysPerWeek = patch.workDaysPerWeek ?? value.workDaysPerWeek
                    value.commutingDescription = patch.commutingDescription ?? value.commutingDescription
                    value.commutingWalkMinutes = patch.commutingWalkMinutes ?? value.commutingWalkMinutes
                    value.houseworkDescription = patch.houseworkDescription ?? value.houseworkDescription
                    value.houseworkMinutes = patch.houseworkMinutes ?? value.houseworkMinutes
                    _ = try EnergyReferenceBuilder.initial(value)
                    lifestyle = value
                }
                var confirmation = try row.confirmationData.map { try JSONDecoder().decode(EnergyDayConfirmation.self, from: $0) }
                if patch.hasConfirmation {
                    var value = confirmation ?? .init()
                    value.foodComplete = patch.foodComplete ?? value.foodComplete
                    if let complete = patch.foodComplete {
                        value.mealEvidenceFingerprint = complete ? try EnergyFoodEvidence.fingerprint(on: date, in: context, calendar: calendar) : nil
                    }
                    value.trainingComplete = patch.trainingComplete ?? value.trainingComplete
                    value.walkingCoverageComplete = patch.walkingCoverageComplete ?? value.walkingCoverageComplete
                    value.fluidChangeConcern = patch.fluidChangeConcern ?? value.fluidChangeConcern
                    confirmation = value
                }
                let lifeData = try lifestyle.map { try EnergyInputCoding.encode($0) }
                let flagsData = try confirmation.map { try EnergyInputCoding.encode($0) }
                guard row.lifestyleData != lifeData || row.confirmationData != flagsData else { continue }
                if existing == nil {
                    context.insert(row)
                }
                row.lifestyleData = lifeData
                row.confirmationData = flagsData
                row.sourceTurnID = sourceTurnID
                row.updatedAt = now
                changed += 1
            }
            if context.hasChanges {
                try context.save()
            }
            return changed
        } catch { context.rollback(); throw error }
    }

    private static func inheritedLifestyle(on date: Date, in context: ModelContext) throws -> EnergyLifestyleFacts {
        var query = FetchDescriptor<EnergyContextEntry>(predicate: #Predicate { $0.date < date && $0.lifestyleData != nil },
                                                        sortBy: [SortDescriptor(\.date, order: .reverse)])
        query.fetchLimit = 1
        guard let data = try context.fetch(query).first?.lifestyleData else { return .init(effectiveFrom: date) }
        let old = try JSONDecoder().decode(EnergyLifestyleFacts.self, from: data)
        return .init(effectiveFrom: date, workPosture: old.workPosture, workHours: old.workHours,
                     workDaysPerWeek: old.workDaysPerWeek, commutingDescription: old.commutingDescription,
                     houseworkDescription: old.houseworkDescription, commutingWalkMinutes: old.commutingWalkMinutes,
                     houseworkMinutes: old.houseworkMinutes)
    }
}
