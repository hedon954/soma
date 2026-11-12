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
            XCTAssertEqual(estimate.totalKilocalories, 1617.5 * 1.4 + 223, accuracy: 0.001)
            XCTAssertEqual(estimate.factor, ResidualEnergyCoefficient.initialFallback, accuracy: 0.001)
            XCTAssertEqual(estimate.components?.activity, .selected(223))
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
        let estimate = try XCTUnwrap(snapshot.days.first?.energy.estimate)
        XCTAssertEqual(estimate.calculation?.adoptedTrainingIDs, ["fixture-run"])
        XCTAssertEqual(estimate.totalKilocalories, 1617.5 * 1.4, accuracy: 0.001)
        XCTAssertEqual(estimate.components?.activity, .absent)
        XCTAssertEqual(estimate.components?.trainingKilocalories, 0)
        XCTAssertNotNil(estimate.calculation)
        XCTAssertNotEqual(estimate.calculation?.total, estimate.totalKilocalories)
    }

    func testWinningPackageKeepsSelectedActiveAndAddsListTrainingDirectly() throws {
        var profile = profile
        let health = EnergyTrainingEvent(
            id: "health:fixture", source: "Apple Watch", scope: .active, kilocalories: 100,
            met: nil, durationHours: 1, start: day, end: day.addingTimeInterval(3600)
        )
        profile.energyFacts.activity = [.init(
            day: .init(date: day, calendar: calendar), training: [health], excludedIntervals: [],
            nonTrainingKilometers: nil, nonTrainingSteps: nil, hasAmbiguousBoundarySamples: false,
            basisID: HealthActivityDayEvidence.statisticsBasis
        )]
        let daily = ProgressHistoryRecord(
            activity: .init(id: UUID(), kind: .workout, date: day, title: "日常活动", detail: "", metric: nil),
            calories: 400, activeEnergyKilocalories: 400, isDailyActivity: true, dailyActivitySource: .appleHealth
        )
        let included = ProgressHistoryProjection.build(
            window: ProgressPeriod.day.window(containing: day, calendar: calendar),
            records: [weight, daily], profile: profile, now: day.addingTimeInterval(86400), calendar: calendar
        )
        let split = try XCTUnwrap(included.days.first { $0.date == day }?.energy.estimate)
        XCTAssertEqual(split.totalKilocalories, 1617.5 * 1.4 + 400, accuracy: 0.001)
        XCTAssertEqual(split.components?.activity, .selected(400))
        XCTAssertEqual(split.components?.trainingKilocalories, 0)
        let soma = ProgressHistoryRecord(
            activity: .init(id: UUID(), kind: .workout, date: day, title: "虚构训练", detail: "", metric: nil),
            calories: 800, calorieMET: 5, durationSeconds: 3600
        )
        let mixed = ProgressHistoryProjection.build(
            window: ProgressPeriod.day.window(containing: day, calendar: calendar),
            records: [weight, daily, soma], profile: profile, now: day.addingTimeInterval(86400), calendar: calendar
        )
        let combined = try XCTUnwrap(mixed.days.first { $0.date == day }?.energy.estimate)
        XCTAssertEqual(combined.totalKilocalories, 1617.5 * 1.4 + 400 + 800, accuracy: 0.001)
        XCTAssertEqual(combined.components?.activity, .selected(400))
        XCTAssertEqual(combined.components?.trainingKilocalories, 800)
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
        XCTAssertEqual(updated.outcomes[day]?.estimate?.factor, ResidualEnergyCoefficient.initialFallback)
        XCTAssertEqual(updated.outcomes[day]?.estimate?.totalKilocalories ?? 0, 1617.5 * 1.4, accuracy: 0.001)
        XCTAssertNil(updated.calculations[day]?.input.reference.walkingKilometers)
        profile.energyFacts.contexts = []
        let removed = EnergyRuntimeProjection.build(window: ProgressPeriod.day.window(containing: day, calendar: calendar), records: [weight],
                                                    profile: profile, now: day, calendar: calendar)
        XCTAssertEqual(removed.calculations[day]?.input.reference.factor, 1.4)
        XCTAssertNotEqual(removed.calculations[day]?.input.reference.id, life.id)
    }

    func testAddingEditingAndDeletingTrainingRefreshesThePresentedTotal() throws {
        let daily = ProgressHistoryRecord(
            activity: .init(id: UUID(), kind: .workout, date: day, title: "日常活动", detail: "", metric: nil),
            calories: 300, activeEnergyKilocalories: 300, isDailyActivity: true, dailyActivitySource: .appleHealth
        )
        var first = ProgressHistoryRecord(
            activity: .init(id: UUID(), kind: .workout, date: day, title: "虚构训练甲", detail: "", metric: nil),
            calories: 80
        )
        let second = ProgressHistoryRecord(
            activity: .init(id: UUID(), kind: .workout, date: day, title: "虚构训练乙", detail: "", metric: nil),
            calories: 90
        )
        func total(for records: [ProgressHistoryRecord]) throws -> (Double, Double) {
            let snapshot = ProgressHistoryProjection.build(
                window: ProgressPeriod.day.window(containing: day, calendar: calendar),
                records: records, profile: profile, now: day.addingTimeInterval(86400), calendar: calendar
            )
            let estimate = try XCTUnwrap(snapshot.days.first { $0.date == day }?.energy.estimate)
            return try (XCTUnwrap(estimate.totalKilocalories), estimate.components?.trainingKilocalories ?? -1)
        }
        let baseline = 1617.5 * 1.4 + 300
        let added = try total(for: [weight, daily, first, second])
        XCTAssertEqual(added.0, baseline + 80 + 90, accuracy: 0.001)
        XCTAssertEqual(added.1, 170, accuracy: 0.001)
        first.calories = 120
        let edited = try total(for: [weight, daily, first, second])
        XCTAssertEqual(edited.0, baseline + 120 + 90, accuracy: 0.001)
        XCTAssertEqual(edited.1, 210, accuracy: 0.001)
        let deleted = try total(for: [weight, daily, first])
        XCTAssertEqual(deleted.0, baseline + 120, accuracy: 0.001)
        XCTAssertEqual(deleted.1, 120, accuracy: 0.001)
        let empty = try total(for: [weight, daily])
        XCTAssertEqual(empty.0, baseline, accuracy: 0.001)
        XCTAssertEqual(empty.1, 0, accuracy: 0.001)
    }
}
