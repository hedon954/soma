@testable import Soma
import XCTest

final class EnergyDayCalculationTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_790_000_000)

    private func input(distance: Double? = 5, covered: Bool = true, ended: Bool = true, training: [EnergyTrainingEvent] = []) -> EnergyDayInput {
        .init(date: day, resting: 1600, weightKG: 70,
              reference: .init(effectiveFrom: day, factor: 1.4, walkingKilometers: 3, reason: "虚构参考"),
              nonTrainingKilometers: distance, walkingCoverageConfirmed: covered, isEndedDay: ended,
              training: training, correction: 0)
    }

    private func event(
        _ id: String, linked: String? = nil, energy: Double = 500,
        scope: EnergyTrainingEvent.EnergyScope = .active, met: Double? = nil, offset: Double = 0
    ) -> EnergyTrainingEvent {
        .init(id: id, linkedIdentity: linked, source: "example.device", scope: scope, kilocalories: energy,
              met: met, durationHours: 1, start: day.addingTimeInterval(offset), end: day.addingTimeInterval(offset + 3600))
    }

    func testReferenceWalkingIsNotAddedTwiceAndTrainingReplacesOtherActivity() throws {
        let result = try EnergyDayCalculator.calculate(input(training: [event("run")]))
        XCTAssertEqual(result.baseline, 2240)
        XCTAssertEqual(result.walkingDelta, 70)
        XCTAssertEqual(result.trainingDelta, 480.5625)
        XCTAssertEqual(result.total, 2790.5625)
        XCTAssertEqual(result.factor, result.total / 1600)
        XCTAssertTrue(result.canCalibrate)
    }

    func testCoveredLowerActivityCanReduceButMissingCoverageAndOpenDayCannot() throws {
        XCTAssertEqual(try EnergyDayCalculator.calculate(input(distance: 1)).total, 2170)
        for candidate in [input(distance: 0, covered: false), input(distance: nil), input(distance: 0, ended: false)] {
            let result = try EnergyDayCalculator.calculate(candidate)
            XCTAssertEqual(result.total, 2240)
            XCTAssertFalse(result.canCalibrate)
        }
    }

    func testOpenDayCreditsObservedWalkingBeyondFullDayReferenceWithoutSubtractingUnfinishedHours() throws {
        let more = try EnergyDayCalculator.calculate(input(distance: 5, ended: false))
        XCTAssertEqual(more.walkingDelta, 70)
        XCTAssertEqual(more.total, 2310)
        XCTAssertFalse(more.canCalibrate)
        let less = try EnergyDayCalculator.calculate(input(distance: 1, ended: false))
        XCTAssertEqual(less.walkingDelta, 0)
    }

    func testSameExplicitIdentityAcrossDeviceAndMETCountsOnce() throws {
        let result = try EnergyDayCalculator.calculate(input(training: [
            event("device", linked: "session"), event("local", linked: "session", energy: 600, scope: .metGross, met: 6)
        ]))
        XCTAssertEqual(result.adoptedTrainingIDs, ["device"])
        XCTAssertEqual(result.excludedTrainingIDs, ["local"])
        XCTAssertEqual(result.total, 2790.5625)
        XCTAssertTrue(result.canCalibrate)
    }

    func testCoincidentTimesWithoutExplicitIdentityRequireReview() throws {
        let result = try EnergyDayCalculator.calculate(input(training: [event("a"), event("b")]))
        XCTAssertTrue(result.adoptedTrainingIDs.isEmpty)
        XCTAssertEqual(result.trainingDelta, 0)
        XCTAssertEqual(result.walkingDelta, 0)
        XCTAssertFalse(result.canCalibrate)
    }

    func testIndependentSessionsBothContribute() throws {
        let result = try EnergyDayCalculator.calculate(input(training: [event("a"), event("b", offset: 7200)]))
        XCTAssertEqual(result.adoptedTrainingIDs.count, 2)
        XCTAssertEqual(result.trainingDelta, 961.125)
    }

    func testUnknownScopeCannotCreateEnergyOrEnableCalibration() throws {
        let result = try EnergyDayCalculator.calculate(input(training: [event("unknown", scope: .unknown)]))
        XCTAssertEqual(result.total, 2240)
        XCTAssertFalse(result.canCalibrate)
        XCTAssertEqual(result.excludedTrainingIDs, ["unknown"])
    }

    func testNetAndGrossScopesRemainDifferentAndNeverDoubleSubtractResting() throws {
        XCTAssertEqual(event("net").netEnergy(resting: 1600), 500)
        XCTAssertEqual(event("met", energy: 600, scope: .metGross, met: 6).netEnergy(resting: 1600), 500)
        XCTAssertEqual(try XCTUnwrap(event("gross", energy: 600, scope: .gross).netEnergy(resting: 1600)), 533.333333, accuracy: 0.001)
    }

    func testMissingIntervalRetainsKnownTrainingButDoesNotClaimWalkingExclusion() throws {
        let unknown = EnergyTrainingEvent(id: "manual", source: "Soma", scope: .active, kilocalories: 500,
                                          met: nil, durationHours: 1, start: nil, end: nil)
        let result = try EnergyDayCalculator.calculate(input(training: [unknown]))
        XCTAssertEqual(result.trainingDelta, 480.5625)
        XCTAssertEqual(result.walkingDelta, 0)
        XCTAssertFalse(result.canCalibrate)
    }

    func testReanchoringPreservesWalkingAndTrainingResult() throws {
        let old = input(training: [event("run")])
        let reference = try EnergyDayCalculator.reanchor(old.reference, distance: 5, resting: 1600, weightKG: 70)
        let updated = EnergyDayInput(date: old.date, resting: old.resting, weightKG: old.weightKG, reference: reference,
                                     nonTrainingKilometers: 5, walkingCoverageConfirmed: true, isEndedDay: true,
                                     training: old.training, correction: 0)
        XCTAssertEqual(try EnergyDayCalculator.calculate(old).total, try EnergyDayCalculator.calculate(updated).total, accuracy: 0.001)
    }

    func testInconsistentReferenceFailsInsteadOfClampingUnknownBudget() {
        let invalid = EnergyDayInput(date: day, resting: 1600, weightKG: 70,
                                     reference: .init(effectiveFrom: day, factor: 1.4, walkingKilometers: 30, reason: "矛盾夹具"),
                                     nonTrainingKilometers: 5, walkingCoverageConfirmed: true, isEndedDay: true, training: [], correction: 0)
        XCTAssertThrowsError(try EnergyDayCalculator.calculate(invalid))
    }

    func testCalculationSnapshotRoundTripsAllEvidence() throws {
        let result = try EnergyDayCalculator.calculate(input(training: [event("fixture")]))
        XCTAssertEqual(try JSONDecoder().decode(EnergyDayCalculation.self, from: JSONEncoder().encode(result)), result)
    }
}
