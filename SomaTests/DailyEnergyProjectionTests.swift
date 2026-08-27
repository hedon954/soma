@testable import Soma
import XCTest

final class DailyEnergyProjectionTests: XCTestCase {
    func testHealthProjectionUsesActualEnergyAndElapsedDay() throws {
        let (calendar, midday) = try middayFixture()

        let result = try XCTUnwrap(DailyEnergyProjectionCalculator.estimate(
            restingKilocaloriesSoFar: 800,
            dailyRestingEstimate: nil,
            restingUsesHealth: true,
            activeKilocaloriesSoFar: 300,
            now: midday,
            calendar: calendar
        ))

        XCTAssertEqual(result.elapsedDayFraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.projectedRestingKilocalories, 1600)
        XCTAssertEqual(result.projectedActiveKilocalories, 600)
        XCTAssertEqual(result.dailyTotalKilocalories, 2200)
        XCTAssertEqual(result.substitutedFormula, "（800 + 300）÷ 50% = 2200 kcal")
    }

    func testProfileProjectionKeepsDailyRestingAndProjectsActivity() throws {
        let (calendar, midday) = try middayFixture()

        let result = try XCTUnwrap(DailyEnergyProjectionCalculator.estimate(
            restingKilocaloriesSoFar: 800,
            dailyRestingEstimate: 1600,
            restingUsesHealth: false,
            activeKilocaloriesSoFar: 300,
            now: midday,
            calendar: calendar
        ))

        XCTAssertEqual(result.projectedRestingKilocalories, 1600)
        XCTAssertEqual(result.projectedActiveKilocalories, 600)
        XCTAssertEqual(result.dailyTotalKilocalories, 2200)
        XCTAssertEqual(result.substitutedFormula, "1600 + 300 ÷ 50% = 2200 kcal")
    }

    func testProjectionDoesNotTreatMissingActivityAsZero() throws {
        let (calendar, midday) = try middayFixture()

        XCTAssertNil(DailyEnergyProjectionCalculator.estimate(
            restingKilocaloriesSoFar: 800,
            dailyRestingEstimate: 1600,
            restingUsesHealth: false,
            activeKilocaloriesSoFar: nil,
            now: midday,
            calendar: calendar
        ))
    }

    private func middayFixture() throws -> (Calendar, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let midday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 27,
            hour: 12
        )))
        return (calendar, midday)
    }
}
