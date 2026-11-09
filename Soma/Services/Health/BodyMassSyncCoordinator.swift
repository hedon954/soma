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
            let anchor = try BodyMassRecordStore.loadAnchorData(in: context)
            let delta = try await reader.pull(anchorData: anchor)
            guard !Task.isCancelled, token == generation, isEnabled, space == .personal else { return }
            // 仅删除 HealthKit 明确回报的 deleted UUID；空结果（含权限拒绝无法区分的情况）不擦除本地导入。
            try BodyMassRecordStore.apply(delta, in: context)
            guard !Task.isCancelled, token == generation, isEnabled, space == .personal else { return }
            if let newAnchor = delta.newAnchorData {
                try BodyMassRecordStore.saveAnchorData(newAnchor, in: context)
            }
        } catch {
            // 失败不推进擦除、不改写游标；下次前台再追赶。
        }
    }
}
