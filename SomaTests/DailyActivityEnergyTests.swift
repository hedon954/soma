import Foundation
@testable import Soma
import XCTest

final class DailyActivityEnergyTests: XCTestCase {
    func testRecordedActiveEnergyDoesNotCancelLifestyleOrAddADuplicateReward() {
        let outcome = AdaptiveEnergyEstimator.estimate(for: .now, restingEstimate: 1500, trainingNetKilocalories: 700, activeEnergyKilocalories: 450)
        XCTAssertEqual(outcome.estimate?.method, .defaultReference)
        XCTAssertEqual(outcome.estimate?.totalKilocalories, 2800)
        XCTAssertEqual(outcome.estimate?.trainingNetKilocalories, 700)
        XCTAssertEqual(outcome.estimate?.factor, 1.4)
        let zero = AdaptiveEnergyEstimator.estimate(for: .now, restingEstimate: 1500, trainingNetKilocalories: 700, activeEnergyKilocalories: 0)
        XCTAssertEqual(zero.estimate?.totalKilocalories, 2800)
        let fallback = AdaptiveEnergyEstimator.estimate(for: .now, restingEstimate: 1500, trainingNetKilocalories: 700)
        XCTAssertEqual(fallback.estimate?.totalKilocalories, 2800)
        XCTAssertNil(AdaptiveEnergyEstimator.estimate(for: .now, restingEstimate: nil, activeEnergyKilocalories: 450).estimate)
    }

    func testRecordChangesEnergyDeficitTargetsAndPeriodChart() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))
        let now = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        let weight = ProgressHistoryRecord(activity: .init(id: UUID(), kind: .body, date: day, title: "虚构体重", detail: "", metric: nil), weight: 70)
        let meal = ProgressHistoryRecord(activity: .init(id: UUID(), kind: .meal, date: day, title: "虚构餐食", detail: "", metric: nil), calories: 1200)
        let activity = ProgressHistoryRecord(
            activity: .init(id: UUID(), kind: .workout, date: day, title: "日常活动", detail: "", metric: nil),
            calories: 450, activeEnergyKilocalories: 450
        )
        let training = ProgressHistoryRecord(activity: .init(id: UUID(), kind: .workout, date: day, title: "虚构训练", detail: "", metric: nil),
                                             calories: 800, calorieMET: 5, durationSeconds: 3600)
        var profile = ProgressProfileFacts(
            updatedAt: day, birthDate: calendar.date(from: DateComponents(year: 1996, month: 1, day: 1)),
            height: 170, biologicalSex: .male, baselines: [], fitnessGoal: .fatLoss
        )
        profile.energyFacts.contexts = [.init(date: day, timeZoneIdentifier: calendar.timeZone.identifier, lifestyle: nil,
                                              confirmation: .init(foodComplete: true, mealEvidenceFingerprint: EnergyFoodEvidence.fingerprint(records: [meal])),
                                              learningPaused: nil)]
        let resting = 700.0 + 1062.5 - 150 + 5
        let expected = resting * 1.4 + 640 - (resting * 1.4 * 0.9 - resting) / 16
        for period in [ProgressPeriod.day, .week, .month, .year] {
            let snapshot = ProgressHistoryProjection.build(
                window: period.window(containing: day, calendar: calendar), records: [weight, meal, activity, training],
                profile: profile, now: now, calendar: calendar
            )
            let actual = try XCTUnwrap(snapshot.days.first { $0.date == day })
            XCTAssertEqual(try XCTUnwrap(actual.energy.estimate?.totalKilocalories), expected, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(actual.estimatedEnergyDeficit), expected - 1200, accuracy: 0.001)
            XCTAssertEqual(actual.trainingCalories.value, 450)
            if period == .day {
                XCTAssertEqual(try XCTUnwrap(snapshot.nutritionRings?.calories.target), expected - 400, accuracy: 0.001)
            }
        }
    }
}
