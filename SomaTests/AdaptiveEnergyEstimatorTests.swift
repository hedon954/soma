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

    func testCoefficientComesFromTheProviderAndIsNotInlinedInTheTotal() {
        let fallback = ResidualEnergyCoefficient.current()
        XCTAssertEqual(fallback.value, ResidualEnergyCoefficient.initialFallback)
        XCTAssertEqual(fallback.value, 1.4)
        let low = AdaptiveEnergyEstimator.estimate(
            for: target, now: target, restingEstimate: 1700, coefficient: fallback, calendar: calendar
        )
        let high = AdaptiveEnergyEstimator.estimate(
            for: target, now: target, restingEstimate: 1700,
            coefficient: .init(value: 1.8), calendar: calendar
        )
        XCTAssertEqual(low.estimate?.totalKilocalories ?? 0, 1700 * ResidualEnergyCoefficient.initialFallback, accuracy: 0.0001)
        XCTAssertEqual(low.estimate?.method, .defaultReference)
        XCTAssertEqual(
            (high.estimate?.totalKilocalories ?? 0) - (low.estimate?.totalKilocalories ?? 0),
            1700 * 0.4,
            accuracy: 0.0001
        )
        XCTAssertNil(
            AdaptiveEnergyEstimator.estimate(
                for: target, now: target, restingEstimate: 1700,
                coefficient: .init(value: 9), calendar: calendar
            ).estimate
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
