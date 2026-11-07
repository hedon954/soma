import Foundation
@testable import Soma
import XCTest

final class DailyActivityEnergyTests: XCTestCase {
    func testSameRestingAndCoefficientChangeTotalByTheActiveEnergyDifference() {
        let low = AdaptiveEnergyEstimator.estimate(for: .now, restingEstimate: 1500, activeEnergyKilocalories: 100)
        let high = AdaptiveEnergyEstimator.estimate(for: .now, restingEstimate: 1500, activeEnergyKilocalories: 400)
        XCTAssertEqual(low.estimate?.factor, ResidualEnergyCoefficient.initialFallback)
        XCTAssertEqual(high.estimate?.factor, low.estimate?.factor)
        XCTAssertEqual(low.estimate?.totalKilocalories, 1500 * 1.4 + 100)
        XCTAssertEqual((high.estimate?.totalKilocalories ?? 0) - (low.estimate?.totalKilocalories ?? 0), 300)
    }

    func testSelectedActiveEnergyKeepsTheCoefficientAndDoesNotAddTrainingAgain() {
        let outcome = AdaptiveEnergyEstimator.estimate(
            for: .now, restingEstimate: 1500, trainingNetKilocalories: 700, activeEnergyKilocalories: 450
        )
        XCTAssertEqual(outcome.estimate?.method, .defaultReference)
        XCTAssertEqual(outcome.estimate?.factor, 1.4)
        XCTAssertEqual(outcome.estimate?.totalKilocalories, 1500 * 1.4 + 450)
        XCTAssertEqual(outcome.estimate?.components?.baselineExtraKilocalories ?? 0, 600, accuracy: 0.001)
        XCTAssertEqual(outcome.estimate?.components?.activityKilocalories, 450)
        XCTAssertEqual(outcome.estimate?.components?.componentsAddUp, true)
        let zero = AdaptiveEnergyEstimator.estimate(
            for: .now, restingEstimate: 1500, trainingNetKilocalories: 700, activeEnergyKilocalories: 0
        )
        XCTAssertEqual(zero.estimate?.totalKilocalories, 1500 * 1.4)
        XCTAssertEqual(zero.estimate?.components?.activity, .selected(0))
        let missing = AdaptiveEnergyEstimator.estimate(for: .now, restingEstimate: 1500, trainingNetKilocalories: 700)
        XCTAssertEqual(missing.estimate?.totalKilocalories, 1500 * 1.4 + 700)
        XCTAssertEqual(missing.estimate?.components?.activity, .recordedTraining(700))
        XCTAssertNil(missing.estimate?.activeEnergyKilocalories)
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
        // 450 不是日活动整包，是这条训练自己的活动能量；800 MET 5 是另一条训练的净活动能量 640。两者都计入，不互相覆盖。
        let expected = resting * ResidualEnergyCoefficient.initialFallback + 450 + 800 * (5 - 1) / 5
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
        var dailyActivity = activity
        dailyActivity.isDailyActivity = true
        let packaged = ProgressHistoryProjection.build(
            window: ProgressPeriod.day.window(containing: day, calendar: calendar),
            records: [weight, meal, dailyActivity, training], profile: profile, now: now, calendar: calendar
        )
        let packagedTotal = try XCTUnwrap(packaged.days.first { $0.date == day }?.energy.estimate?.totalKilocalories)
        XCTAssertEqual(packagedTotal, resting * ResidualEnergyCoefficient.initialFallback + 450, accuracy: 0.001)
        XCTAssertEqual(expected - packagedTotal, 640, accuracy: 0.001)
    }
}
