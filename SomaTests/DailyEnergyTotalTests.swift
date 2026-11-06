@testable import Soma
import XCTest

final class DailyEnergyTotalTests: XCTestCase {
    func testFormulaAddsRestingBaselineExtraAndSelectedActiveEnergy() throws {
        let components = try XCTUnwrap(DailyEnergyTotal.compose(
            restingKilocalories: 1600,
            coefficient: .current(),
            selectedActiveKilocalories: 250
        ))
        XCTAssertEqual(components.coefficient, ResidualEnergyCoefficient.initialFallback)
        XCTAssertEqual(components.baselineExtraKilocalories, 640)
        XCTAssertEqual(components.activityKilocalories, 250)
        XCTAssertEqual(components.totalKilocalories, 1600 * 1.4 + 250)
        XCTAssertTrue(components.componentsAddUp)
    }

    func testActiveEnergyChangesTheTotalWithoutChangingTheCoefficient() throws {
        let low = try XCTUnwrap(DailyEnergyTotal.compose(
            restingKilocalories: 1500, coefficient: .current(), selectedActiveKilocalories: 100
        ))
        let high = try XCTUnwrap(DailyEnergyTotal.compose(
            restingKilocalories: 1500, coefficient: .init(value: low.coefficient), selectedActiveKilocalories: 400
        ))
        XCTAssertEqual(high.coefficient, low.coefficient)
        XCTAssertEqual(high.totalKilocalories - low.totalKilocalories, 300)
    }

    func testDisaggregatedTrainingStaysInsideSelectedActiveEnergy() throws {
        let components = try XCTUnwrap(DailyEnergyTotal.compose(
            restingKilocalories: 1600, coefficient: .current(),
            selectedActiveKilocalories: 450, includedTrainingKilocalories: 120
        ))
        XCTAssertEqual(components.activity, .disaggregated(training: 120, remaining: 330))
        XCTAssertEqual(components.totalKilocalories, 1600 * 1.4 + 450)
        let overflow = try XCTUnwrap(DailyEnergyTotal.compose(
            restingKilocalories: 1600, coefficient: .current(),
            selectedActiveKilocalories: 450, includedTrainingKilocalories: 700,
            recordedTrainingKilocalories: 700
        ))
        XCTAssertEqual(overflow.activity, .selected(450))
        XCTAssertEqual(overflow.totalKilocalories, 1600 * 1.4 + 450)
    }

    func testMissingActiveEnergyDoesNotBecomeZeroOrDropKnownTraining() throws {
        let absent = try XCTUnwrap(DailyEnergyTotal.compose(
            restingKilocalories: 1600, coefficient: .current(), selectedActiveKilocalories: nil
        ))
        XCTAssertEqual(absent.activity, .absent)
        XCTAssertEqual(absent.totalKilocalories, 1600 * 1.4)
        let training = try XCTUnwrap(DailyEnergyTotal.compose(
            restingKilocalories: 1600, coefficient: .current(),
            selectedActiveKilocalories: nil, recordedTrainingKilocalories: 320
        ))
        XCTAssertEqual(training.activity, .recordedTraining(320))
        XCTAssertEqual(training.totalKilocalories, 1600 * 1.4 + 320)
        XCTAssertNil(DailyEnergyTotal.compose(
            restingKilocalories: 1600, coefficient: .current(), selectedActiveKilocalories: .nan
        ))
        XCTAssertNil(DailyEnergyTotal.compose(
            restingKilocalories: 0, coefficient: .current(), selectedActiveKilocalories: 100
        ))
    }

    func testOverlappingDailyReadingsAreNotSummed() {
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let apple = ProgressHistoryRecord(
            activity: .init(id: UUID(), kind: .workout, date: day, title: "Apple", detail: "", metric: nil),
            calories: 100, activeEnergyKilocalories: 100, isDailyActivity: true, dailyActivitySource: .appleHealth
        )
        let coros = ProgressHistoryRecord(
            activity: .init(id: UUID(), kind: .workout, date: day.addingTimeInterval(1), title: "COROS", detail: "", metric: nil),
            calories: 400, activeEnergyKilocalories: 400, isDailyActivity: true, dailyActivitySource: .coros
        )
        let selected = DailyEnergyTotal.selectedDailyActive(in: [apple, coros])
        XCTAssertEqual(selected.kilocalories, 400)
        XCTAssertEqual(selected.source, .coros)
        XCTAssertNotEqual((selected.kilocalories ?? 0), 500)
    }

    func testOnlyTrainingInsideTheWinningPackageCanBeSplit() {
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let health = EnergyTrainingEvent(
            id: "health:fixture", source: "虚构 COROS", scope: .active, kilocalories: 180,
            met: nil, durationHours: 1, start: day, end: day.addingTimeInterval(3600)
        )
        let soma = EnergyTrainingEvent(
            id: "soma:fixture", source: "Soma", scope: .metGross, kilocalories: 600,
            met: 6, durationHours: 1, start: day, end: day.addingTimeInterval(3600)
        )
        XCTAssertEqual(
            DailyEnergyTotal.includedTrainingKilocalories(
                selectedActive: 450, winningSource: .coros, events: [health], resting: 1600
            ),
            180
        )
        XCTAssertNil(DailyEnergyTotal.includedTrainingKilocalories(
            selectedActive: 450, winningSource: .appleHealth, events: [health, soma], resting: 1600
        ))
        XCTAssertNil(DailyEnergyTotal.includedTrainingKilocalories(
            selectedActive: 100, winningSource: .coros, events: [health], resting: 1600
        ))
    }
}
