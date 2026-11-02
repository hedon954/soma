@testable import Soma
import XCTest

final class EnergyRuntimeProjectionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
    }

    private var profile: ProgressProfileFacts {
        .init(updatedAt: day, birthDate: calendar.date(from: DateComponents(year: 1996, month: 1, day: 1)),
              height: 170, biologicalSex: .male, baselines: [], fitnessGoal: nil)
    }

    private var weight: ProgressHistoryRecord {
        .init(activity: .init(id: UUID(), kind: .body, date: day, title: "虚构体重", detail: "", metric: nil), weight: 70)
    }

    func testHealthDailyEnergyCannotCancelLifestyleOrBecomeExtraReward() throws {
        let records = [weight, ProgressHistoryRecord(
            activity: .init(id: UUID(), kind: .workout, date: day, title: "日常活动", detail: "", metric: nil),
            calories: 223, activeEnergyKilocalories: 223, isDailyActivity: true
        )]
        for period in [ProgressPeriod.day, .week, .month, .year] {
            let snapshot = ProgressHistoryProjection.build(window: period.window(containing: day, calendar: calendar), records: records,
                                                           profile: profile, now: day.addingTimeInterval(86400), calendar: calendar)
            let estimate = try XCTUnwrap(snapshot.days.first { $0.date == day }?.energy.estimate)
            XCTAssertEqual(estimate.totalKilocalories, 1617.5 * 1.4, accuracy: 0.001)
            XCTAssertEqual(estimate.factor, 1.4, accuracy: 0.001)
        }
    }

    func testTrustedNonTrainingDistanceAndDeviceSessionShareOneCalculation() throws {
        var profile = profile
        let reference = EnergyReferenceDay(effectiveFrom: day, factor: 1.4, walkingKilometers: 3, reason: "虚构参考")
        profile.baselines = [.init(id: reference.id, effectiveFrom: day, factor: 1.4, label: "虚构参考")]
        profile.energyFacts.references = [reference]
        profile.energyFacts.contexts = [.init(date: day, timeZoneIdentifier: calendar.timeZone.identifier, lifestyle: nil,
                                              confirmation: .init(foodComplete: true, trainingComplete: true, walkingCoverageComplete: true), learningPaused: nil)]
        profile.energyFacts.activity = [.init(day: .init(date: day, calendar: calendar), training: [
                .init(id: "fixture-run", source: "虚构 COROS", scope: .active, kilocalories: 500, met: nil,
                      durationHours: 1, start: day, end: day.addingTimeInterval(3600))
            ], excludedIntervals: [.init(start: day, end: day.addingTimeInterval(3600))], nonTrainingKilometers: 5,
            nonTrainingSteps: 7000, hasAmbiguousBoundarySamples: false, basisID: HealthActivityDayEvidence.statisticsBasis)]
        let snapshot = ProgressHistoryProjection.build(window: ProgressPeriod.day.window(containing: day, calendar: calendar), records: [weight],
                                                       profile: profile, now: day.addingTimeInterval(86400), calendar: calendar)
        let calculation = try XCTUnwrap(snapshot.days.first?.energy.estimate?.calculation)
        XCTAssertEqual(calculation.walkingDelta, 70)
        XCTAssertEqual(calculation.adoptedTrainingIDs, ["fixture-run"])
        XCTAssertEqual(calculation.total, 1617.5 * 1.4 + 70 + 500 - (1617.5 * 1.4 * 0.9 - 1617.5 - 105) / 16, accuracy: 0.001)
        XCTAssertTrue(calculation.canCalibrate)
    }

    func testBoundaryAmbiguityAndUnknownCoverageDoNotReduceBudget() throws {
        var profile = profile
        profile.energyFacts.references = [.init(effectiveFrom: day, factor: 1.4, walkingKilometers: 3, reason: "虚构参考")]
        profile.energyFacts.activity = [.init(day: .init(date: day, calendar: calendar), training: [], excludedIntervals: [],
                                              nonTrainingKilometers: 0, nonTrainingSteps: 0, hasAmbiguousBoundarySamples: true,
                                              basisID: HealthActivityDayEvidence.statisticsBasis)]
        let snapshot = ProgressHistoryProjection.build(window: ProgressPeriod.day.window(containing: day, calendar: calendar), records: [weight],
                                                       profile: profile, now: day.addingTimeInterval(86400), calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(snapshot.days.first?.energy.estimate?.totalKilocalories), 1617.5 * 1.4, accuracy: 0.001)
        XCTAssertFalse(try XCTUnwrap(snapshot.days.first?.energy.estimate?.calculation?.canCalibrate))
    }

    func testProjectionDoesNotChangeReferenceIdentityOnRepeatedReads() {
        var profile = profile
        let life = EnergyLifestyleFacts(effectiveFrom: day, workPosture: .standing)
        profile.energyFacts.contexts = [.init(date: day, timeZoneIdentifier: calendar.timeZone.identifier, lifestyle: life, confirmation: nil, learningPaused: nil)]
        let records = [weight]
        let first = EnergyRuntimeProjection.build(window: ProgressPeriod.day.window(containing: day, calendar: calendar), records: records,
                                                  profile: profile, now: day, calendar: calendar)
        let second = EnergyRuntimeProjection.build(window: ProgressPeriod.day.window(containing: day, calendar: calendar), records: records,
                                                   profile: profile, now: day, calendar: calendar)
        XCTAssertEqual(first.calculations[day], second.calculations[day])
        XCTAssertEqual(first.calculations[day]?.input.reference.id, life.id)
    }

    func testEditingAndDeletingLifestyleNeverReusesReferenceFromOldFacts() throws {
        var profile = profile
        var life = EnergyLifestyleFacts(effectiveFrom: day, workPosture: .sitting)
        var reference = try EnergyReferenceBuilder.initial(life)
        reference.walkingKilometers = 3
        profile.energyFacts.references = [reference]
        life.workPosture = .walking
        profile.energyFacts.contexts = [.init(date: day, timeZoneIdentifier: calendar.timeZone.identifier,
                                              lifestyle: life, confirmation: nil, learningPaused: nil)]
        let updated = EnergyRuntimeProjection.build(window: ProgressPeriod.day.window(containing: day, calendar: calendar), records: [weight],
                                                    profile: profile, now: day, calendar: calendar)
        XCTAssertEqual(updated.calculations[day]?.input.reference.factor, 1.6)
        XCTAssertNil(updated.calculations[day]?.input.reference.walkingKilometers)
        profile.energyFacts.contexts = []
        let removed = EnergyRuntimeProjection.build(window: ProgressPeriod.day.window(containing: day, calendar: calendar), records: [weight],
                                                    profile: profile, now: day, calendar: calendar)
        XCTAssertEqual(removed.calculations[day]?.input.reference.factor, 1.4)
        XCTAssertNotEqual(removed.calculations[day]?.input.reference.id, life.id)
    }
}
