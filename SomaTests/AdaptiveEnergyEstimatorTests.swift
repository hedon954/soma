@testable import Soma
import XCTest

final class AdaptiveEnergyEstimatorTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var target: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
    }

    func testDynamicFactorUsesCompletedHistoryAndSameSourceResting() throws {
        let result = evaluate(history: history(active: 800))
        let estimate = try XCTUnwrap(result.estimate)
        XCTAssertEqual(estimate.method, .deviceHistory)
        XCTAssertEqual(estimate.factor, 1.5, accuracy: 0.0001)
        XCTAssertEqual(estimate.restingKilocalories, 1600)
        XCTAssertEqual(estimate.totalKilocalories, 2400)
        XCTAssertEqual(estimate.evidenceDays.count, 30)
        XCTAssertEqual(evaluate(history: history(active: 400)).estimate?.totalKilocalories, 2000)
    }

    func testTodayFutureAndOutOfWindowEvidenceCannotInfluenceResult() {
        var days = history(active: 400)
        days += [day(offset: 0, active: 9000), day(offset: 1, active: 9000), day(offset: -31, active: 9000)]
        XCTAssertEqual(evaluate(history: days), evaluate(history: history(active: 400)))
    }

    func testInsufficientCoverageAndMissingActiveDoNotBecomeZeroCalibration() {
        let days = (-30 ..< 0).map { day(offset: $0, active: $0 < -10 ? nil : 800, coverage: 0.8) }
        XCTAssertNil(evaluate(history: days).estimate)
        XCTAssertEqual(evaluate(history: days).eligibleDayCount, 0)
        XCTAssertEqual(evaluate(history: history(active: 0)).estimate?.factor, 1)
    }

    func testDoesNotCombineSourcesToMeetCoverageThreshold() {
        let days = (-30 ..< 0).map { day(offset: $0, active: 800, source: $0 < -15 ? "watch-a" : "watch-b") }
        XCTAssertNil(evaluate(history: days).estimate)
        XCTAssertEqual(evaluate(history: days).eligibleDayCount, 15)
    }

    func testReplayDuplicatesDoNotIncreaseValidDayCount() {
        let days = history(active: 800)
        XCTAssertEqual(evaluate(history: days + days), evaluate(history: days))
    }

    func testConflictingDuplicatesAreExcludedNotAdded() {
        let days = history(active: 800) + (-30 ..< -20).map { day(offset: $0, active: 900) }
        XCTAssertEqual(evaluate(history: days).eligibleDayCount, 20)
        XCTAssertNil(evaluate(history: days).estimate)
    }

    func testManualReferenceIsExplicitDatedAndNeverUsesFutureBaseline() {
        let past = EnergyLifestyleBaseline(effectiveFrom: target.addingTimeInterval(-86400), factor: 1.4, label: "本人确认")
        let future = EnergyLifestyleBaseline(effectiveFrom: target.addingTimeInterval(86400), factor: 2, label: "未来设置")
        let result = AdaptiveEnergyEstimator.estimate(
            for: target, now: target, history: [], restingEstimate: 1700,
            baselines: [future, past], calendar: calendar
        )
        XCTAssertEqual(result.estimate?.totalKilocalories ?? 0, 2380, accuracy: 0.0001)
        XCTAssertEqual(result.estimate?.method, .confirmedLifestyle)
        XCTAssertNil(AdaptiveEnergyEstimator.estimate(
            for: target, now: target, history: [], restingEstimate: 1700, baselines: [future], calendar: calendar
        ).estimate)
    }

    func testFutureDayAndNonfiniteValuesNeverYieldForecast() {
        XCTAssertNil(AdaptiveEnergyEstimator.estimate(
            for: target.addingTimeInterval(86400), now: target, history: history(active: 800), restingEstimate: 1700, calendar: calendar
        ).estimate)
        XCTAssertNil(evaluate(history: history(active: .infinity)).estimate)
        XCTAssertNil(evaluate(history: history(active: -.infinity)).estimate)
    }

    func testProductWindowCanBeEvaluatedAt28And30Days() {
        let days = history(active: 800)
        let result = AdaptiveEnergyEstimator.estimate(
            for: target, now: target, history: days, restingEstimate: nil, calendar: calendar,
            policy: AdaptiveEnergyPolicy(lookbackDays: 28)
        )
        XCTAssertEqual(result.estimate?.evidenceDays.count, 28)
        XCTAssertEqual(result.estimate?.totalKilocalories, evaluate(history: days).estimate?.totalKilocalories)
    }

    private func evaluate(history: [EnergyHistoryDay]) -> AdaptiveEnergyOutcome {
        AdaptiveEnergyEstimator.estimate(for: target, now: target, history: history, restingEstimate: 1700, calendar: calendar)
    }

    private func history(active: Double?) -> [EnergyHistoryDay] {
        (-30 ..< 0).map { day(offset: $0, active: active) }
    }

    private func day(offset: Int, active: Double?, coverage: Double = 1, source: String = "watch") -> EnergyHistoryDay {
        EnergyHistoryDay(
            date: calendar.date(byAdding: .day, value: offset, to: target)!,
            restingKilocalories: 1600, activeKilocalories: active, sourceID: source, sourceName: source, coverage: coverage
        )
    }
}
