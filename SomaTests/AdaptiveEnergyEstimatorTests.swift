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

    func testRestingEstimateWithoutManualSettingsStillProducesDefaultEstimate() throws {
        let result = AdaptiveEnergyEstimator.estimate(
            for: target, now: target, restingEstimate: 1700, calendar: calendar
        )
        let estimate = try XCTUnwrap(result.estimate)
        XCTAssertEqual(estimate.method, .defaultReference)
        XCTAssertEqual(estimate.factor, 1.4)
        XCTAssertEqual(estimate.totalKilocalories, 2380, accuracy: 0.001)
        XCTAssertNil(result.missingReason)
    }

    func testManualReferenceIsExplicitDatedAndNeverUsesFutureBaseline() {
        let past = EnergyLifestyleBaseline(
            effectiveFrom: target.addingTimeInterval(-86400), factor: 1.4, label: "本人确认"
        )
        let future = EnergyLifestyleBaseline(
            effectiveFrom: target.addingTimeInterval(86400), factor: 2, label: "未来设置"
        )
        let result = AdaptiveEnergyEstimator.estimate(
            for: target, now: target, restingEstimate: 1700,
            baselines: [future, past], calendar: calendar
        )
        XCTAssertEqual(result.estimate?.totalKilocalories ?? 0, 2380, accuracy: 0.0001)
        XCTAssertEqual(result.estimate?.method, .confirmedLifestyle)
        XCTAssertEqual(
            AdaptiveEnergyEstimator.estimate(
                for: target, now: target, restingEstimate: 1700, baselines: [future], calendar: calendar
            ).estimate?.method,
            .defaultReference
        )
    }

    func testFutureDayNeverYieldsForecast() {
        XCTAssertNil(
            AdaptiveEnergyEstimator.estimate(
                for: target.addingTimeInterval(86400), now: target, restingEstimate: 1700, calendar: calendar
            ).estimate
        )
    }

    func testMissingOrInvalidRestingNeverCreatesEnergy() {
        for resting in [nil, 0, -1, Double.nan, .infinity, -.infinity] as [Double?] {
            XCTAssertNil(
                AdaptiveEnergyEstimator.estimate(
                    for: target, now: target, restingEstimate: resting, calendar: calendar
                ).estimate
            )
        }
    }
}
