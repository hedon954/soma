@testable import Soma
import XCTest

final class ProgressEnergyDeficitTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testDayUsesEstimatedExpenditureWithListTrainingCalories() throws {
        let facts = snapshot(.day, [meal(10, 2000), record(10, .workout, calories: 500, met: 5)])
        let result = try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: facts))
        XCTAssertEqual(try XCTUnwrap(result.kilocalories), 1617.5 * 1.4 + 500 - 2000, accuracy: 0.001)
        XCTAssertEqual(result.includedDayCount, 1)
        XCTAssertEqual(facts.days.first?.trainingCalories.value, 500)
        XCTAssertEqual(facts.days.first?.estimatedEnergyDeficit, result.kilocalories)
    }

    func testMissingAndPartialIntakeNeverBecomeZeroButExplicitZeroIsValid() throws {
        for meals in [[], [meal(10, nil)], [meal(10, 100, partial: true)], [meal(10, 100), meal(10, nil)]] {
            let facts = snapshot(.day, meals)
            XCTAssertNil(facts.days.first?.estimatedEnergyDeficit)
            XCTAssertNil(try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: facts)).kilocalories)
            XCTAssertNotNil(facts.days.first?.energyDeficitMissingReason)
        }
        let result = try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: snapshot(.day, [meal(10, 0)])))
        XCTAssertEqual(try XCTUnwrap(result.kilocalories), 2264.5, accuracy: 0.001)
    }

    func testUnconfirmedFoodOnlyShowsRecordedDifferenceAndIsExcludedFromPeriodTotal() throws {
        let day = snapshot(.day, [meal(10, 1200)], confirmsFood: false)
        XCTAssertNil(day.days.first?.estimatedEnergyDeficit)
        XCTAssertEqual(day.days.first?.recordedEnergyDifference, 1064.5)
        let caption = try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: day))
        XCTAssertEqual(caption.metricLabel, "已记饮食差额")
        XCTAssertTrue(caption.detail.contains("尚未确认饮食完整"))
        let period = snapshot(.week, [meal(9, 1200)], confirmsFood: false)
        XCTAssertNil(try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: period)).kilocalories)
    }

    func testWeekAndMonthSumSameDayPairsAndExcludeTodayFutureAndUnmatchedDays() throws {
        for period in [ProgressPeriod.week, .month] {
            // 静息所需体重直到 8 日才存在；7 日只有摄入，9 日只有消耗。
            let facts = snapshot(period, [meal(7, 1000), meal(8, 2000), meal(10, 100), meal(11, 9000)], weightDay: 8)
            let result = try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: facts))
            XCTAssertEqual(try XCTUnwrap(result.kilocalories), 264.5, accuracy: 0.001)
            XCTAssertEqual(result.includedDayCount, 1)
            XCTAssertEqual(result.eligibleDayCount, period == .week ? 3 : 9)
            XCTAssertTrue(result.detail.contains("截至昨日"))
        }
    }

    func testSurplusOffsetsDeficitAndKeepsNegativeSign() throws {
        let result = try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: snapshot(.week, [meal(8, 2000), meal(9, 3000)])))
        XCTAssertEqual(try XCTUnwrap(result.kilocalories), -471, accuracy: 0.001)
        XCTAssertEqual(result.includedDayCount, 2)
        XCTAssertTrue(result.valueText.contains("−"))
        XCTAssertTrue(result.accessibilityValue.contains("盈余"))
        let balanced = try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: snapshot(.day, [meal(10, 2264.5)])))
        XCTAssertEqual(balanced.kilocalories, 0)
        XCTAssertFalse(balanced.valueText.contains("−"))
    }

    func testNoEstimateNoCompletedDaysAndFutureStayUnavailable() throws {
        let noProfile = snapshot(.day, [meal(10, 2000)], hasProfile: false)
        XCTAssertNil(try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: noProfile)).kilocalories)
        XCTAssertEqual(noProfile.days.first?.energyDeficitMissingReason, "缺少消耗估算")
        let monday = snapshot(.week, [meal(7, 2000)], now: date(7, hour: 12))
        let empty = try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: monday))
        XCTAssertNil(empty.kilocalories)
        XCTAssertEqual(empty.eligibleDayCount, 0)
        XCTAssertEqual(empty.detail, "暂无已结束日期")
        let future = snapshot(.day, [meal(11, 2000)], anchor: date(11))
        XCTAssertNil(future.days.first?.estimatedEnergyDeficit)
        XCTAssertNil(try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: future)).kilocalories)
        XCTAssertNil(ProgressEnergyDeficit.make(snapshot: snapshot(.year, [meal(10, 2000)])))
    }

    func testHistoricalMonthUsesItsOwnDatesAndDoesNotClaimYesterday() throws {
        let facts = snapshot(.month, [meal(8, 2000), meal(9, 2000)], now: date(1, month: 10))
        let result = try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: facts))
        XCTAssertEqual(result.eligibleDayCount, 30)
        XCTAssertEqual(result.includedDayCount, 2)
        XCTAssertEqual(try XCTUnwrap(result.kilocalories), 529, accuracy: 0.001)
        XCTAssertFalse(result.detail.contains("截至昨日"))
    }

    func testCaptionDistinguishesExpenditureDeficitFromGoalAdjustedRemainingIntake() throws {
        let loss = try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: snapshot(.day, [meal(10, 1800)], goal: .fatLoss)))
        XCTAssertEqual(try XCTUnwrap(loss.kilocalories), 464.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(loss.remainingIntakeKilocalories), 64.5, accuracy: 0.001)
        XCTAssertTrue(loss.accessibilityValue.contains("仍可摄入 65 千卡"))

        let gain = try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: snapshot(.day, [meal(10, 2400)], goal: .muscleGain)))
        XCTAssertEqual(try XCTUnwrap(gain.kilocalories), -135.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(gain.remainingIntakeKilocalories), 114.5, accuracy: 0.001)
    }

    func testRemainingIntakeClampsAtZeroAndDoesNotInventAnAllowanceForMissingOrPeriodData() throws {
        let over = try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: snapshot(.day, [meal(10, 3000)])))
        XCTAssertEqual(over.remainingIntakeKilocalories, 0)
        XCTAssertTrue(over.accessibilityValue.contains("仍可摄入 0 千卡"))
        for records in [[], [meal(10, 100, partial: true)]] {
            XCTAssertNil(try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: snapshot(.day, records))).remainingIntakeKilocalories)
        }
        for period in [ProgressPeriod.week, .month] {
            XCTAssertNil(try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: snapshot(period, [meal(9, 1000)]))).remainingIntakeKilocalories)
        }
    }

    func testCustomTargetFlowsThroughProjectionWithoutChangingExpenditureOrActualDeficit() throws {
        for goal in [FitnessGoal.fatLoss, .recomposition] {
            let original = snapshot(.day, [meal(10, 1000)], goal: goal)
            let custom = snapshot(.day, [meal(10, 1000)], goal: goal, targetDeficit: 600)
            XCTAssertEqual(custom.averageEstimate, original.averageEstimate)
            XCTAssertEqual(custom.nutritionRings?.calories.target, (original.nutritionRings?.calories.target ?? 0) - 200)
            let first = try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: original))
            let second = try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: custom))
            XCTAssertEqual(second.kilocalories, first.kilocalories)
            XCTAssertEqual(second.remainingIntakeKilocalories, (first.remainingIntakeKilocalories ?? 0) - 200)
            let clamped = try XCTUnwrap(ProgressEnergyDeficit.make(snapshot: snapshot(
                .day, [meal(10, 1000)], goal: goal, targetDeficit: 3000
            )))
            XCTAssertEqual(clamped.remainingIntakeKilocalories, 0)
        }
    }

    private func snapshot(
        _ period: ProgressPeriod, _ records: [ProgressHistoryRecord],
        weightDay: Int? = nil, hasProfile: Bool = true, now: Date? = nil, anchor: Date? = nil, goal: FitnessGoal? = nil,
        confirmsFood: Bool = true, targetDeficit: Double? = nil
    ) -> ProgressHistorySnapshot {
        let weightDate = weightDay.map { date($0) } ?? date(30, month: 8)
        let weight = ProgressHistoryRecord(activity: .init(id: UUID(), kind: .body, date: weightDate,
                                                           title: "虚构体重", detail: "", metric: nil), weight: 70)
        var profile = ProgressProfileFacts(updatedAt: date(1, month: 8),
                                           birthDate: calendar.date(from: DateComponents(year: 1996, month: 1, day: 1)),
                                           height: 170, biologicalSex: .male, baselines: [], fitnessGoal: goal)
        profile.dailyTargetDeficitKilocalories = targetDeficit
        if confirmsFood {
            let meals = Dictionary(grouping: records.filter { $0.activity.kind == .meal }) { calendar.startOfDay(for: $0.activity.date) }
            profile.energyFacts.contexts = meals.map { day, records in
                .init(date: day, timeZoneIdentifier: calendar.timeZone.identifier, lifestyle: nil,
                      confirmation: .init(foodComplete: true, mealEvidenceFingerprint: EnergyFoodEvidence.fingerprint(records: records)), learningPaused: nil)
            }
        }
        return ProgressHistoryProjection.build(
            window: period.window(containing: anchor ?? date(10), calendar: calendar), records: records + [weight],
            profile: hasProfile ? profile : nil, now: now ?? date(10, hour: 12), calendar: calendar
        )
    }

    private func meal(_ day: Int, _ calories: Double?, partial: Bool = false) -> ProgressHistoryRecord {
        var value = record(day, .meal, calories: calories)
        value.caloriesArePartial = partial
        return value
    }

    private func record(_ day: Int, _ kind: ProgressRecentActivity.Kind, calories: Double?, met: Double? = nil) -> ProgressHistoryRecord {
        .init(activity: .init(id: UUID(), kind: kind, date: date(day), title: "虚构记录", detail: "", metric: nil),
              calories: calories, calorieMET: met, durationSeconds: met == nil ? nil : 3600)
    }

    private func date(_ day: Int, month: Int = 9, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
}
