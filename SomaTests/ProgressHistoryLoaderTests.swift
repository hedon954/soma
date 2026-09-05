@testable import Soma
import SwiftData
import XCTest

@MainActor
final class ProgressHistoryLoaderTests: XCTestCase {
    func testDiskHistoryUsesBoundedDatesPaginationAndImmutableValues() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProgressHistory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(SomaDataSchema.models)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(
            "ProgressHistory", schema: schema, url: directory.appendingPathComponent("history.store"), cloudKitDatabase: .none
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day = Date(timeIntervalSince1970: 86400 * 20000)
        let window = ProgressPeriod.day.window(containing: day, calendar: calendar)
        for index in 0 ..< 300 {
            container.mainContext.insert(MealEntry(date: day.addingTimeInterval(Double(index)), mealType: .lunch, title: "虚构餐食 \(index)", calories: 1))
        }
        container.mainContext.insert(MealEntry(date: window.end, mealType: .lunch, title: "次日不计入", calories: 9000))
        let workout = WorkoutEntry(date: day, exercise: "虚构左右动作")
        workout.setEntries = [
            .init(logicalSetIndex: 1, side: .left, reps: 10, externalWeightKG: 5),
            .init(logicalSetIndex: 1, side: .right, reps: 10, externalWeightKG: 5),
            .init(logicalSetIndex: 2, kind: .warmup, reps: 10, externalWeightKG: 0)
        ]
        container.mainContext.insert(workout)
        try container.mainContext.save()
        let facts = try await ProgressHistoryLoader(modelContainer: container).load(window: window)
        XCTAssertEqual(facts.records.filter { $0.activity.kind == .meal }.count, 300)
        XCTAssertEqual(facts.records.first { $0.activity.kind == .workout }?.logicalSets, 1)
        XCTAssertEqual(facts.records.first { $0.activity.kind == .workout }?.volume, 100)
        workout.exercise = "修改之后"
        try container.mainContext.save()
        XCTAssertEqual(facts.records.first { $0.activity.kind == .workout }?.activity.title, "虚构左右动作")
        let empty = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let other = try await ProgressHistoryLoader(modelContainer: empty).load(window: window)
        XCTAssertTrue(other.records.isEmpty)
    }
}
