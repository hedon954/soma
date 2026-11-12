@testable import Soma
import XCTest

final class DailyEnergyTotalTests: XCTestCase {
    func testFormulaAddsRestingBaselineExtraSelectedActiveAndTraining() throws {
        let components = try XCTUnwrap(DailyEnergyTotal.compose(
            restingKilocalories: 1600,
            coefficient: .current(),
            selectedActiveKilocalories: 250,
            trainingKilocalories: 80
        ))
        XCTAssertEqual(components.coefficient, ResidualEnergyCoefficient.initialFallback)
        XCTAssertEqual(components.baselineExtraKilocalories, 640, accuracy: 0.001)
        XCTAssertEqual(components.activityKilocalories, 250)
        XCTAssertEqual(components.trainingKilocalories, 80)
        XCTAssertEqual(components.totalKilocalories, 1600 * 1.4 + 250 + 80, accuracy: 0.001)
        XCTAssertTrue(components.componentsAddUp)
        let displayed = EnergyKilocalorieDisplay.parts(.init(
            restingKilocalories: 1617.5, coefficient: 1.4, activity: .absent
        ))
        XCTAssertEqual(displayed.resting, 1618)
        XCTAssertEqual(displayed.baselineExtra, 647)
        XCTAssertEqual(displayed.training, 0)
        XCTAssertEqual(displayed.total, 2265)
        XCTAssertTrue(displayed.addsUp)
        XCTAssertEqual(EnergyKilocalorieDisplay.whole(2264.5 - 1900), 365)
        let withTraining = EnergyKilocalorieDisplay.parts(.init(
            restingKilocalories: 1600, coefficient: 1.4, activity: .selected(250), trainingKilocalories: 80
        ))
        XCTAssertEqual(withTraining.resting, 1600)
        XCTAssertEqual(withTraining.training, 80)
        XCTAssertEqual(withTraining.displayedActivity, 250)
        XCTAssertEqual(withTraining.total, 2570)
        XCTAssertTrue(withTraining.addsUp)
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

    func testTrainingIsAddedOnTopOfSelectedActiveEnergy() throws {
        let components = try XCTUnwrap(DailyEnergyTotal.compose(
            restingKilocalories: 1600, coefficient: .current(),
            selectedActiveKilocalories: 300, trainingKilocalories: 210
        ))
        XCTAssertEqual(components.activity, .selected(300))
        XCTAssertEqual(components.trainingKilocalories, 210)
        XCTAssertEqual(components.totalKilocalories, 1600 * 1.4 + 300 + 210, accuracy: 0.001)
        let withoutTraining = try XCTUnwrap(DailyEnergyTotal.compose(
            restingKilocalories: 1600, coefficient: .current(), selectedActiveKilocalories: 300
        ))
        XCTAssertEqual(withoutTraining.trainingKilocalories, 0)
        XCTAssertEqual(withoutTraining.activity, .selected(300))
        XCTAssertEqual(components.totalKilocalories - withoutTraining.totalKilocalories, 210, accuracy: 0.001)
    }

    func testMissingActiveEnergyDoesNotBecomeZeroAndStillAddsTraining() throws {
        let absent = try XCTUnwrap(DailyEnergyTotal.compose(
            restingKilocalories: 1600, coefficient: .current(), selectedActiveKilocalories: nil
        ))
        XCTAssertEqual(absent.activity, .absent)
        XCTAssertEqual(absent.trainingKilocalories, 0)
        XCTAssertEqual(absent.totalKilocalories, 1600 * 1.4)
        let training = try XCTUnwrap(DailyEnergyTotal.compose(
            restingKilocalories: 1600, coefficient: .current(),
            selectedActiveKilocalories: nil, trainingKilocalories: 320
        ))
        XCTAssertEqual(training.activity, .absent)
        XCTAssertEqual(training.trainingKilocalories, 320)
        XCTAssertEqual(training.totalKilocalories, 1600 * 1.4 + 320)
        XCTAssertNil(DailyEnergyTotal.compose(
            restingKilocalories: 1600, coefficient: .current(), selectedActiveKilocalories: .nan
        ))
        XCTAssertNil(DailyEnergyTotal.compose(
            restingKilocalories: 0, coefficient: .current(), selectedActiveKilocalories: 100
        ))
        let invalidTraining = try XCTUnwrap(DailyEnergyTotal.compose(
            restingKilocalories: 1600, coefficient: .current(),
            selectedActiveKilocalories: 100, trainingKilocalories: .nan
        ))
        XCTAssertEqual(invalidTraining.trainingKilocalories, 0)
        XCTAssertEqual(invalidTraining.totalKilocalories, 1600 * 1.4 + 100, accuracy: 0.001)
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
        XCTAssertNotEqual(selected.kilocalories ?? 0, 500)
    }

    func testListTrainingSumsVisibleEstimatesAndSkipsInvalidOrDuplicateRecords() {
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let firstID = UUID()
        let first = workout(id: firstID, date: day, calories: 80)
        let duplicate = workout(id: firstID, date: day, calories: 80)
        let second = workout(id: UUID(), date: day, calories: 90)
        let third = workout(id: UUID(), date: day, calories: 110)
        let fourth = workout(id: UUID(), date: day, calories: 130)
        let daily = ProgressHistoryRecord(
            activity: .init(id: UUID(), kind: .workout, date: day, title: "日常活动", detail: "", metric: nil),
            calories: 300, activeEnergyKilocalories: 300, isDailyActivity: true, dailyActivitySource: .appleHealth
        )
        let missing = workout(id: UUID(), date: day, calories: nil)
        let invalid = workout(id: UUID(), date: day, calories: -8)
        let tooLarge = workout(id: UUID(), date: day, calories: 100_000)
        let zero = workout(id: UUID(), date: day, calories: 0)
        XCTAssertEqual(
            DailyEnergyTotal.listTrainingKilocalories(
                in: [first, duplicate, second, third, fourth, daily, missing, invalid, tooLarge, zero]
            ),
            80 + 90 + 110 + 130
        )
        XCTAssertEqual(DailyEnergyTotal.listTrainingKilocalories(in: [daily, missing]), 0)
    }

    func testLegacyRecordedTrainingDecodesAsIndependentTrainingAddend() throws {
        let data = Data(
            #"{"restingKilocalories":1600,"coefficient":1.4,"activity":{"recordedTraining":320}}"#.utf8
        )
        let components = try JSONDecoder().decode(DailyEnergyTotal.Components.self, from: data)
        XCTAssertEqual(components.activity, .absent)
        XCTAssertEqual(components.trainingKilocalories, 320)
        XCTAssertEqual(components.totalKilocalories, 1600 * 1.4 + 320, accuracy: 0.001)
        let split = Data(
            #"{"restingKilocalories":1600,"coefficient":1.4,"activity":{"disaggregated":{"training":120,"remaining":330}}}"#.utf8
        )
        let migrated = try JSONDecoder().decode(DailyEnergyTotal.Components.self, from: split)
        XCTAssertEqual(migrated.activity, .selected(450))
        XCTAssertEqual(migrated.trainingKilocalories, 0)
        XCTAssertEqual(migrated.totalKilocalories, 1600 * 1.4 + 450, accuracy: 0.001)
    }

    private func workout(id: UUID, date: Date, calories: Double?) -> ProgressHistoryRecord {
        .init(
            activity: .init(id: id, kind: .workout, date: date, title: "虚构训练", detail: "", metric: nil),
            calories: calories
        )
    }
}
