import Foundation
import SwiftData

@MainActor
enum EnergyUITestFixture {
    static func seedIfRequested(in context: ModelContext) throws {
        guard AppTestRuntime.isRunning, ProcessInfo.processInfo.environment["SOMA_UI_ENERGY_FIXTURE"] == "1" else { return }
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
}
