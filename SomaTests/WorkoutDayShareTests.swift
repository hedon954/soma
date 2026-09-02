@testable import Soma
import SwiftData
import XCTest

final class WorkoutDayShareTests: XCTestCase {
    private struct Fixture {
        var context: ModelContext
        var defaults: UserDefaults
        var suite: String
        var calendar: Calendar
        var day: Date
    }

    @MainActor
    func testDailyPosterFetchesWholeNaturalDayAndAggregatesWorkoutRecords() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let context = fixture.context
        let calendar = fixture.calendar
        let day = fixture.day

        let squat = ExerciseDefinition(
            canonicalName: "虚构深蹲",
            primaryMuscles: ["股四头肌"],
            secondaryMuscles: ["臀大肌"]
        )
        let raise = ExerciseDefinition(
            canonicalName: "虚构提踵",
            primaryMuscles: ["小腿"]
        )
        context.insert(squat)
        context.insert(raise)

        let morning = WorkoutEntry(
            date: day.addingTimeInterval(-3600),
            exercise: squat.canonicalName,
            exerciseID: squat.id,
            setEntries: (1 ... 2).map { index in
                WorkoutSetEvidence(
                    logicalSetIndex: index,
                    reps: 5,
                    externalWeightKG: 20,
                    restSeconds: index == 1 ? 60 : nil
                )
            },
            durationMinutes: 5,
            estimatedCalories: 30,
            calorieDurationMinutes: 5
        )
        morning.exerciseDefinition = squat
        let evening = WorkoutEntry(
            date: day.addingTimeInterval(3600),
            exercise: raise.canonicalName,
            exerciseID: raise.id,
            setEntries: [WorkoutSetEvidence(
                logicalSetIndex: 1,
                reps: 12,
                externalWeightKG: 0
            )],
            estimatedCalories: 10,
            calorieDurationMinutes: 3,
            calorieDurationEstimated: true
        )
        evening.exerciseDefinition = raise
        let tomorrow = try WorkoutEntry(
            date: XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day)),
            exercise: "次日记录",
            setEntries: [WorkoutSetEvidence(
                logicalSetIndex: 1,
                reps: 100,
                externalWeightKG: 100
            )],
            estimatedCalories: 999,
            calorieDurationMinutes: 99
        )
        context.insert(morning)
        context.insert(evening)
        context.insert(tomorrow)
        try context.save()

        let model = try XCTUnwrap(WorkoutSharePosterBuilder.makeModel(
            forDay: day,
            in: context,
            calendar: calendar
        ))

        XCTAssertEqual(model.dateText, "2026-09-03 周四")
        XCTAssertEqual(model.title, "股四头肌 · 小腿")
        XCTAssertEqual(model.exerciseCount, 2)
        XCTAssertEqual(model.completedSets, 3)
        XCTAssertEqual(model.volumeValue, "200")
        XCTAssertEqual(model.estimatedCalories, 40)
        XCTAssertEqual(model.durationText, "约 8 分")
        XCTAssertEqual(model.exercises.map(\.name), ["虚构深蹲", "虚构提踵"])
        XCTAssertEqual(model.exercises.map(\.setCount), [2, 1])
        XCTAssertEqual(model.intensities[.quadriceps], 2)
        XCTAssertEqual(model.intensities[.calves], 1)
        XCTAssertNil(model.exercises.first { $0.name == "次日记录" })
    }

    @MainActor
    func testDailyPosterKeepsCaloriesEmptyWhenAnyWorkoutLacksEstimate() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let context = fixture.context
        let day = fixture.day

        context.insert(WorkoutEntry(
            date: day,
            exercise: "有热量记录",
            setEntries: [WorkoutSetEvidence(
                logicalSetIndex: 1,
                reps: 5,
                externalWeightKG: 10
            )],
            estimatedCalories: 12,
            calorieDurationMinutes: 1
        ))
        context.insert(WorkoutEntry(
            date: day.addingTimeInterval(60),
            exercise: "缺热量记录",
            setEntries: [WorkoutSetEvidence(
                logicalSetIndex: 1,
                reps: 5,
                externalWeightKG: 10
            )]
        ))
        try context.save()

        let model = try XCTUnwrap(WorkoutSharePosterBuilder.makeModel(
            forDay: day,
            in: context,
            calendar: fixture.calendar
        ))

        XCTAssertNil(model.estimatedCalories)
        XCTAssertEqual(model.exerciseCount, 2)
    }

    @MainActor
    func testDailyPosterIsNotLimitedByHistoryPageSize() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let count = WorkoutHistoryQuery.pageSize + 1

        for index in 0 ..< count {
            fixture.context.insert(WorkoutEntry(
                date: fixture.day.addingTimeInterval(Double(index)),
                exercise: "虚构动作 \(index + 1)",
                setEntries: [WorkoutSetEvidence(
                    logicalSetIndex: 1,
                    reps: 1,
                    externalWeightKG: 1
                )],
                durationMinutes: 1,
                estimatedCalories: 1,
                calorieDurationMinutes: 1
            ))
        }
        try fixture.context.save()

        let model = try XCTUnwrap(WorkoutSharePosterBuilder.makeModel(
            forDay: fixture.day,
            in: fixture.context,
            calendar: fixture.calendar
        ))

        XCTAssertEqual(model.exerciseCount, count)
        XCTAssertEqual(model.exercises.count, count)
        XCTAssertEqual(model.completedSets, count)
    }

    @MainActor
    private func makeFixture() throws -> Fixture {
        let suite = "WorkoutDayShareTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let container = try XCTUnwrap(spaces.personalContainer)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3600))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 3,
            hour: 12
        )))
        return Fixture(
            context: ModelContext(container),
            defaults: defaults,
            suite: suite,
            calendar: calendar,
            day: day
        )
    }
}
