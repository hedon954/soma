@testable import Soma
import XCTest

final class HealthActivityEvidenceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private var day: DailyActivityDayKey {
        .init(date: start, calendar: Calendar(identifier: .gregorian))
    }

    func testComplementUsesUnionSoOverlappingSourcesDoNotSubtractTwice() {
        let start = day.start
        let inputs = [EnergyTimeInterval(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(7200)),
                      .init(start: start.addingTimeInterval(5400), end: start.addingTimeInterval(9000))]
        XCTAssertEqual(EnergyTimeInterval.union(inputs, within: day), [.init(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(9000))])
        XCTAssertEqual(EnergyTimeInterval.complement(inputs, within: day), [
            .init(start: start, end: start.addingTimeInterval(3600)), .init(start: start.addingTimeInterval(9000), end: day.end)
        ])
    }

    func testCrossingSampleIsAmbiguousButExactBoundariesAreNotProrated() {
        let interval = EnergyTimeInterval(start: day.start.addingTimeInterval(3600), end: day.start.addingTimeInterval(7200))
        XCTAssertTrue(EnergyTimeInterval.crossesBoundary(start: day.start, end: day.start.addingTimeInterval(4000), intervals: [interval]))
        XCTAssertFalse(EnergyTimeInterval.crossesBoundary(start: interval.start, end: interval.end, intervals: [interval]))
        XCTAssertFalse(EnergyTimeInterval.crossesBoundary(start: day.start, end: interval.start, intervals: [interval]))
    }

    func testCrossMidnightIntervalsClipToEachNaturalDay() {
        let interval = EnergyTimeInterval(start: day.start.addingTimeInterval(-3600), end: day.start.addingTimeInterval(3600))
        XCTAssertEqual(EnergyTimeInterval.union([interval], within: day), [.init(start: day.start, end: day.start.addingTimeInterval(3600))])
        XCTAssertEqual(EnergyTimeInterval.complement([.init(start: day.start, end: day.end)], within: day), [])
    }
}
