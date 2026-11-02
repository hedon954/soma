@testable import Soma
import SwiftData
import XCTest

/// Same entity name and existing required columns, without any new energy fields or tables.
private enum LegacyEnergyStore {
    @Model
    final class WorkoutEntry {
        var id: UUID
        var date: Date
        var exercise: String
        var notes: String
        var mediaKindRaw: String
        var setEntriesData: Data = Data()
        var mediaAttachmentsData: Data = Data()
        var calorieDurationEstimated: Bool = false
        var estimatedCalories: Int?
        var calorieMET: Double?

        init(id: UUID, date: Date) {
            self.id = id
            self.date = date
            exercise = "虚构旧库训练"
            notes = "用户原始事实"
            mediaKindRaw = "none"
            estimatedCalories = 500
            calorieMET = 5
        }
    }
}

@MainActor
final class EnergyDiskCompatibilityTests: XCTestCase {
    func testOldDiskStoreAddsNullableScopeAndEvidenceTablesWithoutRebuildingRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("energy-compat-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store"), id = UUID(), date = Date(timeIntervalSince1970: 1_793_000_000)
        try writeLegacy(url: url, id: id, date: date)
        let schema = Schema(SomaDataSchema.models)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let row = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<WorkoutEntry>()).first)
        XCTAssertEqual(row.id, id)
        XCTAssertEqual(row.date, date)
        XCTAssertEqual(row.notes, "用户原始事实")
        XCTAssertEqual(row.estimatedCalories, 500)
        XCTAssertEqual(row.calorieMET, 5)
        XCTAssertNil(row.calorieScopeRaw)
        XCTAssertEqual(row.calorieScope, .unknown)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<EnergyContextEntry>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<EnergyEvidenceEntry>()), 0)
        try EnergyEvidenceStore.saveConfirmation(.init(trainingComplete: true), for: date, in: container.mainContext)
        try EnergyEvidenceStore.append(EnergyReferenceDay(effectiveFrom: date, factor: 1.4, reason: "虚构参考"), kind: .reference,
                                       date: date, reason: "虚构参考", in: container.mainContext)
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<WorkoutEntry>()), 1)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<EnergyContextEntry>()), 1)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<EnergyEvidenceEntry>()), 1)
    }

    private func writeLegacy(url: URL, id: UUID, date: Date) throws {
        let schema = Schema([LegacyEnergyStore.WorkoutEntry.self])
        XCTAssertEqual(schema.entities.first?.name, "WorkoutEntry")
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        container.mainContext.insert(LegacyEnergyStore.WorkoutEntry(id: id, date: date))
        try container.mainContext.save()
    }
}
