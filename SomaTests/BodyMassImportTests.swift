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
        XCTAssertEqual(keep.listCaption, "Keep")
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

    func testBodyFatPercentConversionFromHealthKitFraction() {
        XCTAssertEqual(BodyFatPercentageConversion.percentPoints(fromHealthKitPercentUnit: 0.185), 18.5)
        XCTAssertEqual(BodyFatPercentageConversion.percentPoints(fromHealthKitPercentUnit: 1.0), 100)
        XCTAssertEqual(BodyFatPercentageConversion.percentPoints(fromHealthKitPercentUnit: 18.5), 18.5)
        XCTAssertNil(BodyFatPercentageConversion.percentPoints(fromHealthKitPercentUnit: 0))
        XCTAssertNil(BodyFatPercentageConversion.percentPoints(fromHealthKitPercentUnit: -0.1))
        XCTAssertNil(BodyFatPercentageConversion.percentPoints(fromHealthKitPercentUnit: 150))
        XCTAssertNil(BodyFatPercentageConversion.percentPoints(fromHealthKitPercentUnit: .nan))
    }

    func testBodyFatImportIsIndependentFromWeightSample() throws {
        let context = container.mainContext
        let weightID = UUID()
        let fatID = UUID()
        let weightDate = Date(timeIntervalSince1970: 1_700_200_000)
        let fatDate = Date(timeIntervalSince1970: 1_700_200_000 + 3600)
        try BodyMassRecordStore.apply(
            BodyMassSyncDelta(
                upserts: [
                    .init(
                        sampleUUID: weightID, date: weightDate, weightKilograms: 72.4,
                        sourceName: "Keep", sourceBundleIdentifier: "com.gotokeep.keep"
                    )
                ],
                deletedSampleUUIDs: [],
                newAnchorData: Data([9])
            ),
            in: context
        )
        try BodyMassRecordStore.applyBodyFat(
            BodyFatSyncDelta(
                upserts: [
                    .init(
                        sampleUUID: fatID, date: fatDate, bodyFatPercent: 18.2,
                        sourceName: "Keep", sourceBundleIdentifier: "com.gotokeep.keep"
                    )
                ],
                deletedSampleUUIDs: [],
                newAnchorData: Data([8])
            ),
            in: context
        )
        try BodyMassRecordStore.saveBodyFatAnchorData(Data([8]), in: context)

        let bodies = try context.fetch(FetchDescriptor<BodyEntry>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(bodies.count, 2)
        let weightRow = try XCTUnwrap(bodies.first { $0.externalID == BodyMassImportIdentity.bodyMassExternalID(sampleUUID: weightID) })
        let fatRow = try XCTUnwrap(bodies.first { $0.externalID == BodyMassImportIdentity.bodyFatExternalID(sampleUUID: fatID) })
        XCTAssertEqual(weightRow.weight, 72.4)
        XCTAssertNil(weightRow.bodyFat)
        XCTAssertNil(fatRow.weight)
        XCTAssertEqual(fatRow.bodyFat, 18.2)
        XCTAssertEqual(weightRow.sourceName, "Keep")
        XCTAssertEqual(fatRow.sourceName, "Keep")
        XCTAssertEqual(try BodyMassRecordStore.loadBodyFatAnchorData(in: context), Data([8]))
    }

    func testDeletingBodyFatDoesNotRemoveWeightImport() throws {
        let context = container.mainContext
        let weightID = UUID()
        let fatID = UUID()
        try BodyMassRecordStore.apply(
            BodyMassSyncDelta(
                upserts: [
                    .init(
                        sampleUUID: weightID, date: .now, weightKilograms: 70.5,
                        sourceName: "Keep", sourceBundleIdentifier: "com.gotokeep.keep"
                    )
                ],
                deletedSampleUUIDs: [],
                newAnchorData: nil
            ),
            in: context
        )
        try BodyMassRecordStore.applyBodyFat(
            BodyFatSyncDelta(
                upserts: [
                    .init(
                        sampleUUID: fatID, date: .now.addingTimeInterval(60), bodyFatPercent: 17.0,
                        sourceName: "Acme Scale", sourceBundleIdentifier: "com.acme.scale"
                    )
                ],
                deletedSampleUUIDs: [],
                newAnchorData: nil
            ),
            in: context
        )
        try BodyMassRecordStore.applyBodyFat(
            BodyFatSyncDelta(upserts: [], deletedSampleUUIDs: [fatID], newAnchorData: nil),
            in: context
        )
        let remaining = try context.fetch(FetchDescriptor<BodyEntry>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.externalID, BodyMassImportIdentity.bodyMassExternalID(sampleUUID: weightID))
        XCTAssertEqual(remaining.first?.weight, 70.5)
    }

    func testEmptyBodyFatDeltaDoesNotEraseImports() throws {
        let context = container.mainContext
        let fatID = UUID()
        try BodyMassRecordStore.applyBodyFat(
            BodyFatSyncDelta(
                upserts: [
                    .init(
                        sampleUUID: fatID, date: .now, bodyFatPercent: 16.5,
                        sourceName: "Keep", sourceBundleIdentifier: "com.gotokeep.keep"
                    )
                ],
                deletedSampleUUIDs: [],
                newAnchorData: nil
            ),
            in: context
        )
        // 空结果（拒权与无数据不可区分）不得擦除。
        try BodyMassRecordStore.applyBodyFat(
            BodyFatSyncDelta(upserts: [], deletedSampleUUIDs: [], newAnchorData: nil),
            in: context
        )
        let remaining = try context.fetch(FetchDescriptor<BodyEntry>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.bodyFat, 16.5)
    }

    func testFatOnlyImportDoesNotClearLatestWeight() throws {
        let context = container.mainContext
        let weightDate = Date(timeIntervalSince1970: 1_700_300_000)
        let fatDate = Date(timeIntervalSince1970: 1_700_400_000)
        try BodyMassRecordStore.apply(
            BodyMassSyncDelta(
                upserts: [
                    .init(
                        sampleUUID: UUID(), date: weightDate, weightKilograms: 73.0,
                        sourceName: "Keep", sourceBundleIdentifier: "com.gotokeep.keep"
                    )
                ],
                deletedSampleUUIDs: [],
                newAnchorData: nil
            ),
            in: context
        )
        try BodyMassRecordStore.applyBodyFat(
            BodyFatSyncDelta(
                upserts: [
                    .init(
                        sampleUUID: UUID(), date: fatDate, bodyFatPercent: 19.0,
                        sourceName: "Keep", sourceBundleIdentifier: "com.gotokeep.keep"
                    )
                ],
                deletedSampleUUIDs: [],
                newAnchorData: nil
            ),
            in: context
        )
        let latest = WorkoutCalorieCalculator.latestRecordedWeight(at: fatDate.addingTimeInterval(10), in: context)
        XCTAssertEqual(latest, 73.0)
    }

    func testBodyFatBackupFilterExcludesHealthImports() throws {
        let context = container.mainContext
        context.insert(BodyEntry(date: .now, weight: 70, bodyFat: 18, notes: "manual"))
        try BodyMassRecordStore.applyBodyFat(
            BodyFatSyncDelta(
                upserts: [
                    .init(
                        sampleUUID: UUID(), date: .now.addingTimeInterval(10), bodyFatPercent: 17.2,
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
        XCTAssertEqual(snapshot.bodyEntries.first?.bodyFat, 18)
    }

    func testDualAxisMappingRoundTripsAndPadding() {
        let source: ClosedRange<Double> = 16 ... 20
        let target: ClosedRange<Double> = 70 ... 74
        let mid = BodyHistoryDualAxisMapping.plot(18, from: source, onto: target)
        XCTAssertEqual(mid, 72, accuracy: 0.0001)
        let back = BodyHistoryDualAxisMapping.value(atPlot: mid, from: target, onto: source)
        XCTAssertEqual(back, 18, accuracy: 0.0001)
        XCTAssertEqual(
            BodyHistoryDualAxisMapping.plot(16, from: source, onto: target),
            70,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            BodyHistoryDualAxisMapping.plot(20, from: source, onto: target),
            74,
            accuracy: 0.0001
        )
        let padded = BodyHistoryDualAxisMapping.paddedRange(values: [18.0], minimumSpan: 2)
        XCTAssertLessThan(padded.lowerBound, 18)
        XCTAssertGreaterThan(padded.upperBound, 18)
        let empty = BodyHistoryDualAxisMapping.paddedRange(values: [], minimumSpan: 2)
        XCTAssertEqual(empty.lowerBound, 0)
        XCTAssertGreaterThanOrEqual(empty.upperBound, 2)
    }
}
