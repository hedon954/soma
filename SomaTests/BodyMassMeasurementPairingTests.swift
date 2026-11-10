@testable import Soma
import SwiftData
import XCTest

@MainActor
final class BodyMassMeasurementPairingTests: XCTestCase {
    private var container: ModelContainer!
    private let instant = Date(timeIntervalSince1970: 1_700_000_000)
    private let laterSameDay = Date(timeIntervalSince1970: 1_700_000_000 + 7200)
    private let nextDay = Date(timeIntervalSince1970: 1_700_000_000 + 86400)

    override func setUp() async throws {
        container = try ModelContainer(
            for: Schema(SomaDataSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDown() async throws {
        container = nil
    }

    func testSameSourceSameSecondPairsIntoOneMeasurement() {
        let weight = health(date: instant, weight: 72.4)
        let fat = health(date: instant, bodyFat: 18.6)
        let measurements = BodyMassMeasurementPairing.measurements(from: [weight, fat])
        XCTAssertEqual(measurements.count, 1)
        XCTAssertEqual(measurements[0].weight, 72.4)
        XCTAssertEqual(measurements[0].bodyFat, 18.6)
        XCTAssertEqual(measurements[0].memberIDs, [weight.id, fat.id])
        XCTAssertEqual(measurements[0].id, weight.id)
    }

    func testPairingIsIdempotentAndOrderIndependent() {
        let weight = health(date: instant, weight: 70)
        let fat = health(date: instant, bodyFat: 16)
        let forward = BodyMassMeasurementPairing.measurements(from: [weight, fat])
        let reversed = BodyMassMeasurementPairing.measurements(from: [fat, weight])
        let again = BodyMassMeasurementPairing.measurements(from: [weight, fat])
        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward, again)
        XCTAssertEqual(forward.count, 1)
    }

    func testSameSourceDifferentSecondsDoNotPair() {
        let weight = health(date: instant, weight: 72.4)
        let fat = health(date: laterSameDay, bodyFat: 18.6)
        let measurements = BodyMassMeasurementPairing.measurements(from: [weight, fat])
        XCTAssertEqual(measurements.count, 2)
        XCTAssertEqual(Set(measurements.map(\.entries.count)), [1])
    }

    func testDifferentSourcesAtSameSecondDoNotPair() {
        let weight = health(
            date: instant,
            weight: 72.4,
            name: "Keep",
            bundle: "com.gotokeep.keep"
        )
        let fat = health(
            date: instant,
            bodyFat: 18.6,
            name: "Health",
            bundle: "com.apple.health"
        )
        let measurements = BodyMassMeasurementPairing.measurements(from: [weight, fat])
        XCTAssertEqual(measurements.count, 2)
    }

    func testMissingSourceIdentityDoesNotPair() {
        let weight = health(date: instant, weight: 70, name: "", bundle: "")
        let fat = health(date: instant, bodyFat: 18, name: "", bundle: "")
        XCTAssertEqual(BodyMassMeasurementPairing.measurements(from: [weight, fat]).count, 2)
    }

    func testSourceNameFallbackPairsWhenBundlesAreMissing() {
        let weight = health(date: instant, weight: 70, name: "Keep", bundle: "")
        let fat = health(date: instant, bodyFat: 18, name: "Keep", bundle: "")
        XCTAssertEqual(BodyMassMeasurementPairing.measurements(from: [weight, fat]).count, 1)
    }

    func testDifferentDaysDoNotPair() {
        let weight = health(date: instant, weight: 70)
        let fat = health(date: nextDay, bodyFat: 18)
        XCTAssertEqual(BodyMassMeasurementPairing.measurements(from: [weight, fat]).count, 2)
    }

    func testSameDayMultipleSessionsPairIndependently() {
        let morningWeight = health(date: instant, weight: 71)
        let morningFat = health(date: instant, bodyFat: 17)
        let eveningWeight = health(date: laterSameDay, weight: 70.5)
        let eveningFat = health(date: laterSameDay, bodyFat: 16.8)
        let measurements = BodyMassMeasurementPairing.measurements(
            from: [eveningFat, morningWeight, eveningWeight, morningFat]
        )
        XCTAssertEqual(measurements.count, 2)
        let morning = measurements.first { $0.memberIDs.contains(morningWeight.id) }
        let evening = measurements.first { $0.memberIDs.contains(eveningWeight.id) }
        XCTAssertEqual(morning?.weight, 71)
        XCTAssertEqual(morning?.bodyFat, 17)
        XCTAssertEqual(evening?.weight, 70.5)
        XCTAssertEqual(evening?.bodyFat, 16.8)
    }

    func testSingleMetricStaysSingle() {
        let weight = health(date: instant, weight: 70)
        let measurements = BodyMassMeasurementPairing.measurements(from: [weight])
        XCTAssertEqual(measurements.count, 1)
        XCTAssertEqual(measurements[0].weight, 70)
        XCTAssertNil(measurements[0].bodyFat)
        XCTAssertEqual(measurements[0].entries.count, 1)
    }

    func testManualEntryDoesNotPairWithImportEvenAtSameSecond() {
        let imported = health(date: instant, weight: 72)
        let manual = BodyEntry(date: instant, bodyFat: 18, notes: "manual")
        let measurements = BodyMassMeasurementPairing.measurements(from: [imported, manual])
        XCTAssertEqual(measurements.count, 2)
    }

    func testManualEntryAlreadyHoldingBothMetricsStaysOneRow() {
        let manual = BodyEntry(date: instant, weight: 70, bodyFat: 18, waist: 80, notes: "manual")
        let measurements = BodyMassMeasurementPairing.measurements(from: [manual])
        XCTAssertEqual(measurements.count, 1)
        XCTAssertEqual(measurements[0].weight, 70)
        XCTAssertEqual(measurements[0].bodyFat, 18)
        XCTAssertEqual(measurements[0].entries.count, 1)
    }

    func testTwoWeightsAtSameSecondRemainSingle() {
        let first = health(date: instant, weight: 70)
        let second = health(date: instant, weight: 71)
        XCTAssertEqual(BodyMassMeasurementPairing.measurements(from: [first, second]).count, 2)
    }

    func testDeletingOneImportedSampleLeavesTheOther() throws {
        let context = container.mainContext
        let weightID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let fatID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"))
        try BodyMassRecordStore.apply(
            BodyMassSyncDelta(
                upserts: [
                    BodyMassSampleImport(
                        sampleUUID: weightID,
                        date: instant,
                        weightKilograms: 72.4,
                        sourceName: "Keep",
                        sourceBundleIdentifier: "com.gotokeep.keep"
                    )
                ],
                deletedSampleUUIDs: [],
                newAnchorData: Data([1])
            ),
            in: context
        )
        try BodyMassRecordStore.applyBodyFat(
            BodyFatSyncDelta(
                upserts: [
                    BodyFatSampleImport(
                        sampleUUID: fatID,
                        date: instant,
                        bodyFatPercent: 18.6,
                        sourceName: "Keep",
                        sourceBundleIdentifier: "com.gotokeep.keep"
                    )
                ],
                deletedSampleUUIDs: [],
                newAnchorData: Data([2])
            ),
            in: context
        )

        let imported = try context.fetch(FetchDescriptor<BodyEntry>()).filter(\.isHealthImported)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.weight, 72.4)
        XCTAssertEqual(imported.first?.bodyFat, 18.6)

        let dayKey = BodyMassDayKey.dayKey(for: instant)
        try BodyMassRecordStore.applyBodyFat(
            BodyFatSyncDelta(
                upserts: [],
                deletedSampleUUIDs: [fatID],
                newAnchorData: Data([3])
            ),
            in: context,
            resample: BodyMassDayResampleSet(bodyFatByDay: [dayKey: []])
        )
        let remaining = try context.fetch(FetchDescriptor<BodyEntry>()).filter(\.isHealthImported)
        XCTAssertEqual(remaining.count, 1)
        let leftover = try XCTUnwrap(remaining.first)
        XCTAssertEqual(leftover.weight, 72.4)
        XCTAssertNil(leftover.bodyFat)
        XCTAssertEqual(leftover.healthDayEvidence?.weight?.sampleUUID, weightID)
        XCTAssertNil(leftover.healthDayEvidence?.bodyFat)
    }

    func testUpdatingOneSampleDateKeepsOneDailyRecord() throws {
        let context = container.mainContext
        let weightID = try XCTUnwrap(UUID(uuidString: "CCCCCCCC-DDDD-EEEE-FFFF-AAAAAAAAAAAA"))
        let fatID = try XCTUnwrap(UUID(uuidString: "DDDDDDDD-EEEE-FFFF-AAAA-BBBBBBBBBBBB"))
        try BodyMassRecordStore.apply(
            BodyMassSyncDelta(
                upserts: [
                    BodyMassSampleImport(
                        sampleUUID: weightID,
                        date: instant,
                        weightKilograms: 70,
                        sourceName: "Keep",
                        sourceBundleIdentifier: "com.gotokeep.keep"
                    )
                ],
                deletedSampleUUIDs: [],
                newAnchorData: Data([4])
            ),
            in: context
        )
        try BodyMassRecordStore.applyBodyFat(
            BodyFatSyncDelta(
                upserts: [
                    BodyFatSampleImport(
                        sampleUUID: fatID,
                        date: instant,
                        bodyFatPercent: 16,
                        sourceName: "Keep",
                        sourceBundleIdentifier: "com.gotokeep.keep"
                    )
                ],
                deletedSampleUUIDs: [],
                newAnchorData: Data([5])
            ),
            in: context
        )
        try BodyMassRecordStore.applyBodyFat(
            BodyFatSyncDelta(
                upserts: [
                    BodyFatSampleImport(
                        sampleUUID: fatID,
                        date: laterSameDay,
                        bodyFatPercent: 16.2,
                        sourceName: "Keep",
                        sourceBundleIdentifier: "com.gotokeep.keep"
                    )
                ],
                deletedSampleUUIDs: [],
                newAnchorData: Data([6])
            ),
            in: context
        )
        let imported = try context.fetch(FetchDescriptor<BodyEntry>()).filter(\.isHealthImported)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.weight, 70)
        XCTAssertEqual(imported.first?.bodyFat, 16.2)
        XCTAssertEqual(imported.first?.healthDayEvidence?.weight?.date, instant)
        XCTAssertEqual(imported.first?.healthDayEvidence?.bodyFat?.date, laterSameDay)
        XCTAssertEqual(imported.first?.date, laterSameDay)
    }

    func testReapplyingSameSamplesKeepsOneDailyRecord() throws {
        let context = container.mainContext
        let weightID = try XCTUnwrap(UUID(uuidString: "EEEEEEEE-FFFF-AAAA-BBBB-CCCCCCCCCCCC"))
        let fatID = try XCTUnwrap(UUID(uuidString: "FFFFFFFF-AAAA-BBBB-CCCC-DDDDDDDDDDDD"))
        let weightDelta = BodyMassSyncDelta(
            upserts: [
                BodyMassSampleImport(
                    sampleUUID: weightID,
                    date: instant,
                    weightKilograms: 71.2,
                    sourceName: "Keep",
                    sourceBundleIdentifier: "com.gotokeep.keep"
                )
            ],
            deletedSampleUUIDs: [],
            newAnchorData: Data([7])
        )
        let fatDelta = BodyFatSyncDelta(
            upserts: [
                BodyFatSampleImport(
                    sampleUUID: fatID,
                    date: instant,
                    bodyFatPercent: 17.1,
                    sourceName: "Keep",
                    sourceBundleIdentifier: "com.gotokeep.keep"
                )
            ],
            deletedSampleUUIDs: [],
            newAnchorData: Data([8])
        )
        try BodyMassRecordStore.apply(weightDelta, in: context)
        try BodyMassRecordStore.applyBodyFat(fatDelta, in: context)
        try BodyMassRecordStore.apply(weightDelta, in: context)
        try BodyMassRecordStore.applyBodyFat(fatDelta, in: context)
        let imported = try context.fetch(FetchDescriptor<BodyEntry>()).filter(\.isHealthImported)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(
            imported.first?.externalID,
            BodyMassImportIdentity.bodyDayExternalID(dayKey: BodyMassDayKey.dayKey(for: instant))
        )
        XCTAssertEqual(imported.first?.healthDayEvidence?.weight?.sampleUUID, weightID)
        XCTAssertEqual(imported.first?.healthDayEvidence?.bodyFat?.sampleUUID, fatID)
    }

    func testGroupByDayKeepsSameDaySessionsSeparate() {
        let morning = health(date: instant, weight: 71)
        let morningFat = health(date: instant, bodyFat: 17)
        let evening = health(date: laterSameDay, weight: 70)
        let measurements = BodyHistoryQuery.groupedMeasurementsByDay(
            BodyMassMeasurementPairing.measurements(from: [morning, morningFat, evening])
        )
        XCTAssertEqual(measurements.count, 1)
        XCTAssertEqual(measurements[0].measurements.count, 2)
    }

    private func health(
        date: Date,
        weight: Double? = nil,
        bodyFat: Double? = nil,
        name: String = "Keep",
        bundle: String = "com.gotokeep.keep"
    ) -> BodyEntry {
        let sampleID = UUID()
        let externalID: String? = if weight != nil {
            BodyMassImportIdentity.externalID(sampleUUID: sampleID)
        } else {
            BodyMassImportIdentity.bodyFatExternalID(sampleUUID: sampleID)
        }
        return BodyEntry(
            date: date,
            weight: weight,
            bodyFat: bodyFat,
            notes: "",
            externalSource: BodyMassImportIdentity.externalSource,
            externalID: externalID,
            sourceName: name.isEmpty ? nil : name,
            sourceBundleIdentifier: bundle.isEmpty ? nil : bundle
        )
    }
}
