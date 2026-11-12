import Foundation
import SwiftData

@MainActor
enum EnergyUITestFixture {
    static func seedIfRequested(in context: ModelContext) throws {
        guard AppTestRuntime.isRunning else { return }
        if ProcessInfo.processInfo.environment["SOMA_UI_ENERGY_FIXTURE"] == "1" {
            try seedEnergy(in: context)
        }
        if ProcessInfo.processInfo.environment["SOMA_UI_LEGACY_ENERGY_TOTAL_FIXTURE"] == "1" {
            try seedLegacyPresentedTotalReview(in: context)
        }
    }

    private static func seedEnergy(in context: ModelContext) throws {
        let calendar = Calendar.current, today = calendar.startOfDay(for: .now)
        let first = calendar.date(byAdding: .day, value: -56, to: today)!
        let old = try context.fetch(FetchDescriptor<WorkoutEntry>(predicate: #Predicate { $0.exercise == "虚构深蹲" }))
        old.forEach { context.delete($0) }
        try context.save()
        let facts = EnergyLifestyleFacts(effectiveFrom: first, workPosture: .sitting, workHours: 8, workDaysPerWeek: 5,
                                         commutingDescription: "虚构地铁通勤", houseworkDescription: "虚构日常家务",
                                         commutingWalkMinutes: 30, houseworkMinutes: 20)
        try EnergyEvidenceStore.saveLifestyle(facts, in: context)
        let sessionID = UUID()
        for index in 0 ..< 2 {
            context.insert(WorkoutEntry(date: today, exercise: "虚构动作 \(index + 1)", durationMinutes: 5,
                                        estimatedCalories: 200, calorieMET: 5, calorieScope: .metGross,
                                        calorieDurationMinutes: 5, sourceWorkoutSessionID: sessionID))
        }
        for offset in -56 ... 0 {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            try EnergyEvidenceStore.saveConfirmation(.init(foodComplete: true, trainingComplete: true, walkingCoverageComplete: true), for: day, in: context)
            let intervals: [EnergyTimeInterval] = offset == 0 ? [.init(start: today, end: today.addingTimeInterval(600))] : []
            let training: [EnergyTrainingEvent] = offset == 0 ? [
                .init(id: "health:fictional-coros", source: "虚构 COROS", activityType: "力量训练", scope: .active,
                      kilocalories: 450, met: nil, durationHours: 1.0 / 6, start: today, end: today.addingTimeInterval(600))
            ] : []
            let value = HealthActivityDayEvidence(day: .init(date: day, calendar: calendar), training: training, excludedIntervals: intervals,
                                                  nonTrainingKilometers: offset == 0 ? 5 : 3, nonTrainingSteps: offset == 0 ? 7000 : 4200,
                                                  hasAmbiguousBoundarySamples: false, basisID: HealthActivityDayEvidence.statisticsBasis)
            try EnergyEvidenceStore.append(value, kind: .healthActivity, date: day, reason: "虚构 UI 夹具", in: context)
        }
    }

    private static func seedLegacyPresentedTotalReview(in context: ModelContext) throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let existing = try context.fetch(FetchDescriptor<EnergyEvidenceEntry>(
            predicate: #Predicate { $0.key == "calibration:ui-legacy-presented-total" }
        ))
        existing.forEach { context.delete($0) }
        let reference = EnergyReferenceDay(effectiveFrom: today, factor: 1.4, reason: "虚构旧格式参考")
        let input = EnergyDayInput(
            date: today, resting: 1600, weightKG: 70, reference: reference,
            nonTrainingKilometers: nil, walkingCoverageConfirmed: false, isEndedDay: true,
            training: [], correction: 0
        )
        let calculation = EnergyDayCalculation(
            input: input, baseline: 2240, walkingDelta: 0, trainingDelta: 0,
            displacedActivityPerHour: 0, adoptedTrainingIDs: [], excludedTrainingIDs: [], issues: []
        )
        let review = EnergyCalibrationReview(
            date: today, windowStart: today, windowEnd: today, inputFingerprint: "ui-legacy-fixture",
            previousCorrection: 0, nextCorrection: 0, meanIntake: nil, meanModel: nil,
            slope: nil, minimumCandidate: nil, maximumCandidate: nil, weightDayCount: 0,
            direction: 0, evidenceEligible: false, reason: "虚构旧格式校准",
            inputDays: [
                .init(
                    date: today, intake: 2000, uncalibratedTotal: 2240, foodComplete: true,
                    activityComplete: true, weights: [70], fluidChangeConcern: false,
                    calculation: calculation, sourceMealIDs: nil
                )
            ]
        )
        var object = try jsonObject(EnergyInputCoding.encode(review))
        let presented: [String: Any] = [
            "restingKilocalories": 1600,
            "coefficient": 1.4,
            "activity": ["recordedTraining": ["_0": 320]]
        ]
        guard var days = object["inputDays"] as? [[String: Any]], var first = days.first else { return }
        var calc = first["calculation"] as? [String: Any] ?? [:]
        calc["presentedTotal"] = presented
        first["calculation"] = calc
        days[0] = first
        object["inputDays"] = days
        let payload = try JSONSerialization.data(withJSONObject: object)
        context.insert(
            EnergyEvidenceEntry(
                key: "calibration:ui-legacy-presented-total",
                kindRaw: EnergyEvidenceKind.calibration.rawValue,
                date: today, payload: payload, reason: "虚构旧格式 UI 夹具", predecessorKey: nil
            )
        )
        try context.save()
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let object = value as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "夹具 JSON 不是对象"))
        }
        return object
    }
}
