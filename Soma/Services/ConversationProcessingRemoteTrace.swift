import Foundation
import SwiftData

struct RemoteVideoKeyframeFallbackRequired: Error {
    var code: String
}

extension ConversationProcessingService {
    func applyRemoteEvents(
        _ events: [RemoteAgentEvent],
        remoteJobID: String,
        job: AgentJob,
        userMessage: CoachMessage,
        responseMessage: CoachMessage,
        trace: AgentTrace,
        context: ConversationProcessingContext,
        client: RemoteAgentClient
    ) async throws {
        for event in events where event.sequence > job.remoteEventCursor {
            guard !job.state.isTerminal,
                  job.dataSpace == context.dataSpace
            else {
                try? await client.cancel(remoteJobID: remoteJobID)
                return
            }
            try await applyRemoteEvent(
                event,
                remoteJobID: remoteJobID,
                job: job,
                userMessage: userMessage,
                responseMessage: responseMessage,
                trace: trace,
                context: context,
                client: client
            )
            job.remoteEventCursor = event.sequence
            try context.modelContext.save()
        }
    }

    func failRemoteJob(
        _ job: AgentJob,
        message: String,
        context: ConversationProcessingContext
    ) {
        if !job.state.isTerminal, job.state.canTransition(to: .failed) {
            try? job.transition(to: .failed, error: message)
            _ = try? AgentJobStore.append(
                kind: .failed,
                payload: .init(message: message),
                to: job,
                in: context.modelContext
            )
        }
        try? context.modelContext.save()
    }

    func remoteClientJobID(for job: AgentJob) -> UUID {
        guard job.remoteRequestAttempt > 1 else { return job.id }
        var raw = job.id.uuidString.lowercased()
        let first = raw.startIndex
        raw.replaceSubrange(first ... first, with: raw[first] == "f" ? "e" : "f")
        return UUID(uuidString: raw) ?? job.id
    }

    func updateRemoteModelSpan(
        firstDeltaAt: Date?,
        completedAt: Date?,
        status: AgentTraceStatus?,
        trace: AgentTrace,
        responseMessage: CoachMessage
    ) {
        guard var span = trace.spans.last(where: {
            $0.kind == .model && $0.status == .running
        }) else {
            return
        }
        var metadata = (span.metadata?.data(using: .utf8))
            .flatMap {
                try? JSONSerialization.jsonObject(with: $0)
                    as? [String: Any]
            } ?? [:]
        if let firstDeltaAt,
           metadata["provider_ttft_ms"] == nil
        {
            metadata["provider_ttft_ms"] = Int(
                firstDeltaAt.timeIntervalSince(span.startedAt) * 1000
            )
        }
        if let completedAt {
            span.endedAt = completedAt
            metadata["stream_ms"] = Int(
                completedAt.timeIntervalSince(span.startedAt) * 1000
            )
        }
        if let status {
            span.statusRaw = status.rawValue
        }
        span.metadata = AgentTraceText.jsonObject(metadata)
        trace.apply(.span(span))
        responseMessage.applyAgentEvent(.span(span))
    }

    func projectRemoteSpan(
        _ span: AgentTraceSpan,
        job: AgentJob,
        responseMessage: CoachMessage,
        trace: AgentTrace,
        context: ConversationProcessingContext
    ) {
        trace.apply(.span(span))
        responseMessage.applyAgentEvent(.span(span))
        _ = try? AgentJobStore.append(
            kind: .span,
            payload: .init(span: span),
            to: job,
            in: context.modelContext,
            at: span.endedAt
        )
    }

    func remoteResponseMessage(
        for job: AgentJob,
        turnID: UUID,
        sessionID: UUID,
        in context: ModelContext
    ) -> CoachMessage {
        let messages = (
            try? context.fetch(FetchDescriptor<CoachMessage>())
        ) ?? []
        if let responseID = job.responseMessageID,
           let existing = messages.first(where: { $0.id == responseID })
        {
            existing.agentStatus = .running
            return existing
        }
        let response = CoachMessage(
            sessionID: sessionID,
            isFromCoach: true,
            text: "",
            agentStatus: .running,
            turnID: turnID,
            attemptNumber: nextAttemptNumber(for: turnID, in: context)
        )
        context.insert(response)
        job.responseMessageID = response.id
        try? context.save()
        return response
    }

    func remoteTrace(
        for response: CoachMessage,
        turnID: UUID,
        dataSpace: DataSpace,
        endpoint: URL,
        input: String,
        in context: ModelContext
    ) -> AgentTrace {
        let traces = (try? context.fetch(FetchDescriptor<AgentTrace>())) ?? []
        if let traceID = response.agentTraceID,
           let existing = traces.first(where: { $0.id == traceID })
        {
            return existing
        }
        let trace = AgentTrace(
            provider: "Soma Managed",
            model: "managed",
            endpoint: endpoint.absoluteString,
            dataSpaceRaw: dataSpace.rawValue,
            userInput: input,
            contextSnapshot: "由用户启用的后台持续处理；仅发送当前任务最小上下文。",
            mediaKind: .none,
            imageCount: 0,
            imageAttachmentCount: 0,
            videoAttachmentCount: 0,
            turnID: turnID,
            attemptNumber: response.attemptNumber
        )
        context.insert(trace)
        response.agentTraceID = trace.id
        try? context.save()
        return trace
    }
}
