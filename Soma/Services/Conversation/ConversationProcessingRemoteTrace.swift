import Foundation
import SwiftData

func remoteModelSpanMetadata(_ event: RemoteAgentEvent) -> String {
    let mediaMode = event.payload["mediaMode"]?.stringValue ?? "text"
    let exposedToolNames = event.payload["exposedToolNames"]?.stringArrayValue ?? []
    let exposedToolCount = event.payload["exposedToolCount"]?.intValue
        ?? exposedToolNames.count
    return AgentTraceText.jsonObject([
        "media_mode": mediaMode,
        "request_attempt": event.payload["requestAttempt"]?.intValue ?? 1,
        "exposed_tool_names": exposedToolNames,
        "exposed_tool_count": exposedToolCount,
        "provider": event.payload["provider"]?.stringValue ?? "managed",
        "model": event.payload["model"]?.stringValue ?? "configured",
        "ttft_budget_seconds": mediaMode == "direct_video"
            ? 20
            : mediaMode == "text" ? 8 : 10
    ])
}

func applyRemoteUsage(
    _ usage: RemoteJSONValue?,
    to metadata: inout [String: Any]
) {
    guard let usage = usage?.objectValue else { return }
    metadata["prompt_tokens"] = usage["input"]?.intValue ?? NSNull()
    metadata["completion_tokens"] = usage["output"]?.intValue ?? NSNull()
    metadata["cached_prompt_tokens"] = usage["cachedInput"]?.intValue ?? NSNull()
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
        for event in events where event.sequence > currentRemoteProjectionCursor(for: job) {
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
            remoteProjectionCursor = event.sequence
            if !event.isTransientTextUpdate {
                persistRemoteProjectionCursor(for: job)
                try context.modelContext.save()
            }
        }
    }

    func currentRemoteProjectionCursor(for job: AgentJob) -> Int {
        if remoteProjectionJobID != job.id {
            remoteProjectionJobID = job.id
            remoteProjectionCursor = job.remoteEventCursor
        }
        return remoteProjectionCursor
    }

    func resetRemoteProjectionCursor(for job: AgentJob) {
        remoteProjectionJobID = job.id
        remoteProjectionCursor = job.remoteEventCursor
    }

    func persistRemoteProjectionCursor(for job: AgentJob) {
        guard remoteProjectionJobID == job.id else { return }
        job.remoteEventCursor = remoteProjectionCursor
    }

    func failRemoteJob(
        _ job: AgentJob,
        message: String,
        context: ConversationProcessingContext
    ) {
        if !job.state.isTerminal {
            try? ConversationTurnPersistence.waitForUser(
                job,
                message: message,
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
        usage: RemoteJSONValue? = nil,
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
        applyRemoteUsage(usage, to: &metadata)
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
        _ = try? ConversationTurnPersistence.append(
            kind: .span,
            payload: .init(span: span),
            to: job,
            in: context.modelContext,
            at: span.endedAt
        )
    }

    func projectRemoteRuntimeTool(
        _ event: RemoteAgentEvent,
        job: AgentJob,
        responseMessage: CoachMessage,
        trace: AgentTrace,
        context: ConversationProcessingContext
    ) -> Bool {
        guard event.kind == "tool",
              let nameRaw = event.payload["toolName"]?.stringValue,
              let name = AgentToolName(rawValue: nameRaw),
              ["started", "updated", "suspended", "completed", "failed", "cancelled"]
              .contains(event.phase)
        else {
            return false
        }
        let result = event.payload["result"]?.objectValue
        let ok = result?["ok"]?.boolValue ?? false
        let operationID = event.payload["toolCallID"]?.stringValue ?? event.id
        let existingStartedAt = responseMessage.agentTurnItems.first {
            $0.operationID == operationID
        }?.startedAt ?? event.createdAt
        let status: AgentTraceStatus = switch event.phase {
        case "started", "updated", "suspended": .running
        case "cancelled": .cancelled
        case "failed": .failed
        default: ok ? .succeeded : .failed
        }
        let phase: AgentTurnPhase = switch event.phase {
        case "started": .preparing
        case "updated": .running
        case "suspended": .waitingForDevice
        case "cancelled": .cancelled
        case "failed": .failed
        default: ok ? .completed : .failed
        }
        projectRemoteSpan(
            AgentTraceSpan(
                sequence: event.sequence,
                step: event.sequence,
                kind: name == .loadSkill ? .skill : .tool,
                title: name.displayTitle,
                status: status,
                operationID: operationID,
                phase: phase,
                startedAt: existingStartedAt,
                endedAt: event.createdAt,
                input: event.payload["arguments"].map(AgentTraceText.json),
                output: result.map(AgentTraceText.json),
                errorMessage: status == .failed
                    ? result?["message"]?.stringValue
                    : nil
            ),
            job: job,
            responseMessage: responseMessage,
            trace: trace,
            context: context
        )
        return true
    }

    func remoteResponseMessage(
        for job: AgentJob,
        turnID: UUID,
        sessionID: UUID,
        in context: ModelContext
    ) -> CoachMessage {
        if let responseID = job.responseMessageID {
            var descriptor = FetchDescriptor<CoachMessage>(
                predicate: #Predicate { $0.id == responseID }
            )
            descriptor.fetchLimit = 1
            if let existing = try? context.fetch(descriptor).first {
                ConversationTurnPersistence.prepareResponseMessageForResume(existing, job: job)
                return existing
            }
        }
        let response = CoachMessage(
            sessionID: sessionID,
            isFromCoach: true,
            text: "",
            agentStatus: .running,
            turnID: turnID,
            attemptNumber: ConversationTurnPersistence.nextAttemptNumber(for: turnID, in: context)
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
        if let traceID = response.agentTraceID {
            var descriptor = FetchDescriptor<AgentTrace>(
                predicate: #Predicate { $0.id == traceID }
            )
            descriptor.fetchLimit = 1
            if let existing = try? context.fetch(descriptor).first,
               existing.status == .running
            {
                return existing
            }
        }
        let trace = AgentTrace(
            provider: "Soma Managed",
            model: "managed",
            endpoint: endpoint.absoluteString,
            dataSpaceRaw: dataSpace.rawValue,
            userInput: input,
            contextSnapshot: "由用户启用的后台持续处理；发送设备组装的版本化有界模型输入。",
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

private extension RemoteAgentEvent {
    var isTransientTextUpdate: Bool {
        kind == "text" && phase == "updated"
    }
}
