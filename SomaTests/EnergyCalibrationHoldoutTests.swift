@testable import Soma
import XCTest

/// Synthetic control validation. This does not establish individual physiological accuracy.
final class EnergyCalibrationHoldoutTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 1_767_225_600))!
    }

    private func replay(foodComplete: Bool = true, activityShift: Bool = true) throws -> [EnergyCalibrationReview] {
        var reviews: [EnergyCalibrationReview] = []
        var correction = 0.0
        for index in stride(from: 28, through: 84, by: 7) {
            let window = (index - 28 ..< index).map { day in
                let extra = activityShift && day >= 56 ? 400.0 : 0
                return EnergyCalibrationDay(date: date(day), intake: 2400 + extra, uncalibratedTotal: 2200 + extra,
                                            foodComplete: foodComplete, activityComplete: true, weights: [70], fluidChangeConcern: false)
            }
            let review = try EnergyCalibration.evaluate(
                days: window, on: date(index), correction: correction, resting: 1600,
                fingerprint: EnergyInputCoding.digest(EnergyInputCoding.encode(window)), previous: reviews.last,
                lastApplied: reviews.last { $0.delta != 0 }, calendar: calendar
            )
            reviews.append(review)
            correction = review.nextCorrection
        }
        return reviews
    }

    func testIndependentFutureActivityShiftDoesNotBecomeExtraMetabolicCorrection() throws {
        let control = try replay(activityShift: false), shifted = try replay()
        XCTAssertEqual(control.map(\.nextCorrection), shifted.map(\.nextCorrection))
        let before = try XCTUnwrap(shifted.first { $0.date == date(56) })
        let heldOut = try XCTUnwrap(shifted.last)
        XCTAssertEqual(before.nextCorrection, heldOut.nextCorrection)
        XCTAssertLessThan(abs(2600 + heldOut.nextCorrection - 2800), 100)
        XCTAssertTrue(shifted.allSatisfy { abs($0.delta) <= 75 })
    }

    func testIncompleteFoodNeverTurnsIntoAnInferredLowMetabolism() throws {
        let reviews = try replay(foodComplete: false)
        XCTAssertTrue(reviews.allSatisfy { !$0.evidenceEligible && $0.nextCorrection == 0 })
    }

    func testChangingWeightDoesNotForceTheNominal7700EstimateWhenHypothesesDisagree() throws {
        let window = (0 ..< 28).map { index in
            EnergyCalibrationDay(date: date(index), intake: 2000, uncalibratedTotal: 2200, foodComplete: true,
                                 activityComplete: true, weights: [70 - Double(index) * 400 / 7700], fluidChangeConcern: false)
        }
        let result = EnergyCalibration.evaluate(days: window, on: date(28), correction: 0, resting: 1600,
                                                fingerprint: "synthetic-weight-loss", previous: nil, lastApplied: nil, calendar: calendar)
        XCTAssertLessThan(try XCTUnwrap(result.minimumCandidate), 0)
        XCTAssertGreaterThan(try XCTUnwrap(result.maximumCandidate), 0)
        XCTAssertEqual(result.nextCorrection, 0)
    }

    func testExplicitFluidConcernBlocksAWeightStepRegardlessOfNominalEnergyBalance() {
        let window = (0 ..< 28).map { index in
            EnergyCalibrationDay(date: date(index), intake: 2200, uncalibratedTotal: 2200, foodComplete: true,
                                 activityComplete: true, weights: [index < 14 ? 70 : 69], fluidChangeConcern: index >= 14)
        }
        let result = EnergyCalibration.evaluate(days: window, on: date(28), correction: 0, resting: 1600,
                                                fingerprint: "synthetic-water-step", previous: nil, lastApplied: nil, calendar: calendar)
        XCTAssertFalse(result.evidenceEligible)
        XCTAssertEqual(result.delta, 0)
    }

    func testPersistentUnderreportingCannotDriveUnboundedCorrection() throws {
        // Claimed completeness cannot identify systematic underreporting; validate the control limit, not physiological accuracy.
        var reviews: [EnergyCalibrationReview] = []
        var correction = 0.0
        for index in stride(from: 28, through: 140, by: 7) {
            let days = (index - 28 ..< index).map { offset in
                EnergyCalibrationDay(date: date(offset), intake: 1800, uncalibratedTotal: 2400, foodComplete: true,
                                     activityComplete: true, weights: [70], fluidChangeConcern: false)
            }
            let review = try EnergyCalibration.evaluate(days: days, on: date(index), correction: correction, resting: 1600,
                                                        fingerprint: EnergyInputCoding.digest(EnergyInputCoding.encode(days)), previous: reviews.last,
                                                        lastApplied: reviews.last { $0.delta != 0 }, calendar: calendar)
            XCTAssertLessThanOrEqual(abs(review.nextCorrection), 320)
            XCTAssertLessThanOrEqual(abs(review.delta), 75)
            reviews.append(review)
            correction = review.nextCorrection
        }
        XCTAssertEqual(correction, -300)
        XCTAssertTrue(try XCTUnwrap(reviews.last).reason.contains("20%"))
    }

    func testUnresolvedSourceOrMissingTrainingCoverageStopsCalibration() {
        let days = (0 ..< 28).map { index in
            EnergyCalibrationDay(date: date(index), intake: 2000, uncalibratedTotal: 2400, foodComplete: true,
                                 activityComplete: index < 20, weights: [70], fluidChangeConcern: false)
        }
        let result = EnergyCalibration.evaluate(days: days, on: date(28), correction: 0, resting: 1600,
                                                fingerprint: "synthetic-source-coverage-change", previous: nil, lastApplied: nil, calendar: calendar)
        XCTAssertEqual(result.nextCorrection, 0)
        XCTAssertFalse(result.evidenceEligible)
    }
}
