import SwiftData
import SwiftUI

struct AgentSystemProjectionHost: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AgentSystemProjectionCoordinator.self)
    private var coordinator
    @Query(sort: \AgentJob.createdAt) private var jobs: [AgentJob]
    @Query(sort: \PersistentAgentEvent.createdAt)
    private var events: [PersistentAgentEvent]
    @State private var registeredTokens: [UUID: String] = [:]

    private var revision: String {
        let jobRevision = jobs.map {
            "\($0.id.uuidString):\($0.stateRaw):\($0.lastEventSequence):\($0.remoteJobID ?? "")"
        }.joined(separator: "|")
        let tokenRevision = coordinator.activityPushTokens
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map { "\($0.key.uuidString):\($0.value)" }
            .joined(separator: "|")
        return jobRevision + "#" + tokenRevision
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: revision) {
                await coordinator.project(jobs: jobs, events: events)
                try? modelContext.save()
                await registerAvailableRemoteTokens()
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
