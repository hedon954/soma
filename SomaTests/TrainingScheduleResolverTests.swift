@testable import Soma
import XCTest

final class TrainingScheduleResolverTests: XCTestCase {
    private let push = UUID()
    private let pull = UUID()
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        self.calendar = calendar
    }

    func testScheduledDayStaysDueUntilTheNextOpportunity() {
        let slots = [
            TrainingScheduleSlotValue.course(push),
            TrainingScheduleSlotValue.course(pull)
        ]
        let monday = resolve(slots: slots, today: day(0))
        guard case let .due(programID, _, makeup) = monday.attention else {
            return XCTFail("expected Monday's course")
        }
        XCTAssertEqual(programID, push)
        XCTAssertFalse(makeup)

        let tuesday = resolve(slots: slots, today: day(1))
        guard case let .due(programID, dueDay, makeup) = tuesday.attention else {
            return XCTFail("expected the missed course")
        }
        XCTAssertEqual(programID, push)
        XCTAssertEqual(dueDay, day(0))
        XCTAssertTrue(makeup)

        let wednesday = resolve(slots: slots, today: day(2))
        guard case let .due(programID, dueDay, makeup) = wednesday.attention else {
            return XCTFail("expected the current course")
        }
        XCTAssertEqual(programID, pull)
        XCTAssertEqual(dueDay, day(1))
        XCTAssertTrue(makeup)
        XCTAssertEqual(wednesday.expiredDueDays, [day(0)])
    }

    func testExplicitRestClosesTheOutstandingCourse() {
        let slots = [TrainingScheduleSlotValue.course(push), .rest()]
        let resolution = resolve(
            slots: slots,
            today: day(1),
            closures: [.rest(on: day(0))]
        )
        XCTAssertEqual(resolution.attention, .restDay)
        XCTAssertTrue(resolution.expiredDueDays.isEmpty)
    }

    func testCompletionOnTheGraceDayClosesThatCourse() {
        let slots = [TrainingScheduleSlotValue.course(push), .course(pull)]
        let resolution = resolve(
            slots: slots,
            today: day(1),
            completions: [TrainingScheduleCompletion(programID: push, day: day(1))]
        )
        guard case let .due(programID, dueDay, _) = resolution.attention else {
            return XCTFail("expected Tuesday's own course")
        }
        XCTAssertEqual(programID, pull)
        XCTAssertEqual(dueDay, day(1))
    }

    func testAFullCycleWithoutRecordsMarksThePhaseStale() {
        XCTAssertFalse(
            TrainingScheduleResolver.phaseIsStale(
                anchor: day(0),
                cycleLength: 7,
                today: day(0),
                lastTrainingDay: day(-30),
                calendar: calendar
            )
        )
        XCTAssertFalse(
            TrainingScheduleResolver.phaseIsStale(
                anchor: day(0),
                cycleLength: 7,
                today: day(6),
                lastTrainingDay: nil,
                calendar: calendar
            )
        )
        XCTAssertTrue(
            TrainingScheduleResolver.phaseIsStale(
                anchor: day(0),
                cycleLength: 7,
                today: day(7),
                lastTrainingDay: nil,
                calendar: calendar
            )
        )
    }

    func testReanchorRequestHoldsEvenAfterANewRecord() {
        let resolution = resolve(
            slots: [.course(push)],
            today: day(1),
            completions: [TrainingScheduleCompletion(programID: push, day: day(1))],
            reanchorRequired: true
        )
        XCTAssertEqual(resolution.attention, TrainingScheduleAttention.paused)
        XCTAssertEqual(resolution.probeProgramID, push)
    }

    func testReanchorMovesTodayOntoTheFirstCourse() {
        let slots = [TrainingScheduleSlotValue.rest(), .course(push)]
        let anchor = TrainingScheduleResolver.anchor(
            soToday: day(10),
            matchesFirstCourseIn: slots,
            calendar: calendar
        )
        XCTAssertEqual(anchor, day(9))
    }

    private func resolve(
        slots: [TrainingScheduleSlotValue],
        today: Date,
        closures: [TrainingScheduleClosureValue] = [],
        completions: [TrainingScheduleCompletion] = [],
        reanchorRequired: Bool = false
    ) -> TrainingScheduleResolution {
        TrainingScheduleResolver.resolve(
            anchor: day(0),
            slots: slots,
            today: today,
            closures: closures,
            completions: completions,
            reanchorRequired: reanchorRequired,
            calendar: calendar
        )
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(offset) * 86400)
    }
}
