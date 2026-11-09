import HealthKit
@testable import Soma
import SwiftData
import XCTest

final class DailyActivityValueTests: XCTestCase {
    func testReadTypesIncludeDailyQuantitiesBodyMassBodyFatAndMinimalWorkoutWithoutRestingEnergy() {
        XCTAssertEqual(Set(HealthKitDailyActivityReader.readTypes.map(\.identifier)), Set([
            HKQuantityTypeIdentifier.stepCount.rawValue,
            HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
            HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
            HKQuantityTypeIdentifier.bodyMass.rawValue,
            HKQuantityTypeIdentifier.bodyFatPercentage.rawValue,
            HKWorkoutTypeIdentifier
        ]))
    }

    func testReplacementPreservesNilZeroAndNeverAccumulates() {
        var metric = DailyActivityMetric()
        let source = HealthDataSource(name: "COROS", bundleIdentifier: "example.coros")
        metric.replace(value: 9000, readAt: .now)
        metric.source = .init(sources: [source], readAt: .now)
        metric.replace(value: 100, readAt: .now)
        XCTAssertEqual(metric.value, 100)
        XCTAssertNil(metric.source)
        metric.replace(value: 0, readAt: .now)
        XCTAssertEqual(metric.value, 0)
        XCTAssertEqual(metric.availability, .value)
        metric.replace(value: nil, readAt: .now)
        XCTAssertNil(metric.value)
        XCTAssertEqual(metric.availability, .noReadableData)
        for value in [-1.0, .infinity, .nan] {
            metric.replace(value: value, readAt: .now)
            XCTAssertNil(metric.value)
            XCTAssertEqual(metric.availability, .failed)
        }
    }

    func testSourceIdentityDoesNotUseNameOrDuplicateVersionRows() throws {
        let source = try XCTUnwrap(ActivitySourceAttribution(sources: [
            .init(name: "COROS 旧名", bundleIdentifier: "example.coros"),
            .init(name: "COROS", bundleIdentifier: "example.coros"),
            .init(name: "COROS", bundleIdentifier: "example.other")
        ], readAt: .now))
        XCTAssertEqual(source.sources.count, 2)
        XCTAssertEqual(source.label, "多来源")
        XCTAssertEqual(source.sources[0].name, "COROS")
        XCTAssertNil(ActivitySourceAttribution(sources: [], readAt: .now))
    }

    func testCalendarDaysUseDSTAndKeepTimezoneInIdentity() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let spring = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let autumn = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let springKey = DailyActivityDayKey(date: spring, calendar: calendar)
        let autumnKey = DailyActivityDayKey(date: autumn, calendar: calendar)
        XCTAssertEqual(springKey.end.timeIntervalSince(springKey.start), 23 * 3600)
        XCTAssertEqual(autumnKey.end.timeIntervalSince(autumnKey.start), 25 * 3600)
        XCTAssertEqual(DailyActivityWindow(containing: spring, now: spring, calendar: calendar, recent: true).days.count, 30)
        XCTAssertTrue(DailyActivityWindow(containing: springKey.end, now: spring, calendar: calendar, recent: false).days.isEmpty)
        var shanghai = calendar
        shanghai.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        XCTAssertNotEqual(springKey, DailyActivityDayKey(date: spring, calendar: shanghai))
    }
}

final class HealthConnectionStoreTests: XCTestCase {
    func testConnectionPersistsAndRejectsLateReconnectAfterDisconnect() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let connection = root.appending(path: "connection")
        let store = HealthConnectionStore(cacheDirectory: root.appending(path: "cache"), connectionDirectory: connection)
        _ = try await store.setConnected(true, generation: 1)
        let enabled = await store.prepare()
        XCTAssertTrue(enabled)
        XCTAssertEqual(try connection.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        _ = try await store.setConnected(false, generation: 2)
        let reenable = try await store.setConnected(true, generation: 1)
        XCTAssertFalse(reenable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: connection.path))
    }
}

actor ActivityReaderStub: DailyActivityReading {
    nonisolated let isAvailable = true
    private var continuations: [AsyncStream<DailyActivityUpdate>.Continuation] = []
    private(set) var windows: [DailyActivityWindow] = []
    func requestAuthorization() async throws {}
    func updates(in window: DailyActivityWindow) -> AsyncStream<DailyActivityUpdate> {
        windows.append(window)
        return AsyncStream { continuations.append($0) }
    }

    func send(_ update: DailyActivityUpdate, request: Int) {
        continuations[request].yield(update)
    }

    var count: Int {
        windows.count
    }
}

@MainActor
final class DailyActivityCoordinatorTests: XCTestCase {
    func testEachForegroundRefreshesWithoutOpeningProgressAndOverwritesDailyValues() async throws {
        let (coordinator, reader, root) = makeCoordinator()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try ModelContainer(for: Schema(SomaDataSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        coordinator.bind(context: container.mainContext)
        await coordinator.prepare()
        coordinator.setContext(space: .personal, foreground: true)
        await coordinator.connect()
        await waitFor { await reader.count == 1 }
        let key = DailyActivityDayKey(date: .now, calendar: .current)
        await reader.send(.values(.steps, [.init(key: key, value: 9000)], .now), request: 0)
        await waitFor { coordinator.summary(for: .now)?[.steps].value == 9000 }
        let first = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<WorkoutEntry>()).first)
        let recordID = first.id
        XCTAssertEqual(first.dailyActivity?[.steps].value, 9000)
        coordinator.setContext(space: .personal, foreground: false)
        coordinator.setContext(space: .personal, foreground: true)
        await waitFor { await reader.count == 2 }
        await reader.send(.values(.steps, [.init(key: key, value: 100)], .now), request: 1)
        await waitFor { coordinator.summary(for: .now)?[.steps].value == 100 }
        let rows = try container.mainContext.fetch(FetchDescriptor<WorkoutEntry>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, recordID)
        XCTAssertEqual(rows.first?.dailyActivity?[.steps].value, 100)
        await reader.send(.values(.steps, [.init(key: key, value: 99999)], .now), request: 0)
        await Task.yield()
        XCTAssertEqual(coordinator.summary(for: .now)?[.steps].value, 100)
        await reader.send(.values(.steps, [.init(key: key, value: nil)], .now), request: 1)
        await waitFor { coordinator.summary(for: .now)?[.steps].availability == .noReadableData }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<WorkoutEntry>()), 0)
        await coordinator.disconnect()
        await reader.send(.values(.steps, [.init(key: key, value: 99999)], .now), request: 1)
        await Task.yield()
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<WorkoutEntry>()), 0)
    }

    func testRelaunchRestoresConnectionAndStartsThirtyDaySyncWithoutAView() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appending(path: "cache")
        let connectionURL = root.appending(path: "connection")
        let firstCache = HealthConnectionStore(cacheDirectory: cacheURL, connectionDirectory: connectionURL)
        _ = try await firstCache.setConnected(true, generation: 1)
        let reader = ActivityReaderStub()
        let coordinator = DailyActivitySyncCoordinator(reader: reader,
                                                       cache: HealthConnectionStore(cacheDirectory: cacheURL, connectionDirectory: connectionURL))
        await coordinator.prepare()
        coordinator.setContext(space: .personal, foreground: true)
        await waitFor { await reader.count == 1 }
        let windows = await reader.windows
        XCTAssertEqual(windows.first?.days.count, 30)
        XCTAssertTrue(coordinator.isEnabled)
        coordinator.setContext(space: .demo, foreground: true)
        XCTAssertTrue(coordinator.summaries.isEmpty)
        await coordinator.disconnect()
    }

    func testOldHistoryUsesSeparateWindowAndCannotReplaceCurrentDaySource() async throws {
        let (coordinator, reader, root) = makeCoordinator()
        defer { try? FileManager.default.removeItem(at: root) }
        await coordinator.prepare()
        coordinator.setContext(space: .personal, foreground: true)
        await coordinator.connect()
        await waitFor { await reader.count == 1 }
        let oldDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -60, to: .now))
        let owner = UUID()
        coordinator.select(date: oldDate, owner: owner)
        await waitFor { await reader.count == 2 }
        let oldKey = DailyActivityDayKey(date: oldDate, calendar: .current)
        await reader.send(.values(.activeEnergy, [.init(key: oldKey, value: 300)], .now), request: 1)
        await waitFor { coordinator.summary(for: oldDate)?[.activeEnergy].value == 300 }
        coordinator.select(date: oldDate, owner: owner)
        await Task.yield()
        let requestCount = await reader.count
        XCTAssertEqual(requestCount, 2, "记录保存引起页面刷新时不能重启同一天的历史查询")
        coordinator.releaseSelection(owner: owner)
        await reader.send(.values(.activeEnergy, [.init(key: oldKey, value: 900)], .now), request: 1)
        let today = DailyActivityDayKey(date: .now, calendar: .current)
        await reader.send(.values(.activeEnergy, [.init(key: today, value: 200)], .now), request: 0)
        await waitFor { coordinator.summary(for: .now)?[.activeEnergy].value == 200 }
        XCTAssertEqual(coordinator.summary(for: oldDate)?[.activeEnergy].value, 300)
        let source = ActivitySourceAttribution(sources: [.init(name: "COROS", bundleIdentifier: "example.coros")], readAt: .now)
        await reader.send(.sources(.activeEnergy, [.init(key: today, source: source)]), request: 0)
        await waitFor { coordinator.summary(for: .now)?[.activeEnergy].source != nil }
        await reader.send(.sourceFailure(.activeEnergy), request: 0)
        await waitFor { coordinator.summary(for: .now)?[.activeEnergy].source == nil }
        XCTAssertEqual(coordinator.summary(for: .now)?[.activeEnergy].value, 200)
        await reader.send(.failure(.activeEnergy), request: 0)
        await waitFor { coordinator.summary(for: .now)?[.activeEnergy].availability == .failed }
        XCTAssertEqual(coordinator.summary(for: .now)?[.activeEnergy].value, 200)
        XCTAssertEqual(coordinator.summary(for: .now)?[.steps].availability, .loading)
        await coordinator.disconnect()
    }

    func testSourcesStayPerMetricAndDisconnectRejectsLateResults() async {
        let (coordinator, reader, root) = makeCoordinator()
        defer { try? FileManager.default.removeItem(at: root) }
        await coordinator.prepare()
        coordinator.setContext(space: .demo, foreground: true)
        await coordinator.connect()
        let demoCalls = await reader.count
        XCTAssertEqual(demoCalls, 0)
        XCTAssertFalse(coordinator.isEnabled)
        coordinator.setContext(space: .personal, foreground: true)
        await coordinator.connect()
        await waitFor { await reader.count == 1 }
        let key = DailyActivityDayKey(date: .now, calendar: .current)
        let source = ActivitySourceAttribution(sources: [.init(name: "COROS", bundleIdentifier: "example.coros")], readAt: .now)
        await reader.send(.values(.steps, [.init(key: key, value: 200)], .now), request: 0)
        await reader.send(.sources(.steps, [.init(key: key, source: source)]), request: 0)
        await waitFor { coordinator.summary(for: .now)?[.steps].source?.label == "COROS" }
        XCTAssertNil(coordinator.summary(for: .now)?[.activeEnergy].source)
        await reader.send(.values(.steps, [.init(key: key, value: 150)], .now), request: 0)
        await waitFor { coordinator.summary(for: .now)?[.steps].value == 150 }
        XCTAssertNil(coordinator.summary(for: .now)?[.steps].source)
        await coordinator.disconnect()
        await reader.send(.values(.steps, [.init(key: key, value: 99999)], .now), request: 0)
        await Task.yield()
        XCTAssertFalse(coordinator.isEnabled)
        XCTAssertTrue(coordinator.summaries.isEmpty)
    }

    private func makeCoordinator() -> (DailyActivitySyncCoordinator, ActivityReaderStub, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let reader = ActivityReaderStub()
        let cache = HealthConnectionStore(cacheDirectory: root.appending(path: "cache"), connectionDirectory: root.appending(path: "connection"))
        return (DailyActivitySyncCoordinator(reader: reader, cache: cache), reader, root)
    }

    func testPrivateTrainingFailureRetainsEvidenceAndLateResultCannotEnterDemo() async throws {
        let (coordinator, reader, root) = makeCoordinator()
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = Schema(SomaDataSchema.models)
        let personal = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let demo = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        coordinator.bind(context: personal.mainContext)
        await coordinator.prepare()
        coordinator.setContext(space: .personal, foreground: true)
        await coordinator.connect()
        await waitFor { await reader.count == 1 }
        let key = DailyActivityDayKey(date: .now, calendar: .current)
        let evidence = HealthActivityDayEvidence(day: key, training: [], excludedIntervals: [], nonTrainingKilometers: 3,
                                                 nonTrainingSteps: 5000, hasAmbiguousBoundarySamples: false, basisID: HealthActivityDayEvidence.statisticsBasis)
        await reader.send(.trainingEvidence([evidence]), request: 0)
        await waitFor { (try? personal.mainContext.fetchCount(FetchDescriptor<EnergyEvidenceEntry>())) == 1 }
        let stored = try XCTUnwrap(personal.mainContext.fetch(FetchDescriptor<EnergyEvidenceEntry>()).first?.payload)
        await reader.send(.trainingFailure, request: 0)
        await waitFor { coordinator.errorMessage != nil }
        XCTAssertEqual(try personal.mainContext.fetch(FetchDescriptor<EnergyEvidenceEntry>()).first?.payload, stored)
        coordinator.setContext(space: .demo, foreground: true)
        coordinator.bind(context: demo.mainContext)
        await reader.send(.trainingEvidence([evidence]), request: 0)
        await Task.yield()
        XCTAssertEqual(try demo.mainContext.fetchCount(FetchDescriptor<EnergyEvidenceEntry>()), 0)
        XCTAssertEqual(try personal.mainContext.fetchCount(FetchDescriptor<EnergyEvidenceEntry>()), 1)
    }

    private func waitFor(_ condition: @escaping @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
        let passed = await condition()
        XCTAssertTrue(passed, "等待异步查询事件超时")
    }
}
