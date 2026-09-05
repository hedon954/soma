@testable import Soma
import XCTest

final class EnergySampleCoverageTests: XCTestCase {
    func testOverlapAndReplayDoNotDoubleCountCoverage() {
        let day = interval(0, 100)
        let samples = [interval(0, 50), interval(25, 75), interval(25, 75)]
        XCTAssertEqual(EnergySampleCoverage.fraction(samples, within: day), 0.75, accuracy: 0.0001)
    }

    func testClipsSamplesAcrossDayAndDoesNotFillGaps() {
        let day = interval(0, 100)
        XCTAssertEqual(EnergySampleCoverage.fraction([interval(-10, 25), interval(75, 110)], within: day), 0.5)
        XCTAssertEqual(EnergySampleCoverage.fraction([interval(-10, 110)], within: day), 1)
        XCTAssertEqual(EnergySampleCoverage.fraction([interval(100, 110)], within: day), 0)
    }

    func testEmptyAndInstantaneousSamplesDoNotCreateCoverage() {
        XCTAssertEqual(EnergySampleCoverage.fraction([], within: interval(0, 100)), 0)
        XCTAssertEqual(EnergySampleCoverage.fraction([interval(20, 20)], within: interval(0, 100)), 0)
        XCTAssertEqual(EnergySampleCoverage.fraction([interval(0, 100)], within: interval(0, 0)), 0)
    }

    private func interval(_ start: Double, _ end: Double) -> DateInterval {
        DateInterval(start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
    }
}
