@testable import Soma
import XCTest

final class TrainingEnergyNetIncrementTests: XCTestCase {
    func testMetFiveRemovesTheRestingFifth() throws {
        XCTAssertEqual(
            try XCTUnwrap(TrainingEnergyNetIncrement.kilocalories(gross: 350, met: 5)),
            280,
            accuracy: 0.0001
        )
    }

    func testMetAtOrBelowOneAddsNothing() throws {
        XCTAssertEqual(try XCTUnwrap(TrainingEnergyNetIncrement.kilocalories(gross: 100, met: 1)), 0)
        XCTAssertEqual(try XCTUnwrap(TrainingEnergyNetIncrement.kilocalories(gross: 100, met: 0.9)), 0)
    }

    func testMissingMetUsesRestingShareOfDuration() throws {
        XCTAssertEqual(
            try XCTUnwrap(
                TrainingEnergyNetIncrement.kilocalories(
                    gross: 100, met: nil, durationMinutes: 60, dailyResting: 1440
                )
            ),
            40,
            accuracy: 0.0001
        )
    }

    func testMetWinsOverDurationFallback() throws {
        XCTAssertEqual(
            try XCTUnwrap(
                TrainingEnergyNetIncrement.kilocalories(
                    gross: 350, met: 5, durationMinutes: 60, dailyResting: 1440
                )
            ),
            280,
            accuracy: 0.0001
        )
    }

    func testMissingEvidenceStaysUnknown() {
        XCTAssertNil(TrainingEnergyNetIncrement.kilocalories(gross: 350, met: nil))
        XCTAssertNil(TrainingEnergyNetIncrement.kilocalories(gross: nil, met: 5))
        XCTAssertNil(TrainingEnergyNetIncrement.kilocalories(gross: .nan, met: 5))
    }
}
