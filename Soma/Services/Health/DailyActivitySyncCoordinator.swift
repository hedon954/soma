import Foundation
import Observation
import SwiftData

extension Notification.Name {
    static let personalDataDidReplace = Notification.Name("Soma.personalDataDidReplace")
}

@Observable
@MainActor
final class DailyActivitySyncCoordinator {
    private(set) var isEnabled = false
    private(set) var isPrepared = false
    private(set) var isConnecting = false
    private(set) var hasRequestedTrainingAccess = false
    private(set) var needsCleanup = false
    private(set) var errorMessage: String?
    private(set) var generation = 0
    private(set) var space: DataSpace = .demo
    private(set) var summaries: [DailyActivityDayKey: DailyActivitySummary] = [:]
    private let reader: any DailyActivityReading
    private let cache: HealthConnectionStore
    @ObservationIgnored private var recordContext: ModelContext?
    private var tasks: [String: Task<Void, Never>] = [:]
    private var foreground = false
    private var automaticDays: Set<DailyActivityDayKey> = []
    private var historyOwner: UUID?
    private var historyDay: DailyActivityDayKey?
    private var historyRequest = UUID()
    private var connectionRevision = 0

    init(reader: any DailyActivityReading = HealthKitDailyActivityReader(), cache: HealthConnectionStore = HealthConnectionStore()) {
        self.reader = reader
        self.cache = cache
    }

    func bind(context: ModelContext?) {
        recordContext = context
    }

    var isAvailable: Bool {
        reader.isAvailable
    }

    func prepare() async {
        guard !isPrepared else { return }
        let token = connectionRevision
        let enabled = await cache.prepare()
        let trainingRequested = await cache.hasRequestedTrainingAccess()
        guard token == connectionRevision else { return }
        isEnabled = enabled
        hasRequestedTrainingAccess = trainingRequested
        isPrepared = true
    }

    func connect() async {
        guard space == .personal, foreground, !isConnecting, !needsCleanup else { return }
        guard isAvailable else {
            errorMessage = "此设备无法使用 Apple 健康。"
            return
        }
        isConnecting = true
        let token = connectionRevision
        defer { isConnecting = false }
        do {
            try await reader.requestAuthorization()
            guard token == connectionRevision, space == .personal, foreground else { return }
            guard try await cache.setConnected(true, generation: generation) else { return }
            guard token == connectionRevision else { return }
            isEnabled = true
            hasRequestedTrainingAccess = true
            errorMessage = nil
            refresh()
        } catch {
            guard token == connectionRevision else { return }
            errorMessage = "无法连接 Apple 健康，请稍后重试；也可在系统健康访问中检查 Soma 的设置。"
        }
    }

    func disconnect() async {
        let token = beginDisconnect()
        await finishDisconnect(generation: token)
    }

    func beginDisconnect() -> Int {
        connectionRevision &+= 1
        needsCleanup = true
        cancelAll()
        isEnabled = false
        hasRequestedTrainingAccess = false
        isPrepared = true
        isConnecting = false
        summaries = [:]
        return generation
    }

    func finishDisconnect(generation token: Int) async {
        do {
            _ = try await cache.setConnected(false, generation: token)
            if token == generation {
                needsCleanup = false
                errorMessage = nil
            }
        } catch {
            if token == generation {
                errorMessage = "读取已停止，连接设置清除失败，请重试断开。"
            }
        }
    }

    func setContext(space: DataSpace, foreground: Bool, now: Date = .now, calendar: Calendar = .current) {
        self.space = space
        self.foreground = foreground
        cancelAll()
        summaries = [:]
        guard isPrepared, isEnabled, foreground, space == .personal else { return }
        errorMessage = nil
        let window = DailyActivityWindow(containing: now, now: now, calendar: calendar, recent: true)
        automaticDays = Set(window.days)
        monitor(window, slot: "automatic")
    }

    func refresh(now: Date = .now, calendar: Calendar = .current) {
        setContext(space: space, foreground: foreground, now: now, calendar: calendar)
    }

    func select(date: Date, owner: UUID, now: Date = .now, calendar: Calendar = .current) {
        let key = DailyActivityDayKey(date: date, calendar: calendar)
        guard historyOwner != owner || historyDay != key || tasks["history"] == nil else { return }
        historyOwner = owner
        historyDay = key
        historyRequest = UUID()
        tasks.removeValue(forKey: "history")?.cancel()
        guard space == .personal, isEnabled, foreground, isPrepared else { return }
        guard !automaticDays.contains(key), key.start <= now else { return }
        monitor(DailyActivityWindow(containing: date, now: now, calendar: calendar, recent: false), slot: "history")
    }

    func releaseSelection(owner: UUID) {
        guard historyOwner == owner else { return }
        historyOwner = nil
        historyDay = nil
        historyRequest = UUID()
        tasks.removeValue(forKey: "history")?.cancel()
    }

    func summary(for date: Date, calendar: Calendar = .current) -> DailyActivitySummary? {
        let key = DailyActivityDayKey(date: date, calendar: calendar)
        if space == .demo {
            return Self.demo(key: key)
        }
        return summaries[key]
    }

    private func cancelAll() {
        generation &+= 1
        for task in tasks.values {
            task.cancel()
        }
        tasks = [:]
        automaticDays = []
        historyDay = nil
        historyRequest = UUID()
    }

    private func monitor(_ requestedWindow: DailyActivityWindow, slot: String) {
        var window = requestedWindow
        do {
            if let recordContext {
                window.localTrainingIntervals = try LocalEnergyTraining.intervals(in: window, context: recordContext)
            }
        } catch {
            errorMessage = "本机训练时段暂时无法读取，请重新读取活动。"
            return
        }
        let token = generation
        let historyToken = historyRequest
        for key in window.days {
            summaries[key] = DailyActivitySummary(key: key)
        }
        tasks[slot] = Task { [weak self, reader] in
            guard !Task.isCancelled else { return }
            let stream = await reader.updates(in: window)
            for await update in stream {
                guard let self, !Task.isCancelled, generation == token,
                      space == .personal, isEnabled, foreground,
                      slot != "history" || historyRequest == historyToken
                else { return }
                apply(update, window: window)
                do {
                    if let recordContext {
                        if case let .trainingEvidence(entries) = update {
                            for entry in entries where window.days.contains(entry.day) {
                                try EnergyEvidenceStore.append(entry, kind: .healthActivity, date: entry.day.start,
                                                               reason: "更新训练与训练时段外的步行依据", in: recordContext, saveImmediately: false)
                            }
                            if recordContext.hasChanges {
                                try recordContext.save()
                            }
                        } else {
                            try DailyActivityRecordStore.replace(window.days.compactMap { self.summaries[$0] }, in: recordContext)
                        }
                    }
                } catch {
                    recordContext?.rollback()
                    guard generation == token else { return }
                    errorMessage = "活动数据已读取，运动记录暂时无法保存，请重新读取。"
                }
            }
        }
    }

    private func apply(_ update: DailyActivityUpdate, window: DailyActivityWindow) {
        switch update {
        case let .values(kind, values, date):
            for entry in values where window.days.contains(entry.key) {
                var summary = summaries[entry.key] ?? DailyActivitySummary(key: entry.key)
                summary[kind].replace(value: entry.value, readAt: date)
                summaries[entry.key] = summary
            }
        case let .sources(kind, values):
            for entry in values where window.days.contains(entry.key) {
                guard var summary = summaries[entry.key], summary[kind].availability == .value else { continue }
                summary[kind].source = entry.source
                summaries[entry.key] = summary
            }
        case let .failure(kind):
            errorMessage = "部分活动数据读取失败，请重新读取。"
            for key in window.days {
                summaries[key]?[kind].availability = .failed
            }
        case let .sourceFailure(kind):
            for key in window.days {
                summaries[key]?[kind].source = nil
            }
        case .trainingEvidence: break
        case .trainingFailure:
            errorMessage = "训练或训练时段外的步行暂时无法读取，已保留先前依据。"
        }
    }

    static func demo(key: DailyActivityDayKey) -> DailyActivitySummary {
        var summary = DailyActivitySummary(key: key)
        for (kind, value) in [(DailyActivityMetricKind.steps, 8640.0), (.walkingRunningDistance, 6100), (.activeEnergy, 486)] {
            summary[kind].replace(value: value, readAt: key.start)
            var sources = [HealthDataSource(name: "COROS（演示）", bundleIdentifier: "example.soma.demo.coros")]
            if kind == .walkingRunningDistance {
                sources.append(.init(name: "iPhone（演示）", bundleIdentifier: "example.soma.demo.phone"))
            }
            summary[kind].source = ActivitySourceAttribution(
                sources: sources, readAt: key.start
            )
        }
        return summary
    }
}
