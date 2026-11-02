@testable import Soma
import XCTest

final class EnergyCalibrationTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
    }

    private func window(
        ending end: Date? = nil, intake: Double = 2400, incompleteDay: Int? = nil,
        activityMissing: Bool = false, fluid: Bool = false, onlyOneWeight: Bool = false
    ) -> [EnergyCalibrationDay] {
        (0 ..< 28).map { index in
            .init(date: calendar.date(byAdding: .day, value: index - 28, to: end ?? today)!,
                  intake: intake, uncalibratedTotal: 2200, foodComplete: incompleteDay != index,
                  activityComplete: !activityMissing, weights: onlyOneWeight && index != 0 ? [] : [70, 70, 70], fluidChangeConcern: fluid)
        }
    }

    private func first(intake: Double = 2400) -> EnergyCalibrationReview {
        let before = calendar.date(byAdding: .day, value: -7, to: today)!
        return EnergyCalibration.evaluate(days: window(ending: before, intake: intake), on: before, correction: 0, resting: 1600,
                                          fingerprint: "fixture-before", previous: nil, lastApplied: nil, calendar: calendar)
    }

    func testStableWeightNeedsTwoWeeksAndAppliesQuarterResidual() {
        let previous = first()
        XCTAssertTrue(previous.evidenceEligible)
        XCTAssertEqual(previous.delta, 0)
        let result = EnergyCalibration.evaluate(days: window(), on: today, correction: 0, resting: 1600,
                                                fingerprint: "fixture-current", previous: previous, lastApplied: nil, calendar: calendar)
        XCTAssertEqual(result.minimumCandidate, 200)
        XCTAssertEqual(result.maximumCandidate, 200)
        XCTAssertEqual(result.slope, 0)
        XCTAssertEqual(result.nextCorrection, 50)
        XCTAssertEqual(result.weightDayCount, 28)
    }

    func testMissingFoodIsNotDeletedFromWindowToForceLearning() {
        let result = EnergyCalibration.evaluate(days: window(incompleteDay: 7), on: today, correction: 25, resting: 1600,
                                                fingerprint: "fixture", previous: first(), lastApplied: nil, calendar: calendar)
        XCTAssertFalse(result.evidenceEligible)
        XCTAssertEqual(result.nextCorrection, 25)
    }

    func testNoCalibrationWithUnexplainedActivityOrFluidChange() {
        for days in [window(activityMissing: true), window(fluid: true), window(onlyOneWeight: true), Array(window().dropLast())] {
            let result = EnergyCalibration.evaluate(days: days, on: today, correction: 0, resting: 1600,
                                                    fingerprint: "fixture", previous: first(), lastApplied: nil, calendar: calendar)
            XCTAssertFalse(result.evidenceEligible)
            XCTAssertEqual(result.delta, 0)
        }
    }

    func testSameDayWeightsOrDuplicateDaysCannotSatisfyDifferentDayThreshold() {
        let days = Array(repeating: window()[0], count: 28)
        let result = EnergyCalibration.evaluate(days: days, on: today, correction: 0, resting: 1600,
                                                fingerprint: "fixture", previous: first(), lastApplied: nil, calendar: calendar)
        XCTAssertFalse(result.evidenceEligible)
    }

    func testNegativeResidualAndAbsoluteTargetPreventFullErrorAccumulation() {
        let negative = EnergyCalibration.evaluate(days: window(intake: 2000), on: today, correction: 0, resting: 1600,
                                                  fingerprint: "negative", previous: first(intake: 2000), lastApplied: nil, calendar: calendar)
        XCTAssertEqual(negative.delta, -50)
        let updated = EnergyCalibration.evaluate(days: window(), on: today, correction: 50, resting: 1600,
                                                 fingerprint: "updated", previous: first(), lastApplied: nil, calendar: calendar)
        XCTAssertEqual(updated.delta, 37.5)
    }

    func testRepeatedWindowAndWeeklyLimitPreventRepeatedApplication() {
        let applied = EnergyCalibration.evaluate(days: window(), on: today, correction: 0, resting: 1600,
                                                 fingerprint: "same", previous: first(), lastApplied: nil, calendar: calendar)
        let repeatReview = EnergyCalibration.evaluate(days: window(), on: today, correction: 50, resting: 1600,
                                                      fingerprint: "same", previous: first(), lastApplied: applied, calendar: calendar)
        XCTAssertEqual(repeatReview.delta, 0)
    }

    func testSmallResidualAndSaturatedCorrectionHold() {
        for (intake, correction) in [(2250.0, 0.0), (3000, 300)] {
            let result = EnergyCalibration.evaluate(days: window(intake: intake), on: today, correction: correction, resting: 1600,
                                                    fingerprint: "fixture", previous: first(intake: intake), lastApplied: nil, calendar: calendar)
            XCTAssertEqual(result.delta, 0)
        }
    }
}
