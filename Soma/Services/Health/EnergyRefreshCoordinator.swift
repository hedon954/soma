import Foundation
import Observation
import SwiftData

/// Owns a cancelable computation for the selected container. No View owns the energy model.
@Observable
@MainActor
final class EnergyRefreshCoordinator {
    private(set) var errorMessage: String?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var task: Task<Void, Never>?
    private var foreground = false
    private var generation = 0

    func bind(context: ModelContext?, foreground: Bool) {
        generation &+= 1
        task?.cancel()
        self.context = context
        self.foreground = foreground
        if foreground {
            refresh()
        }
    }

    func saved(_ notification: Notification) {
        guard let context, ModelContextSaveImpact.affectsEnergyInputs(notification, in: context) else { return }
        refresh()
    }

    func refresh(now: Date = .now, calendar: Calendar = .current) {
        generation &+= 1
        let token = generation
        task?.cancel()
        guard foreground, let context else { return }
        let container = context.container
        let window = ProgressPeriod.day.window(containing: now, calendar: calendar)
        task = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .utility) {
                let facts = try await ProgressHistoryLoader(modelContainer: container).load(window: window)
                try Task.checkCancellation()
                return EnergyRuntimeProjection.build(window: window, records: facts.records, profile: facts.profile, now: now, calendar: calendar)
            }
            do {
                let output = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, !Task.isCancelled, generation == token, foreground, self.context === context else { return }
                try EnergyRuntimePersistence.apply(output.updates, in: context, now: now)
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, generation == token else { return }
                errorMessage = "消耗依据暂时无法更新，请重新打开或在进展中刷新。"
            }
        }
    }
}
