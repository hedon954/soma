@testable import Soma
import SwiftData
import XCTest

@MainActor
final class BodyMassDailyRecordTests: XCTestCase {
    private var container: ModelContainer!
    private var calendar: Calendar!

    override func setUp() async throws {
        container = try ModelContainer(
            for: Schema(SomaDataSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        self.calendar = calendar
    }

    override func tearDown() async throws {
        container = nil
        calendar = nil
    }

    func testLaterSampleOverwritesSameDayAndKeepsEarlierFromWinning() throws {
        let morning = date(2026, 11, 9, 8)
        let noon = date(2026, 11, 9, 12)
        let earlyID = UUID()
        let lateID = UUID()
        try applyMass([
            mass(earlyID, morning, 70.9),
            mass(lateID, noon, 72.4)
        ])
        let rows = try healthRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].weight, 72.4)
        XCTAssertEqual(rows[0].healthDayEvidence?.weight?.sampleUUID, lateID)
        XCTAssertEqual(rows[0].date, noon)
        XCTAssertEqual(
            rows[0].externalID,
            BodyMassImportIdentity.bodyDayExternalID(dayKey: "2026-11-09")
        )

        try applyMass([mass(earlyID, morning, 70.1)])
        XCTAssertEqual(try healthRows()[0].weight, 72.4)
    }

    func testFatOnlyUpdateDoesNotEraseWeight() throws {
        let morning = date(2026, 11, 9, 8)
        let evening = date(2026, 11, 9, 18)
        try applyMass([mass(UUID(), morning, 72.4)])
        try applyFat([fat(UUID(), evening, 18.6)])
        let row = try XCTUnwrap(try healthRows().first)
        XCTAssertEqual(row.weight, 72.4)
        XCTAssertEqual(row.bodyFat, 18.6)
        XCTAssertEqual(row.date, evening)
        XCTAssertEqual(row.healthDayEvidence?.weight?.date, morning)
        XCTAssertEqual(row.healthDayEvidence?.bodyFat?.date, evening)
    }

    func testMultipleSourcesShareOneDayRecordWithoutUnifiedBrand() throws {
        try applyMass([
            mass(UUID(), date(2026, 11, 9, 9), 71.0, name: "Keep", bundle: "com.gotokeep.keep")
        ])
        try applyFat([
            fat(UUID(), date(2026, 11, 9, 11), 19.0, name: "Acme Scale", bundle: "com.acme.scale")
        ])
        let row = try XCTUnwrap(try healthRows().first)
        XCTAssertEqual(try healthRows().count, 1)
        XCTAssertNil(row.sourceName)
        XCTAssertNil(row.sourceBundleIdentifier)
        XCTAssertNil(row.healthDayEvidence?.unifiedSource)
        XCTAssertEqual(row.healthDayEvidence?.sourceCaptions, ["Keep", "Acme Scale"])
    }

    func testDeletingNonWinningSampleIsNoOp() throws {
        let early = UUID()
        let late = UUID()
        try applyMass([
            mass(early, date(2026, 11, 9, 8), 70.0),
            mass(late, date(2026, 11, 9, 12), 72.0)
        ])
        try applyMass(
            [],
            deleted: [early],
            resample: BodyMassDayResampleSet(weightsByDay: [
                "2026-11-09": [mass(late, date(2026, 11, 9, 12), 72.0)]
            ])
        )
        let row = try XCTUnwrap(try healthRows().first)
        XCTAssertEqual(row.weight, 72.0)
        XCTAssertEqual(row.healthDayEvidence?.weight?.sampleUUID, late)
    }

    func testDeletingWinnerFallsBackToPreviousValidSample() throws {
        let early = UUID()
        let late = UUID()
        try applyMass([
            mass(early, date(2026, 11, 9, 8), 70.0),
            mass(late, date(2026, 11, 9, 12), 72.0)
        ])
        try applyMass(
            [],
            deleted: [late],
            resample: BodyMassDayResampleSet(weightsByDay: [
                "2026-11-09": [mass(early, date(2026, 11, 9, 8), 70.0)]
            ])
        )
        let row = try XCTUnwrap(try healthRows().first)
        XCTAssertEqual(row.weight, 70.0)
        XCTAssertEqual(row.healthDayEvidence?.weight?.sampleUUID, early)
    }

    func testDeletingWinnerWithoutResampleKeepsStoredValue() throws {
        let late = UUID()
        try applyMass([mass(late, date(2026, 11, 9, 12), 72.0)])
        try applyMass([], deleted: [late])
        let row = try XCTUnwrap(try healthRows().first)
        XCTAssertEqual(row.weight, 72.0)
        XCTAssertEqual(row.healthDayEvidence?.weight?.sampleUUID, late)
    }

    func testDeletingWinnerWithEmptyResampleClearsMetricAndRowIfEmpty() throws {
        let weightID = UUID()
        let fatID = UUID()
        try applyMass([mass(weightID, date(2026, 11, 9, 9), 72.0)])
        try applyFat([fat(fatID, date(2026, 11, 9, 10), 18.0)])
        try applyFat(
            [],
            deleted: [fatID],
            resample: BodyMassDayResampleSet(bodyFatByDay: ["2026-11-09": []])
        )
        let row = try XCTUnwrap(try healthRows().first)
        XCTAssertEqual(row.weight, 72.0)
        XCTAssertNil(row.bodyFat)

        try applyMass(
            [],
            deleted: [weightID],
            resample: BodyMassDayResampleSet(weightsByDay: ["2026-11-09": []])
        )
        XCTAssertTrue(try healthRows().isEmpty)
    }

    func testEmptyDeltaDoesNotErase() throws {
        try applyMass([mass(UUID(), date(2026, 11, 9, 9), 71.5)])
        try applyMass([])
        try applyFat([])
        XCTAssertEqual(try healthRows().count, 1)
        XCTAssertEqual(try healthRows()[0].weight, 71.5)
    }

    func testOutOfOrderUpsertDoesNotDowngrade() throws {
        let late = UUID()
        let early = UUID()
        try applyMass([mass(late, date(2026, 11, 9, 18), 73.0)])
        try applyMass([mass(early, date(2026, 11, 9, 8), 70.0)])
        XCTAssertEqual(try healthRows()[0].weight, 73.0)
        XCTAssertEqual(try healthRows()[0].healthDayEvidence?.weight?.sampleUUID, late)
    }

    func testRerunIsIdempotent() throws {
        let sample = mass(UUID(), date(2026, 11, 9, 12), 72.4)
        try applyMass([sample])
        let first = try XCTUnwrap(try healthRows().first)
        let firstID = first.id
        try applyMass([sample])
        let second = try XCTUnwrap(try healthRows().first)
        XCTAssertEqual(try healthRows().count, 1)
        XCTAssertEqual(second.id, firstID)
        XCTAssertEqual(second.weight, 72.4)
    }

    func testDayBoundaryUsesCalendarStartOfDay() throws {
        try assertDayBoundaryUsesCalendarStartOfDay(in: calendar(timeZoneIdentifier: "UTC"))
        try assertDayBoundaryUsesCalendarStartOfDay(in: calendar(timeZoneIdentifier: "Asia/Shanghai"))
    }

    private func assertDayBoundaryUsesCalendarStartOfDay(in calendar: Calendar) throws {
        for row in try healthRows() {
            container.mainContext.delete(row)
        }
        try container.mainContext.save()

        let beforeMidnight = date(2026, 11, 9, 23, 59, calendar: calendar)
        let afterMidnight = date(2026, 11, 10, 0, 0, calendar: calendar)
        try applyMass([
            mass(UUID(), beforeMidnight, 71.0),
            mass(UUID(), afterMidnight, 72.0)
        ], calendar: calendar)
        let rows = try healthRows().sorted { $0.date < $1.date }
        let zone = calendar.timeZone.identifier
        XCTAssertEqual(rows.count, 2, zone)
        XCTAssertEqual(
            rows[0].externalID,
            BodyMassImportIdentity.bodyDayExternalID(dayKey: "2026-11-09"),
            zone
        )
        XCTAssertEqual(
            rows[1].externalID,
            BodyMassImportIdentity.bodyDayExternalID(dayKey: "2026-11-10"),
            zone
        )
        XCTAssertEqual(rows[0].date, beforeMidnight, zone)
        XCTAssertEqual(rows[1].date, afterMidnight, zone)
    }

    private func calendar(timeZoneIdentifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZoneIdentifier))
        return calendar
    }

    func testLegacySampleRowsFoldIntoDailyRecordsAndPreserveManuals() throws {
        let context = container.mainContext
        let morning = date(2026, 11, 8, 8)
        let noon = date(2026, 11, 8, 12)
        let fatTime = date(2026, 11, 8, 16)
        let weightEarly = UUID()
        let weightLate = UUID()
        let fatID = UUID()
        context.insert(legacyMass(weightEarly, morning, 70.0))
        context.insert(legacyMass(weightLate, noon, 72.4))
        context.insert(legacyFat(fatID, fatTime, 18.6))
        let manual = BodyEntry(
            date: date(2026, 11, 8, 7),
            weight: 71.8,
            bodyFat: 17.5,
            waist: 79,
            notes: "手动"
        )
        context.insert(manual)
        try context.save()

        try BodyMassDailyRecordStore.foldLegacySampleRowsIfNeeded(
            in: context,
            calendar: calendar
        )
        try BodyMassDailyRecordStore.foldLegacySampleRowsIfNeeded(
            in: context,
            calendar: calendar
        )

        let all = try context.fetch(FetchDescriptor<BodyEntry>())
        XCTAssertEqual(all.count, 2)
        let imported = all.filter(\.isHealthImported)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].weight, 72.4)
        XCTAssertEqual(imported[0].bodyFat, 18.6)
        XCTAssertEqual(imported[0].healthDayEvidence?.weight?.sampleUUID, weightLate)
        XCTAssertEqual(imported[0].healthDayEvidence?.bodyFat?.sampleUUID, fatID)
        XCTAssertTrue(BodyMassImportIdentity.isDayExternalID(imported[0].externalID))
        XCTAssertFalse(all.contains { BodyMassImportIdentity.isLegacySampleExternalID($0.externalID) })
        let kept = try XCTUnwrap(all.first { !$0.isHealthImported })
        XCTAssertEqual(kept.weight, 71.8)
        XCTAssertEqual(kept.waist, 79)
        XCTAssertEqual(kept.notes, "手动")
    }

    func testRangeQueryIncludesEarliestInWindowAndExcludesEnd() throws {
        let context = container.mainContext
        let start = date(2026, 10, 10, 8)
        let mid = date(2026, 10, 20, 8)
        let onEnd = date(2026, 11, 10, 0)
        context.insert(BodyEntry(date: start, weight: 66.6, notes: "earliest"))
        context.insert(BodyEntry(date: mid, weight: 67.0))
        context.insert(BodyEntry(date: onEnd, weight: 68.0, notes: "excluded"))
        try context.save()
        let window = BodyHistoryTrendRange.Window(start: date(2026, 10, 10, 0), end: date(2026, 11, 10, 0))
        let rows = try BodyHistoryQuery.entries(in: window, context: context)
        XCTAssertEqual(rows.map(\.weight), [67.0, 66.6])
        XCTAssertTrue(try BodyHistoryQuery.hasAny(in: context))
    }

    func testManualRowsAreNeverUpdatedOrDeletedByHealthSync() throws {
        let context = container.mainContext
        let manual = BodyEntry(date: date(2026, 11, 9, 7), weight: 71.8, waist: 79, notes: "手动")
        context.insert(manual)
        try context.save()
        let sample = mass(UUID(), date(2026, 11, 9, 12), 72.4)
        try applyMass([sample])
        try applyMass(
            [],
            deleted: [sample.sampleUUID],
            resample: BodyMassDayResampleSet(weightsByDay: ["2026-11-09": []])
        )
        let manuals = try context.fetch(FetchDescriptor<BodyEntry>()).filter { !$0.isHealthImported }
        XCTAssertEqual(manuals.count, 1)
        XCTAssertEqual(manuals[0].weight, 71.8)
        XCTAssertEqual(manuals[0].waist, 79)
        XCTAssertTrue(try healthRows().isEmpty)
    }

    private func applyMass(
        _ upserts: [BodyMassSampleImport],
        deleted: [UUID] = [],
        resample: BodyMassDayResampleSet = BodyMassDayResampleSet(),
        calendar: Calendar? = nil
    ) throws {
        try BodyMassRecordStore.apply(
            BodyMassSyncDelta(upserts: upserts, deletedSampleUUIDs: deleted, newAnchorData: nil),
            in: container.mainContext,
            calendar: calendar ?? self.calendar,
            resample: resample
        )
    }

    private func applyFat(
        _ upserts: [BodyFatSampleImport],
        deleted: [UUID] = [],
        resample: BodyMassDayResampleSet = BodyMassDayResampleSet()
    ) throws {
        try BodyMassRecordStore.applyBodyFat(
            BodyFatSyncDelta(upserts: upserts, deletedSampleUUIDs: deleted, newAnchorData: nil),
            in: container.mainContext,
            calendar: calendar,
            resample: resample
        )
    }

    private func healthRows() throws -> [BodyEntry] {
        try container.mainContext.fetch(FetchDescriptor<BodyEntry>())
            .filter(\.isHealthImported)
            .sorted { $0.date < $1.date }
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int = 0,
        calendar: Calendar? = nil
    ) -> Date {
        (calendar ?? self.calendar).date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    private func mass(
        _ id: UUID,
        _ date: Date,
        _ kg: Double,
        name: String = "Keep",
        bundle: String = "com.gotokeep.keep"
    ) -> BodyMassSampleImport {
        BodyMassSampleImport(
            sampleUUID: id,
            date: date,
            weightKilograms: kg,
            sourceName: name,
            sourceBundleIdentifier: bundle
        )
    }

    private func fat(
        _ id: UUID,
        _ date: Date,
        _ percent: Double,
        name: String = "Keep",
        bundle: String = "com.gotokeep.keep"
    ) -> BodyFatSampleImport {
        BodyFatSampleImport(
            sampleUUID: id,
            date: date,
            bodyFatPercent: percent,
            sourceName: name,
            sourceBundleIdentifier: bundle
        )
    }

    private func legacyMass(_ id: UUID, _ date: Date, _ kg: Double) -> BodyEntry {
        BodyEntry(
            date: date,
            weight: kg,
            notes: "",
            analysis: "",
            externalSource: BodyMassImportIdentity.externalSource,
            externalID: BodyMassImportIdentity.bodyMassExternalID(sampleUUID: id),
            sourceName: "Keep",
            sourceBundleIdentifier: "com.gotokeep.keep"
        )
    }

    private func legacyFat(_ id: UUID, _ date: Date, _ percent: Double) -> BodyEntry {
        BodyEntry(
            date: date,
            bodyFat: percent,
            notes: "",
            analysis: "",
            externalSource: BodyMassImportIdentity.externalSource,
            externalID: BodyMassImportIdentity.bodyFatExternalID(sampleUUID: id),
            sourceName: "Keep",
            sourceBundleIdentifier: "com.gotokeep.keep"
        )
    }
}
