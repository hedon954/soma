import Foundation
@testable import Soma
import SwiftData
import XCTest

@MainActor
final class DailyActivityRecordTests: XCTestCase {
    func testDailyMovementDoesNotCountAsTrainingOrKeepAnOldScheduleFresh() async throws {
        let container = try ModelContainer(for: Schema(SomaDataSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext, calendar = Calendar.current, today = calendar.startOfDay(for: .now)
        try DailyActivityRecordStore.replace([DailyActivitySyncCoordinator.demo(key: .init(date: today, calendar: calendar))], in: context)
        let window = ProgressPeriod.day.window(containing: today, calendar: calendar)
        let facts = try await ProgressHistoryLoader(modelContainer: container).load(window: window)
        let snapshot = ProgressHistoryProjection.build(window: window, records: facts.records, profile: facts.profile, calendar: calendar)
        XCTAssertEqual(snapshot.days.first?.records.count, 1)
        XCTAssertEqual(snapshot.trainingDayCount, 0)
        let schedule = TrainingSchedule(name: "虚构计划", anchorDate: today.addingTimeInterval(-30 * 86400), slots: [.rest()])
        XCTAssertNil(try TrainingScheduleStore.facts(for: schedule, in: context).lastTrainingDay)
        let earlier = try XCTUnwrap(calendar.date(byAdding: .day, value: -10, to: today))
        context.insert(WorkoutEntry(date: earlier, exercise: "虚构训练"))
        try context.save()
        XCTAssertEqual(try TrainingScheduleStore.facts(for: schedule, in: context).lastTrainingDay, earlier)
    }

    func testDailyRecordOverwritesOneIdentityKeepsNilAndSource() throws {
        let container = try ModelContainer(for: Schema(SomaDataSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let key = DailyActivityDayKey(date: .now, calendar: .current)
        var day = DailyActivitySummary(key: key)
        day[.steps].replace(value: 8000, readAt: .now)
        day[.walkingRunningDistance].replace(value: 6000, readAt: .now)
        day[.activeEnergy].replace(value: 400, readAt: .now)
        day[.activeEnergy].source = .init(sources: [.init(name: "COROS", bundleIdentifier: "example.coros")], readAt: .now)
        try DailyActivityRecordStore.replace([day], in: context)
        let first = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutEntry>()).first)
        let id = first.id
        let businessID = try XCTUnwrap(first.businessID)
        let projectionKey = first.projectionKey
        try SomaDataMigration.assignUniqueProjectionKeys(in: context)
        XCTAssertEqual(first.projectionKey, projectionKey)
        XCTAssertEqual(first.exercise, "日常活动")
        XCTAssertTrue(first.source?.contains("COROS") == true)
        day[.steps].replace(value: 100, readAt: .now)
        day[.walkingRunningDistance].replace(value: nil, readAt: .now)
        day[.activeEnergy].replace(value: 0, readAt: .now)
        try DailyActivityRecordStore.replace([day], in: context)
        let rows = try context.fetch(FetchDescriptor<WorkoutEntry>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, id)
        XCTAssertEqual(rows.first?.businessID, businessID)
        XCTAssertEqual(rows.first?.dailyActivity?[.steps].value, 100)
        XCTAssertNil(rows.first?.dailyActivity?[.walkingRunningDistance].value)
        XCTAssertEqual(rows.first?.estimatedCalories, 0)
        XCTAssertEqual(rows.first?.estimatedVolume, nil)
        XCTAssertTrue(try PortableExportPayload(snapshot: PersonalDataSnapshot.capture(from: context)).workouts.isEmpty)
        let full = try PersonalDataSnapshot.capture(from: context)
        XCTAssertEqual(full.workouts.first?.dailyActivityData, first.dailyActivityData)
        let manual = WorkoutEntry(date: key.start, exercise: "虚构训练")
        context.insert(manual)
        try BusinessIDAllocator.assign(manual, namespace: "workout", in: context)
        try context.save()
        XCTAssertEqual(ConversationRecorder.fetchWorkouts(in: context).map(\.id), [manual.id])
        XCTAssertEqual(CoachTimelineLoader.records(on: key.start, timeZone: .current, in: context).count, 1)
        context.delete(manual)
        for kind in DailyActivityMetricKind.allCases {
            day[kind].replace(value: nil, readAt: .now)
        }
        try DailyActivityRecordStore.replace([day], in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutEntry>()), 0)
    }

    func testPartialReadsAndFailuresDoNotEraseOtherMetrics() throws {
        let container = try ModelContainer(for: Schema(SomaDataSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let key = DailyActivityDayKey(date: .now, calendar: .current)
        var first = DailyActivitySummary(key: key)
        first[.activeEnergy].replace(value: 500, readAt: .now)
        try DailyActivityRecordStore.replace([first], in: context)
        var next = DailyActivitySummary(key: key)
        next[.steps].replace(value: 123, readAt: .now)
        next[.activeEnergy].availability = .failed
        try DailyActivityRecordStore.replace([next], in: context)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutEntry>()).first)
        XCTAssertEqual(entry.dailyActivity?[.activeEnergy].value, 500)
        XCTAssertEqual(entry.dailyActivity?[.steps].value, 123)
    }

    func testWinningSourcePersistsAndKeepsStableProjectionKey() throws {
        let container = try ModelContainer(for: Schema(SomaDataSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let key = DailyActivityDayKey(date: .now, calendar: .current)
        var day = DailyActivitySummary(key: key, winningSource: .coros)
        day[.steps].replace(value: 8000, readAt: .now)
        day[.activeEnergy].replace(value: 400, readAt: .now)
        try DailyActivityRecordStore.replace([day], in: context)
        let first = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutEntry>()).first)
        XCTAssertEqual(first.externalSource, "coros")
        XCTAssertTrue(first.isDailyActivity)
        XCTAssertEqual(first.dailyActivityWinningSource, .coros)
        let projectionKey = first.projectionKey
        day.winningSource = .appleHealth
        day[.steps].replace(value: 1000, readAt: .now)
        try DailyActivityRecordStore.replace([day], in: context)
        let rows = try context.fetch(FetchDescriptor<WorkoutEntry>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.projectionKey, projectionKey)
        XCTAssertEqual(rows.first?.externalSource, "appleHealth")
        XCTAssertEqual(rows.first?.dailyActivity?[.steps].value, 1000)
    }
}
