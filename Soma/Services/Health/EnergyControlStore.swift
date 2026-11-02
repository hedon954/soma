import Foundation
import SwiftData

@MainActor
enum EnergyControlStore {
    static func isPaused(in context: ModelContext, on date: Date = .now) throws -> Bool {
        var query = FetchDescriptor<EnergyContextEntry>(predicate: #Predicate { $0.date <= date && $0.learningPaused != nil },
                                                        sortBy: [SortDescriptor(\.date, order: .reverse)])
        query.fetchLimit = 1
        return try context.fetch(query).first?.learningPaused ?? false
    }

    static func setPaused(_ paused: Bool, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws {
        let key = "control:energy-learning"
        var query = FetchDescriptor<EnergyContextEntry>(predicate: #Predicate { $0.key == key })
        query.fetchLimit = 1
        let existing = try context.fetch(query).first
        let entry = existing ?? EnergyContextEntry(key: key, date: .distantPast,
                                                   timeZoneIdentifier: calendar.timeZone.identifier)
        guard entry.learningPaused != paused else { return }
        if existing == nil {
            context.insert(entry)
        }
        entry.learningPaused = paused
        entry.updatedAt = now
        do { try context.save() } catch { context.rollback(); throw error }
    }

    static func restore(key: String, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws {
        var target = FetchDescriptor<EnergyEvidenceEntry>(predicate: #Predicate { $0.key == key && $0.kindRaw == "calibration" })
        target.fetchLimit = 1
        guard let row = try context.fetch(target).first else { throw EnergyCalculationError.invalidInput }
        let prior = try JSONDecoder().decode(EnergyCalibrationReview.self, from: row.payload)
        guard prior.nextCorrection.isFinite else { throw EnergyCalculationError.invalidInput }
        let day = calendar.startOfDay(for: now)
        var current = FetchDescriptor<EnergyEvidenceEntry>(predicate: #Predicate { $0.kindRaw == "calibration" && $0.date <= day },
                                                           sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.revision, order: .reverse)])
        current.fetchLimit = 1
        let latest = try context.fetch(current).first.map { try JSONDecoder().decode(EnergyCalibrationReview.self, from: $0.payload) }
        guard latest?.nextCorrection != prior.nextCorrection else { return }
        let review = EnergyCalibrationReview(
            date: day, windowStart: prior.windowStart, windowEnd: prior.windowEnd,
            inputFingerprint: "restore:" + key, previousCorrection: latest?.nextCorrection ?? 0,
            nextCorrection: prior.nextCorrection, meanIntake: prior.meanIntake, meanModel: prior.meanModel, slope: prior.slope,
            minimumCandidate: prior.minimumCandidate, maximumCandidate: prior.maximumCandidate,
            weightDayCount: prior.weightDayCount, direction: 0, evidenceEligible: false,
            reason: "本人恢复此前的长期修正，新的自动校准需重新积累同方向证据", restoredFromKey: key,
            inputDays: prior.inputDays, previousReviewFingerprint: latest?.inputFingerprint
        )
        try EnergyEvidenceStore.append(review, kind: .calibration, date: day, reason: review.reason, in: context, now: now)
    }
}
