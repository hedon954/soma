@testable import Soma
import SwiftData
import XCTest

@MainActor
final class EnergyForecastTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
    }

    func testSameWeekdayNeedsConfirmedHistoryAndNeverChangesActualRestDay() throws {
        let current = try calculation(today, training: 0)
        let future = today.addingTimeInterval(86400)
        var history = [today: current]
        for week in 1 ... 3 {
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: -7 * week, to: future))
            history[day] = try calculation(day, training: 500)
        }
        let forecasts = EnergyForecastProjection.upcoming(calculations: history, plans: [], on: today, calendar: calendar)
        let forecast = try XCTUnwrap(forecasts.first)
        XCTAssertEqual(forecast.evidenceDates.count, 3)
        XCTAssertGreaterThan(try XCTUnwrap(forecast.total), current.total)
        XCTAssertEqual(history[today]?.trainingDelta, 0)
        XCTAssertEqual(history[today]?.total, 2240)
        history.removeValue(forKey: forecast.evidenceDates[0])
        XCTAssertNil(EnergyForecastProjection.upcoming(calculations: history, plans: [], on: today, calendar: calendar).first?.total)
        XCTAssertTrue(EnergyForecastProjection.upcoming(calculations: [:], plans: [], on: today, calendar: calendar).isEmpty)
    }

    func testExplicitRestPlanOverridesTrainingHabitAndUnknownPlanNeverBecomesZero() throws {
        let current = try calculation(today, training: 0), future = today.addingTimeInterval(86400)
        let plans: [EnergyPlannedTrainingDay] = [
            .init(date: future, source: "虚构计划休息", eventsPerKilogram: []),
            .init(date: future.addingTimeInterval(86400), source: "虚构缺时长计划", eventsPerKilogram: nil)
        ]
        let forecasts = EnergyForecastProjection.upcoming(calculations: [today: current], plans: plans, on: today, calendar: calendar)
        XCTAssertEqual(forecasts[0].total, current.total)
        XCTAssertEqual(forecasts[0].trainingDelta, 0)
        XCTAssertNil(forecasts[1].total)
        XCTAssertNil(forecasts[1].trainingDelta)
    }

    func testPlanLoaderReadsConfirmedTargetsWithoutWritingAnyWorkout() throws {
        let container = try ModelContainer(for: Schema(SomaDataSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let exercise = ExerciseDefinition(canonicalName: "虚构跑步")
        exercise.targetKind = .duration
        context.insert(exercise)
        let prescription = TemplateExercisePrescription(exerciseID: exercise.id, exerciseName: exercise.canonicalName, order: 1,
                                                        plannedSets: [.init(order: 1, targetKind: .duration, targetDurationSeconds: 1800)])
        context.insert(TrainingSchedule(name: "虚构训练计划", anchorDate: today, slots: [.rest(), .training([.exercise(prescription)])]))
        try context.save()
        let plans = try EnergyPlanForecastLoader.load(in: container, now: today, calendar: calendar)
        XCTAssertEqual(plans.count, 7)
        XCTAssertEqual(plans.first?.eventsPerKilogram?.count, 1)
        XCTAssertGreaterThan(try XCTUnwrap(plans.first?.eventsPerKilogram?.first?.netEnergy(resting: 1600.0 / 70)), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EnergyEvidenceEntry>()), 0)
    }

    private func calculation(_ date: Date, training: Double) throws -> EnergyDayCalculation {
        let event = EnergyTrainingEvent(id: "fixture", source: "虚构来源", scope: .active, kilocalories: training, met: nil,
                                        durationHours: 1, start: date, end: date.addingTimeInterval(3600))
        return try EnergyDayCalculator.calculate(.init(date: date, resting: 1600, weightKG: 70,
                                                       reference: .init(effectiveFrom: date, factor: 1.4, walkingKilometers: 3, reason: "虚构参考"),
                                                       nonTrainingKilometers: 3, walkingCoverageConfirmed: true,
                                                       isEndedDay: true, training: training == 0 ? [] : [event], correction: 0))
    }
}
