@testable import Soma
import SwiftData
import XCTest

@MainActor
final class BodyMassImportTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        container = try ModelContainer(
            for: Schema(SomaDataSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDown() async throws {
        container = nil
    }

    func testKeepAndUnknownSourceMapping() {
        let keep = BodyMassKnownSource.resolve(name: "Keep", bundleIdentifier: "com.gotokeep.keep")
        XCTAssertEqual(keep, .keep)
        XCTAssertTrue(keep.accessibilityLabel.contains("自备识别标"))
        XCTAssertTrue(keep.accessibilityLabel.contains("非官方"))
        XCTAssertTrue(keep.listCaption.contains("自备识别标"))
        XCTAssertEqual(
            BodyMassKnownSource.resolve(name: "Health", bundleIdentifier: "com.apple.health"),
            .appleHealth
        )
        let unknown = BodyMassKnownSource.resolve(name: "Acme Scale", bundleIdentifier: "com.acme.scale")
        XCTAssertEqual(unknown, .unknown(displayName: "Acme Scale"))
        XCTAssertEqual(unknown.accessibilityLabel, "Acme Scale")
    }

    func testIdempotentUpsertPreservesManualEntries() throws {
        let context = container.mainContext
        let manual = BodyEntry(date: Date(timeIntervalSince1970: 1_700_000_000), weight: 70, notes: "manual")
        context.insert(manual)
        try context.save()

        let sampleID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let first = BodyMassSyncDelta(
            upserts: [
                BodyMassSampleImport(
                    sampleUUID: sampleID,
                    date: Date(timeIntervalSince1970: 1_700_000_100),
                    weightKilograms: 71.2,
                    sourceName: "Keep",
                    sourceBundleIdentifier: "com.gotokeep.keep"
                )
            ],
            deletedSampleUUIDs: [],
            newAnchorData: Data([1, 2, 3])
        )
        try BodyMassRecordStore.apply(first, in: context)
        try BodyMassRecordStore.saveAnchorData(first.newAnchorData, in: context)

        let second = BodyMassSyncDelta(
            upserts: [
                BodyMassSampleImport(
                    sampleUUID: sampleID,
                    date: Date(timeIntervalSince1970: 1_700_000_100),
                    weightKilograms: 71.5,
                    sourceName: "Keep",
                    sourceBundleIdentifier: "com.gotokeep.keep"
                )
            ],
            deletedSampleUUIDs: [],
            newAnchorData: Data([4, 5, 6])
        )
        try BodyMassRecordStore.apply(second, in: context)

        let bodies = try context.fetch(FetchDescriptor<BodyEntry>())
        XCTAssertEqual(bodies.count, 2)
        let imported = bodies.filter(\.isHealthImported)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.weight, 71.5)
        XCTAssertEqual(imported.first?.sourceName, "Keep")
        XCTAssertEqual(imported.first?.externalID, BodyMassImportIdentity.externalID(sampleUUID: sampleID))
        XCTAssertEqual(bodies.filter { !$0.isHealthImported }.count, 1)
        XCTAssertEqual(try BodyMassRecordStore.loadAnchorData(in: context), Data([1, 2, 3]))
        try BodyMassRecordStore.saveAnchorData(second.newAnchorData, in: context)
        XCTAssertEqual(try BodyMassRecordStore.loadAnchorData(in: context), Data([4, 5, 6]))
    }

    func testDeletionRemovesImportedSampleOnly() throws {
        let context = container.mainContext
        let sampleID = UUID()
        let otherID = UUID()
        try BodyMassRecordStore.apply(
            BodyMassSyncDelta(
                upserts: [
                    .init(
                        sampleUUID: sampleID, date: .now, weightKilograms: 68,
                        sourceName: "Keep", sourceBundleIdentifier: "com.gotokeep.keep"
                    ),
                    .init(
                        sampleUUID: otherID, date: .now.addingTimeInterval(-3600), weightKilograms: 69,
                        sourceName: "Acme", sourceBundleIdentifier: "com.acme"
                    )
                ],
                deletedSampleUUIDs: [],
                newAnchorData: nil
            ),
            in: context
        )
        try BodyMassRecordStore.apply(
            BodyMassSyncDelta(upserts: [], deletedSampleUUIDs: [sampleID], newAnchorData: nil),
            in: context
        )
        let remaining = try context.fetch(FetchDescriptor<BodyEntry>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.externalID, BodyMassImportIdentity.externalID(sampleUUID: otherID))
    }

    func testBackupAndAgentFiltersExcludeHealthImports() throws {
        let context = container.mainContext
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_100_000)
        context.insert(UserProfile(updatedAt: older, displayName: "夹具用户", height: 170))
        context.insert(BodyEntry(date: older, weight: 70, notes: "manual"))
        try BodyMassRecordStore.apply(
            BodyMassSyncDelta(
                upserts: [
                    .init(
                        sampleUUID: UUID(), date: newer, weightKilograms: 71.25,
                        sourceName: "Keep", sourceBundleIdentifier: "com.gotokeep.keep"
                    )
                ],
                deletedSampleUUIDs: [],
                newAnchorData: nil
            ),
            in: context
        )
        let snapshot = try PersonalDataSnapshot.capture(from: context).withoutHealthActivity()
        XCTAssertEqual(snapshot.bodyEntries.count, 1)
        XCTAssertNil(snapshot.bodyEntries.first?.externalSource)
        XCTAssertEqual(snapshot.bodyEntries.first?.weight, 70)

        let pack = AgentContextPackBuilder.build(
            gyms: [],
            equipment: [],
            in: context,
            businessDate: newer
        )
        // 最新体重可来自健康导入；批量趋势只用手动记录，且不暴露 Keep 来源名。
        XCTAssertTrue(pack.contains("最新体重"))
        XCTAssertTrue(pack.contains("71."))
        XCTAssertTrue(pack.contains("体重：70"))
        XCTAssertFalse(pack.contains("Keep"))
    }
}
