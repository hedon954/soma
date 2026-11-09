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
            Task { await reader.stopObserving() }
            observing = false
        }
    }

    func setContext(space: DataSpace, foreground: Bool) {
        self.space = space
        self.foreground = foreground
        guard isEnabled, foreground, space == .personal, recordContext != nil else {
            cancel()
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
        guard isEnabled, space == .personal, !observing else { return }
        observing = true
        Task { [weak self] in
            guard let self else { return }
            await reader.startObserving { [weak self] in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        }
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
            guard !Task.isCancelled, token == generation else { return }
            try BodyMassRecordStore.apply(delta, in: context)
            if let newAnchor = delta.newAnchorData {
                try BodyMassRecordStore.saveAnchorData(newAnchor, in: context)
            }
        } catch {
            // 前台失败不打断日活动；下一次回前台再追赶。
        }
    }
}
