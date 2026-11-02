@testable import Soma
import XCTest

final class EnergyReferenceBuilderTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
    }

    private func samples(_ count: Int = 10, covered: Bool = true, basis: String = "merged-v1") -> [EnergyWalkingReferenceSample] {
        (0 ..< count).map { offset in
            .init(date: calendar.date(byAdding: .day, value: -offset - 1, to: today)!, kilometers: 3,
                  steps: 5000, coverageConfirmed: covered, trainingExcluded: true, basisID: basis)
        }
    }

    func testUnknownFactsStayUnknownWhilePriorIsExplicit() throws {
        let facts = EnergyLifestyleFacts(effectiveFrom: today)
        let reference = try EnergyReferenceBuilder.initial(facts)
        XCTAssertEqual(reference.factor, 1.4)
        XCTAssertNil(reference.walkingKilometers)
        XCTAssertNil(facts.workHours)
        XCTAssertNil(facts.workPosture)
        XCTAssertTrue(reference.reason.contains("未校准"))
    }

    func testIncompleteTimeBudgetIsRejectedRatherThanFilledWithCommonHours() {
        let facts = EnergyLifestyleFacts(effectiveFrom: today, allocations: [.init(label: "已知办公室工作", hours: 8, physicalActivityRatio: 1.5)])
        XCTAssertThrowsError(try EnergyReferenceBuilder.initial(facts))
    }

    func testExplicitFullTimeBudgetUsesFactorialCalculation() throws {
        let facts = EnergyLifestyleFacts(effectiveFrom: today, allocations: [
            .init(label: "用户说明的睡眠时段", hours: 8, physicalActivityRatio: 1),
            .init(label: "用户说明的其他参考活动", hours: 16, physicalActivityRatio: 1.5)
        ])
        XCTAssertEqual(try EnergyReferenceBuilder.initial(facts).factor, 32.0 / 24)
    }

    func testKnownWorkCommuteAndHouseworkReplaceReferenceHoursOnlyOnce() throws {
        let facts = EnergyLifestyleFacts(effectiveFrom: today, workPosture: .sitting, workHours: 8, workDaysPerWeek: 5,
                                         commutingWalkMinutes: 30, houseworkMinutes: 20)
        let work = (1.3 - 1.4) * (8.0 * 5 / 7) / 24
        let commute = (3.2 - 1.4) * (0.5 * 5 / 7) / 24
        let housework = (2.8 - 1.4) * (20.0 / 60) / 24
        XCTAssertEqual(try EnergyReferenceBuilder.initial(facts).factor, 1.4 + work + commute + housework, accuracy: 0.000001)
        XCTAssertNil(facts.allocations.first)
        XCTAssertNil(try EnergyReferenceBuilder.initial(facts).walkingKilometers)
        XCTAssertThrowsError(try EnergyReferenceBuilder.initial(.init(effectiveFrom: today, workPosture: .sitting,
                                                                      workHours: 24, workDaysPerWeek: 7, houseworkMinutes: 60)))
    }

    func testReferenceNeedsEnoughDistinctCoveredDaysOfConsistentBasis() {
        XCTAssertEqual(EnergyReferenceBuilder.walkingDistance(samples(), before: today, basisID: "merged-v1", calendar: calendar), 3)
        for entries in [samples(9), samples(10, covered: false), samples(10, basis: "different"), Array(repeating: samples()[0], count: 12)] {
            XCTAssertNil(EnergyReferenceBuilder.walkingDistance(entries, before: today, basisID: "merged-v1", calendar: calendar))
        }
    }

    func testStrideUsesPairedDistinctDaysAndCannotUseHeightDefault() {
        XCTAssertEqual(EnergyReferenceBuilder.stepLengthMeters(samples(7), basisID: "merged-v1", calendar: calendar), 0.6)
        XCTAssertNil(EnergyReferenceBuilder.stepLengthMeters(samples(6), basisID: "merged-v1", calendar: calendar))
        XCTAssertNil(EnergyReferenceBuilder.stepLengthMeters(samples(7, covered: false), basisID: "merged-v1", calendar: calendar))
    }
}
