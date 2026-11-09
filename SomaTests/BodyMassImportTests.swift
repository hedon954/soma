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

    func testCombinedTrendModelKeepsIndependentSortedSeries() throws {
        let calendar = Calendar(identifier: .gregorian)
        func day(_ offset: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1 + offset)))
        }
        // 交错时刻：若 LineMark 未分 series，SwiftCharts 会按时间把体脂点连到体重点。
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9)))
        let model = try BodyHistoryTrendChartModel.make(
            weights: [
                (id: UUID(), date: day(10), value: 71.2),
                (id: UUID(), date: day(40), value: 72.4),
                (id: UUID(), date: day(5), value: 70.9)
            ],
            bodyFats: [
                (id: UUID(), date: day(0), value: 18.0),
                (id: UUID(), date: day(30), value: 18.6),
                (id: UUID(), date: day(12), value: 17.8)
            ],
            range: .year,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(model.weightPoints.map(\.value), [70.9, 71.2, 72.4])
        XCTAssertEqual(model.bodyFatPoints.map(\.value), [18.0, 17.8, 18.6])
        XCTAssertTrue(model.weightPoints.map(\.date).isSortedChronologically)
        XCTAssertTrue(model.bodyFatPoints.map(\.date).isSortedChronologically)
        XCTAssertTrue(model.weightPoints.allSatisfy { $0.id.hasPrefix(BodyHistoryTrendSeriesKey.weight.rawValue) })
        XCTAssertTrue(model.bodyFatPoints.allSatisfy { $0.id.hasPrefix(BodyHistoryTrendSeriesKey.bodyFat.rawValue) })
        XCTAssertEqual(Set(model.weightPoints.map(\.id)).count, model.weightPoints.count)
        XCTAssertEqual(Set(model.bodyFatPlotPoints.map(\.id)).count, model.bodyFatPlotPoints.count)

        // 映射后体脂绘图 Y 落在体重域内，且不等于真实百分点（防混单位直绘）。
        for (display, plot) in zip(model.bodyFatPoints, model.bodyFatPlotPoints) {
            XCTAssertEqual(display.date, plot.date)
            XCTAssertNotEqual(plot.value, display.value, accuracy: 0.0001)
            XCTAssertGreaterThanOrEqual(plot.value, model.weightDomain.lowerBound - 0.0001)
            XCTAssertLessThanOrEqual(plot.value, model.weightDomain.upperBound + 0.0001)
        }

        // 混排时必然出现跨系列相邻；独立 series 渲染不得把这些相邻画成连线。
        XCTAssertGreaterThan(model.illicitCrossSeriesAdjacencies, 0)
        XCTAssertEqual(model.weightPoints.count, 3)
        XCTAssertEqual(model.bodyFatPlotPoints.count, 3)

        let labels = model.xAxisTickDates.map { BodyHistoryTrendChartModel.compactAxisDate($0) }
        XCTAssertEqual(labels.count, 3)
        XCTAssertFalse(labels.contains(where: { $0.contains("…") || $0.contains("月") }))
        XCTAssertTrue(labels.allSatisfy { $0.contains("/") })
    }

    func testCombinedTrendModelWeightOnlyAndFatOnlyAndEmpty() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12)))
        let weightOnly = BodyHistoryTrendChartModel.make(
            weights: [(id: UUID(), date: day, value: 70)],
            bodyFats: [],
            range: .week,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(weightOnly.hasWeight)
        XCTAssertFalse(weightOnly.hasBodyFat)
        XCTAssertEqual(weightOnly.bodyFatPlotPoints.count, 0)
        XCTAssertEqual(weightOnly.illicitCrossSeriesAdjacencies, 0)

        let fatOnly = BodyHistoryTrendChartModel.make(
            weights: [],
            bodyFats: [(id: UUID(), date: day, value: 18.2)],
            range: .week,
            now: now,
            calendar: calendar
        )
        XCTAssertFalse(fatOnly.hasWeight)
        XCTAssertTrue(fatOnly.hasBodyFat)
        XCTAssertEqual(try XCTUnwrap(fatOnly.bodyFatPlotPoints.first).value, 18.2, accuracy: 0.0001)

        let empty = BodyHistoryTrendChartModel.make(
            weights: [],
            bodyFats: [],
            range: .week,
            now: now,
            calendar: calendar
        )
        XCTAssertFalse(empty.hasWeight)
        XCTAssertFalse(empty.hasBodyFat)
        XCTAssertEqual(empty.illicitCrossSeriesAdjacencies, 0)
    }

    func testTrendRangeWindowsUseCalendarNowNotLatestSample() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 15)))
        let week = BodyHistoryTrendRange.week.window(now: now, calendar: calendar)
        XCTAssertEqual(calendar.startOfDay(for: week.start), calendar.date(from: DateComponents(year: 2026, month: 11, day: 3)))
        XCTAssertEqual(week.end, calendar.date(from: DateComponents(year: 2026, month: 11, day: 10)))
        XCTAssertTrue(try week.contains(XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 23)))))
        XCTAssertFalse(week.contains(week.end))

        let month = BodyHistoryTrendRange.month.window(now: now, calendar: calendar)
        XCTAssertEqual(month.start, calendar.date(from: DateComponents(year: 2026, month: 10, day: 9)))
        let three = BodyHistoryTrendRange.threeMonths.window(now: now, calendar: calendar)
        XCTAssertEqual(three.start, calendar.date(from: DateComponents(year: 2026, month: 8, day: 9)))
        let year = BodyHistoryTrendRange.year.window(now: now, calendar: calendar)
        XCTAssertEqual(year.start, calendar.date(from: DateComponents(year: 2025, month: 11, day: 9)))
        XCTAssertEqual(BodyHistoryTrendRange.default, .month)
    }

    func testTrendModelFiltersBySelectedRangeAndKeepsSharedDomain() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12)))
        let inside = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 8)))
        let outside = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 8)))
        let farFutureSample = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))
        let model = BodyHistoryTrendChartModel.make(
            weights: [
                (id: UUID(), date: inside, value: 71.0),
                (id: UUID(), date: outside, value: 80.0),
                (id: UUID(), date: farFutureSample, value: 90.0)
            ],
            bodyFats: [
                (id: UUID(), date: inside, value: 18.0),
                (id: UUID(), date: outside, value: 22.0)
            ],
            range: .month,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(model.weightPoints.map(\.value), [71.0])
        XCTAssertEqual(model.bodyFatPoints.map(\.value), [18.0])
        let window = BodyHistoryTrendRange.month.window(now: now, calendar: calendar)
        XCTAssertEqual(model.sharedDateDomain.lowerBound, window.start)
        XCTAssertLessThan(model.sharedDateDomain.upperBound, window.end)
        XCTAssertEqual(model.range, .month)

        let weekEmpty = BodyHistoryTrendChartModel.make(
            weights: [(id: UUID(), date: outside, value: 80)],
            bodyFats: [],
            range: .week,
            now: now,
            calendar: calendar
        )
        XCTAssertFalse(weekEmpty.hasWeight)
        XCTAssertFalse(weekEmpty.hasBodyFat)
        XCTAssertEqual(
            weekEmpty.sharedDateDomain.lowerBound,
            BodyHistoryTrendRange.week.window(now: now, calendar: calendar).start
        )
    }

    func testTrendModelHidesPermanentPointsWhenDense() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9)))
        let weights = (0 ..< 20).map { offset -> (id: UUID, date: Date, value: Double) in
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            return (id: UUID(), date: date, value: 70 + Double(offset % 3))
        }
        let model = BodyHistoryTrendChartModel.make(
            weights: weights,
            bodyFats: [],
            range: .month,
            now: now,
            calendar: calendar
        )
        XCTAssertGreaterThan(model.weightPoints.count, BodyHistoryTrendChartModel.permanentPointLimit)
        XCTAssertFalse(model.showsPermanentPoints)
    }

    func testTrendSelectionPicksSingleNearestSampleInPlotSpace() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12)))
        let weightDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12)))
        let fatDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 10)))
        let model = BodyHistoryTrendChartModel.make(
            weights: [(id: UUID(), date: weightDate, value: 72.4)],
            bodyFats: [(id: UUID(), date: fatDate, value: 18.6)],
            range: .week,
            now: now,
            calendar: calendar
        )
        // 点在体重绘图位置附近，应只命中体重，不拼体脂。
        let weightHit = try XCTUnwrap(
            BodyHistoryTrendSelectionResolver.nearest(
                date: weightDate,
                plotY: 72.4,
                in: model,
                maxNormalizedDistance: 0.2
            )
        )
        XCTAssertEqual(weightHit.series, .weight)
        XCTAssertEqual(weightHit.displayValue, 72.4, accuracy: 0.0001)
        XCTAssertEqual(weightHit.unit, "kg")

        let fatPlot = try XCTUnwrap(model.bodyFatPlotPoints.first).value
        let fatHit = try XCTUnwrap(
            BodyHistoryTrendSelectionResolver.nearest(
                date: fatDate,
                plotY: fatPlot,
                in: model,
                maxNormalizedDistance: 0.2
            )
        )
        XCTAssertEqual(fatHit.series, .bodyFat)
        XCTAssertEqual(fatHit.displayValue, 18.6, accuracy: 0.0001)
        XCTAssertEqual(fatHit.unit, "%")
        XCTAssertNotEqual(fatHit.plotValue, fatHit.displayValue, accuracy: 0.0001)

        let miss = try BodyHistoryTrendSelectionResolver.nearest(
            date: XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5))),
            plotY: model.plotDomain.lowerBound,
            in: model,
            maxNormalizedDistance: 0.05
        )
        XCTAssertNil(miss)
    }

    func testTrendSelectionClearsWhenOutsideSelectedRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9)))
        let recent = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 8)))
        let old = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let yearModel = BodyHistoryTrendChartModel.make(
            weights: [
                (id: UUID(), date: recent, value: 71),
                (id: UUID(), date: old, value: 80)
            ],
            bodyFats: [],
            range: .year,
            now: now,
            calendar: calendar
        )
        let oldPoint = try XCTUnwrap(yearModel.weightPoints.first { abs($0.value - 80) < 0.01 })
        let selection = BodyHistoryTrendSelection(
            id: oldPoint.id,
            series: .weight,
            date: oldPoint.date,
            displayValue: oldPoint.value,
            plotValue: oldPoint.value
        )
        let weekModel = BodyHistoryTrendChartModel.make(
            weights: [
                (id: UUID(), date: recent, value: 71),
                (id: UUID(), date: old, value: 80)
            ],
            bodyFats: [],
            range: .week,
            now: now,
            calendar: calendar
        )
        XCTAssertNil(BodyHistoryTrendSelectionResolver.validated(selection, in: weekModel))
        XCTAssertNotNil(BodyHistoryTrendSelectionResolver.validated(selection, in: yearModel))
    }
}

private extension [Date] {
    var isSortedChronologically: Bool {
        zip(self, dropFirst()).allSatisfy { $0 <= $1 }
    }
}
