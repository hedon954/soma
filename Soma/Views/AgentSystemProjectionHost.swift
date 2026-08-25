import SwiftData
import SwiftUI

struct AgentSystemProjectionHost: View {
    @AppStorage(AgentSystemPreference.completionNotificationsKey)
    private var completionNotificationsEnabled = false

    var body: some View {
        AgentSystemProjectionWorker(
            completionNotificationsEnabled: completionNotificationsEnabled
        )
    }
}

private struct AgentProjectionJobRevision: Hashable {
    let id: UUID
    let stateRaw: String
    let lastEventSequence: Int
    let liveActivityCursor: Int
    let notificationCursor: Int
    let remoteJobID: String?
}

private struct AgentSystemProjectionWorker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AgentSystemProjectionCoordinator.self)
    private var coordinator
    @Query private var jobs: [AgentJob]
    @State private var registeredTokens: [UUID: String] = [:]
    let completionNotificationsEnabled: Bool

    init(completionNotificationsEnabled: Bool) {
        let succeeded = AgentJobState.succeeded.rawValue
        let failed = AgentJobState.failed.rawValue
        let cancelled = AgentJobState.cancelled.rawValue
        var descriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate {
                ($0.stateRaw != succeeded
                    && $0.stateRaw != failed
                    && $0.stateRaw != cancelled)
                    || $0.liveActivityProjectionCursor < $0.lastEventSequence
                    || (completionNotificationsEnabled
                        && $0.notificationProjectionCursor < $0.lastEventSequence)
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 100
        _jobs = Query(descriptor)
        self.completionNotificationsEnabled = completionNotificationsEnabled
    }

    private var revision: [AgentProjectionJobRevision] {
        jobs.map {
            AgentProjectionJobRevision(
                id: $0.id,
                stateRaw: $0.stateRaw,
                lastEventSequence: $0.lastEventSequence,
                liveActivityCursor: $0.liveActivityProjectionCursor,
                notificationCursor: $0.notificationProjectionCursor,
                remoteJobID: $0.remoteJobID
            )
        }
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: revision) {
                // Text/Event persistence can advance the same Job many times
                // per second. Coalesce those revisions so the always-mounted
                // root worker does not compete with navigation or Tab taps.
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
                let interval = AppPerformance.begin(
                    .agentProjection,
                    detail: "jobs=\(jobs.count)"
                )
                let container = modelContext.container
                let jobIDs = jobs.map(\.id)
                let worker = Task.detached(priority: .utility) {
                    let loader = AgentProjectionOperationCountLoader(
                        modelContainer: container
                    )
                    return try await loader.load(jobIDs: jobIDs)
                }
                let operationCounts = await (try? withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }) ?? [:]
                guard !Task.isCancelled else {
                    AppPerformance.end(
                        interval,
                        detail: "jobs=\(jobs.count),cancelled=true"
                    )
                    return
                }
                await coordinator.project(
                    jobs: jobs,
                    operationCounts: operationCounts
                )
                try? modelContext.save()
                await registerAvailableRemoteTokens()
                AppPerformance.end(
                    interval,
                    detail: "jobs=\(jobs.count)"
                )
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .agentActivityPushTokenUpdated
                )
            ) { _ in
                Task {
                    await registerAvailableRemoteTokens()
                }
            }
    }

    private func registerAvailableRemoteTokens() async {
        guard let baseURL = RemoteAgentPreference.baseURL() else { return }
        let client = RemoteAgentClient(baseURL: baseURL)
        for job in jobs
            where job.backend == .remote && !job.state.isTerminal
        {
            guard let remoteJobID = job.remoteJobID,
                  let token = coordinator.activityPushTokens[job.id],
                  registeredTokens[job.id] != token
            else {
                continue
            }
            do {
                try await client.registerActivityToken(
                    token,
                    remoteJobID: remoteJobID
                )
                registeredTokens[job.id] = token
            } catch {
                continue
            }
        }
    }
}
