import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class BodyMassSyncCoordinator {
    private let reader: any BodyMassReading
    private var recordContext: ModelContext?
    private var generation = 0
    private var space: DataSpace = .demo
    private var foreground = false
    private var isEnabled = false
    private var syncTask: Task<Void, Never>?
    private var observing = false

    init(reader: any BodyMassReading = HealthKitBodyMassReader()) {
        self.reader = reader
    }

    func bind(context: ModelContext?) {
        recordContext = context
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            cancel()
            stopObservation()
        }
    }

    func setContext(space: DataSpace, foreground: Bool) {
        self.space = space
        self.foreground = foreground
        let canSync = isEnabled && foreground && space == .personal && recordContext != nil
        guard canSync else {
            cancel()
            // 断开、演示空间或无上下文时停止观察，避免跨空间迟到回调写入。
            if !isEnabled || space != .personal || recordContext == nil {
                stopObservation()
            }
            return
        }
        refresh()
        ensureObserving()
    }

    func refresh() {
        guard isEnabled, foreground, space == .personal, let context = recordContext else { return }
        cancel()
        let token = generation
        syncTask = Task { [weak self] in
            guard let self else { return }
            await pullAndApply(token: token, context: context)
        }
    }

    private func ensureObserving() {
        guard isEnabled, space == .personal, recordContext != nil, !observing else { return }
        observing = true
        Task { [weak self] in
            guard let self else { return }
            await reader.startObserving { [weak self] in
                Task { @MainActor in
                    guard let self, self.isEnabled, self.space == .personal else { return }
                    self.refresh()
                }
            }
        }
    }

    private func stopObservation() {
        observing = false
        Task { await reader.stopObserving() }
    }

    private func cancel() {
        generation &+= 1
        syncTask?.cancel()
        syncTask = nil
    }

    private func pullAndApply(token: Int, context: ModelContext) async {
        do {
            try BodyMassDailyRecordStore.foldLegacySampleRowsIfNeeded(in: context)

            let massAnchor = try BodyMassRecordStore.loadAnchorData(in: context)
            let massDelta = try await reader.pull(anchorData: massAnchor)
            guard isCurrentGeneration(token) else { return }
            // 仅删除 HealthKit 明确回报的 deleted UUID；空结果（含权限拒绝无法区分的情况）不擦除本地导入。
            // 回退查询失败时不应用本批、不推进游标，下次用同一锚点重试。
            guard let massResample = await resampleWeights(for: massDelta, in: context), isCurrentGeneration(token) else { return }
            try BodyMassRecordStore.apply(massDelta, in: context, resample: massResample)
            guard isCurrentGeneration(token) else { return }
            if let newAnchor = massDelta.newAnchorData {
                try BodyMassRecordStore.saveAnchorData(newAnchor, in: context)
            }

            let fatAnchor = try BodyMassRecordStore.loadBodyFatAnchorData(in: context)
            let fatDelta = try await reader.pullBodyFat(anchorData: fatAnchor)
            guard isCurrentGeneration(token), let fatResample = await resampleBodyFat(for: fatDelta, in: context), isCurrentGeneration(token) else { return }
            try BodyMassRecordStore.applyBodyFat(fatDelta, in: context, resample: fatResample)
            guard isCurrentGeneration(token) else { return }
            if let newAnchor = fatDelta.newAnchorData {
                try BodyMassRecordStore.saveBodyFatAnchorData(newAnchor, in: context)
            }
        } catch {
            // 失败不推进擦除、不改写游标；下次前台再追赶。
        }
    }

    private func isCurrentGeneration(_ token: Int) -> Bool {
        !Task.isCancelled && token == generation && isEnabled && space == .personal
    }

    private func resampleWeights(
        for delta: BodyMassSyncDelta,
        in context: ModelContext,
        calendar: Calendar = .current
    ) async -> BodyMassDayResampleSet? {
        do {
            let keys = try BodyMassDailyRecordStore.dayKeysNeedingWeightResample(
                deletedSampleUUIDs: delta.deletedSampleUUIDs,
                in: context
            )
            var resample = BodyMassDayResampleSet()
            for dayKey in keys {
                guard let start = BodyMassDayKey.startOfDay(for: dayKey, calendar: calendar) else {
                    continue
                }
                let end = BodyMassDayKey.endOfDay(for: start, calendar: calendar)
                resample.weightsByDay[dayKey] = try await reader.weightSamples(from: start, to: end)
            }
            return resample
        } catch {
            return nil
        }
    }

    private func resampleBodyFat(
        for delta: BodyFatSyncDelta,
        in context: ModelContext,
        calendar: Calendar = .current
    ) async -> BodyMassDayResampleSet? {
        do {
            let keys = try BodyMassDailyRecordStore.dayKeysNeedingBodyFatResample(
                deletedSampleUUIDs: delta.deletedSampleUUIDs,
                in: context
            )
            var resample = BodyMassDayResampleSet()
            for dayKey in keys {
                guard let start = BodyMassDayKey.startOfDay(for: dayKey, calendar: calendar) else {
                    continue
                }
                let end = BodyMassDayKey.endOfDay(for: start, calendar: calendar)
                resample.bodyFatByDay[dayKey] = try await reader.bodyFatSamples(from: start, to: end)
            }
            return resample
        } catch {
            return nil
        }
    }
}
