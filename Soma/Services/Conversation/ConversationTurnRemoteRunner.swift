import Foundation
import Observation
import SwiftData

@MainActor
extension ConversationProcessingService {
    func startRemoteProcessing(
        job: AgentJob,
        userMessage: CoachMessage,
        context: ConversationProcessingContext,
        locationService: LocationContextService?
    ) {
        processingTask = Task { [weak self] in
            guard let self else { return }
            if job.contextSnapshot?.includeLocation == true,
               userMessage.location == nil,
               let locationService
            {
                userMessage.location = await locationService.requestSnapshot()
                try? context.modelContext.save()
            }
            await runRemoteAttempt(
                job: job,
                userMessage: userMessage,
                context: context
            )
            finishProcessing()
            if let locationService {
                startNextPendingJob(
                    dataSpace: context.dataSpace,
                    ai: context.ai,
                    modelContext: context.modelContext,
                    locationService: locationService
                )
            }
        }
    }

    func runRemoteAttempt(
        job: AgentJob,
        userMessage: CoachMessage,
        context: ConversationProcessingContext
    ) async {
        guard let baseURL = RemoteAgentPreference.baseURL(),
              let turnID = userMessage.turnID,
              job.dataSpace == context.dataSpace,
              !job.state.isTerminal
        else {
            failRemoteJob(
                job,
                message: RemoteAgentError.endpointMissing.localizedDescription,
                context: context
            )
            return
        }

        let client = RemoteAgentClient(baseURL: baseURL)
        let responseMessage = remoteResponseMessage(
            for: job,
            turnID: turnID,
            sessionID: context.session.id,
            in: context.modelContext
        )
        let trace = remoteTrace(
            for: responseMessage,
            turnID: turnID,
            dataSpace: context.dataSpace,
            endpoint: baseURL,
            input: userMessage.text,
            in: context.modelContext
        )

        do {
            if job.remoteJobID == nil {
                let submissionStartedAt = Date.now
                let prepared = try await prepareRemoteSubmission(
                    job: job,
                    userMessage: userMessage,
                    turnID: turnID,
                    context: context,
                    client: client
                )
                if let summary = prepared.compactionSummary {
                    projectRemoteSpan(
                        AgentTraceSpan(
                            kind: .output,
                            title: "已压缩更早对话",
                            status: .succeeded,
                            startedAt: submissionStartedAt,
                            endedAt: .now,
                            output: summary,
                            metadata: AgentTraceText.jsonObject([
                                "strategy": prepared.compactionStrategy?.rawValue
                                    ?? "unknown"
                            ])
                        ),
                        job: job,
                        responseMessage: responseMessage,
                        trace: trace,
                        context: context
                    )
                }
                let submitted = try await client.submit(job: AgentJobSubmission(
                    clientJobID: remoteClientJobID(for: job),
                    turnID: turnID,
                    sessionID: context.session.id,
                    modelInput: prepared.modelInput,
                    mediaMode: prepared.mediaMode,
                    liveActivityEnabled: UserDefaults.standard.bool(
                        forKey: AgentSystemPreference.liveActivitiesKey
                    ),
                    requestAttempt: job.remoteRequestAttempt
                ))
                guard !job.state.isTerminal else {
                    try? await client.cancel(remoteJobID: submitted.id)
                    return
                }
                job.remoteJobID = submitted.id
                job.remoteEventCursor = 0
                resetRemoteProjectionCursor(for: job)
                let submissionEndedAt = Date.now
                projectRemoteSpan(
                    AgentTraceSpan(
                        kind: .output,
                        title: "远程媒体上传与任务投递",
                        status: .succeeded,
                        startedAt: submissionStartedAt,
                        endedAt: submissionEndedAt,
                        metadata: AgentTraceText.jsonObject([
                            "attachment_count": job.mediaAttachments.count,
                            "history_exchange_count": prepared.historyExchangeCount,
                            "video_count": job.mediaAttachments.count {
                                $0.kind == .video
                            },
                            "media_mode": prepared.mediaMode.rawValue,
                            "request_attempt": job.remoteRequestAttempt,
                            "duration_ms": Int(
                                submissionEndedAt.timeIntervalSince(
                                    submissionStartedAt
                                ) * 1000
                            )
                        ])
                    ),
                    job: job,
                    responseMessage: responseMessage,
                    trace: trace,
                    context: context
                )
                try context.modelContext.save()
            }
            guard let remoteJobID = job.remoteJobID else {
                throw RemoteAgentError.invalidResponse
            }

            let catchUpPage = try await client.events(
                remoteJobID: remoteJobID,
                after: currentRemoteProjectionCursor(for: job)
            )
            try await applyRemoteEvents(
                catchUpPage.events,
                remoteJobID: remoteJobID,
                job: job,
                userMessage: userMessage,
                responseMessage: responseMessage,
                trace: trace,
                context: context,
                client: client
            )

            if !job.state.isTerminal, !catchUpPage.terminal {
                if job.state == .running {
                    try job.transition(to: .remoteRunning)
                }
                job.leaseOwner = nil
                job.leaseExpiresAt = nil
                job.nextRetryAt = nil
                responseMessage.agentStatus = .running
                try context.modelContext.save()

                for try await event in client.eventStream(
                    remoteJobID: remoteJobID,
                    after: currentRemoteProjectionCursor(for: job)
                ) {
                    try await applyRemoteEvents(
                        [event],
                        remoteJobID: remoteJobID,
                        job: job,
                        userMessage: userMessage,
                        responseMessage: responseMessage,
                        trace: trace,
                        context: context,
                        client: client
                    )
                    if job.state.isTerminal {
                        break
                    }
                }
            }

            let finalPage = try await client.events(
                remoteJobID: remoteJobID,
                after: currentRemoteProjectionCursor(for: job)
            )
            try await applyRemoteEvents(
                finalPage.events,
                remoteJobID: remoteJobID,
                job: job,
                userMessage: userMessage,
                responseMessage: responseMessage,
                trace: trace,
                context: context,
                client: client
            )
            let projectedCursor = currentRemoteProjectionCursor(for: job)
            if projectedCursor > 0 {
                let acknowledgedCursor = projectedCursor
                Task {
                    try? await client.acknowledge(
                        remoteJobID: remoteJobID,
                        through: acknowledgedCursor
                    )
                }
            }

            if job.state.isTerminal {
                job.nextRetryAt = nil
            } else if finalPage.terminal || catchUpPage.terminal {
                if job.state == .running || job.state == .remoteRunning {
                    try job.transition(
                        to: .failed,
                        error: "后台任务已结束，但没有返回可展示的结果。"
                    )
                }
                job.nextRetryAt = nil
            } else {
                throw URLError(.networkConnectionLost)
            }
            persistRemoteProjectionCursor(for: job)
            context.session.touch(at: .now)
            try context.modelContext.save()
        } catch {
            if job.state == .waitingForUser,
               responseMessage.agentStatus == .cancelled
            {
                context.session.touch(at: .now)
                try? context.modelContext.save()
                return
            }
            let reason = AppErrorMessage.message(for: error, operation: .model)
            let message = LLMOutageClassifier.disposition(for: error).message(
                fallback: "这次后台任务没有处理成功：\(reason)"
            )
            job.submissionAttemptCount += 1
            trace.apply(.failed(
                message: reason,
                cancelled: false,
                at: .now
            ))
            failRemoteJob(job, message: message, context: context)
            responseMessage.text = ""
            responseMessage.agentStatus = .failed
            responseMessage.applyAgentEvent(.failed(
                message: message,
                cancelled: false,
                at: .now
            ))
            try? ConversationTurnPersistence.stageFollowingJobs(
                after: job,
                message: "前一条消息等待手动重试；本条已按发送顺序暂存。",
                in: context.modelContext
            )
            try? context.modelContext.save()
        }
    }

    func applyRemoteEvent(
        _ event: RemoteAgentEvent,
        remoteJobID: String,
        job: AgentJob,
        userMessage: CoachMessage,
        responseMessage: CoachMessage,
        trace: AgentTrace,
        context: ConversationProcessingContext,
        client: RemoteAgentClient
    ) async throws {
        if let request = RemoteDeviceToolRequest(event: event) {
            updateRemoteModelSpan(
                firstDeltaAt: nil,
                completedAt: event.createdAt,
                status: .succeeded,
                trace: trace,
                responseMessage: responseMessage
            )
            guard let name = AgentToolName(rawValue: request.name),
                  name.supportedSchemaVersions.contains(request.schemaVersion),
                  name.isMutation == request.mutation,
                  job.turnID == userMessage.turnID,
                  job.state == .running || job.state == .remoteRunning
            else {
                throw RemoteAgentError.toolRejected(
                    "后台请求的 Tool 与当前 Turn、空间或 Schema 不匹配。"
                )
            }
            let argumentData = try JSONEncoder().encode(request.arguments)
            let normalizedArgumentData = request.schemaVersion == name.schemaVersion
                ? try AgentToolArgumentNormalizer.normalize(argumentData, for: name)
                : argumentData
            try AgentToolSchemaValidator.validate(
                normalizedArgumentData,
                for: name,
                schemaVersion: request.schemaVersion
            )
            let arguments = try JSONDecoder().decode(
                AgentToolArguments.self,
                from: normalizedArgumentData
            )
            let call = AgentToolCall(name: name, arguments: arguments)
            let operationID = request.toolCallID
            let existingStartedAt = responseMessage.agentTurnItems.first {
                $0.operationID == operationID
            }?.startedAt ?? event.createdAt
            try job.transition(to: .waitingForDevice)
            _ = try? ConversationTurnPersistence.append(
                kind: .waitingForDevice,
                payload: .init(message: "正在本机执行 \(name.displayTitle)。"),
                to: job,
                in: context.modelContext
            )
            projectRemoteSpan(
                AgentTraceSpan(
                    sequence: event.sequence,
                    step: event.sequence,
                    kind: name == .loadSkill ? .skill : .tool,
                    title: name.displayTitle,
                    status: .running,
                    operationID: operationID,
                    phase: .waitingForDevice,
                    startedAt: existingStartedAt,
                    endedAt: event.createdAt,
                    input: AgentTraceText.json(arguments)
                ),
                job: job,
                responseMessage: responseMessage,
                trace: trace,
                context: context
            )
            projectRemoteSpan(
                AgentTraceSpan(
                    sequence: event.sequence,
                    step: event.sequence,
                    kind: name == .loadSkill ? .skill : .tool,
                    title: name.displayTitle,
                    status: .running,
                    operationID: operationID,
                    phase: .running,
                    startedAt: existingStartedAt,
                    endedAt: .now,
                    input: AgentTraceText.json(arguments)
                ),
                job: job,
                responseMessage: responseMessage,
                trace: trace,
                context: context
            )
            let currentGymID = GymSelection.current(in: context.gyms)?.id
            let result = try await executeAgentTool(
                call,
                turnID: job.turnID,
                userMessage: userMessage,
                sourceDate: job.stableDefaultOccurredAt,
                mediaAttachments: job.mediaAttachments,
                preferredGymID: currentGymID,
                context: context
            )
            try await client.submitToolResult(
                remoteJobID: remoteJobID,
                toolCallID: request.toolCallID,
                result: result
            )
            try job.transition(to: .remoteRunning)
            projectRemoteSpan(
                AgentTraceSpan(
                    sequence: event.sequence,
                    step: event.sequence,
                    kind: name == .loadSkill ? .skill : .tool,
                    title: name.displayTitle,
                    status: result.ok ? .succeeded : .failed,
                    operationID: operationID,
                    phase: result.ok ? .completed : .failed,
                    startedAt: existingStartedAt,
                    endedAt: .now,
                    input: AgentTraceText.json(arguments),
                    output: AgentTraceText.json(result),
                    errorMessage: result.ok ? nil : result.observation
                ),
                job: job,
                responseMessage: responseMessage,
                trace: trace,
                context: context
            )
            return
        }

        if projectRemoteRuntimeTool(
            event,
            job: job,
            responseMessage: responseMessage,
            trace: trace,
            context: context
        ) {
            return
        }

        if projectRemoteReasoning(
            event,
            job: job,
            responseMessage: responseMessage,
            trace: trace,
            context: context
        ) {
            return
        }

        if event.kind == "text",
           event.phase == "updated",
           let delta = event.payload["delta"]?.stringValue
        {
            if !remoteModelReceivedFirstDelta {
                updateRemoteModelSpan(
                    firstDeltaAt: event.createdAt,
                    completedAt: nil,
                    status: nil,
                    trace: trace,
                    responseMessage: responseMessage
                )
                remoteModelReceivedFirstDelta = true
            }
            let itemID = event.payload["itemID"]?.stringValue
                .flatMap(UUID.init(uuidString:))
                ?? UUID(uuidString: event.id)
                ?? UUID()
            let traceEvent = AgentTraceEvent.assistantTextDelta(
                itemID: itemID,
                delta: delta
            )
            projectRemoteTextDelta(traceEvent, at: event.createdAt)
        } else if event.kind == "text", event.phase == "completed" {
            let itemID = event.payload["itemID"]?.stringValue
                .flatMap(UUID.init(uuidString:))
                ?? UUID(uuidString: event.id)
                ?? UUID()
            let traceEvent = AgentTraceEvent.assistantTextCompleted(
                itemID: itemID,
                at: event.createdAt
            )
            flushRemoteTextDelta(itemID: itemID, at: event.createdAt)
            let liveText = pendingLiveTextSnapshot(for: traceEvent)
            PersistentAgentEventProjection.persistAndProject(
                traceEvent,
                job: job,
                responseMessage: responseMessage,
                trace: trace,
                liveText: liveText,
                in: context.modelContext
            )
            applyLiveAgentEvent(traceEvent)
            remoteTextCoalescer = AgentTextDeltaCoalescer()
            remoteTextItemID = nil
        } else if event.kind == "model", event.phase == "updated",
                  event.payload["fallbackReason"]?.stringValue == "video_input_unsupported"
        {
            projectRemoteVideoFallback(event, job: job, responseMessage: responseMessage,
                                       trace: trace, context: context)
        } else if event.kind == "model", event.phase == "started" {
            remoteModelReceivedFirstDelta = false
            let exposedToolNames = event.payload["exposedToolNames"]?
                .stringArrayValue ?? []
            projectRemoteSpan(
                AgentTraceSpan(
                    sequence: event.sequence,
                    kind: .model,
                    title: "Soma 后台模型",
                    status: .running,
                    phase: .modelRunning,
                    startedAt: event.createdAt,
                    endedAt: event.createdAt,
                    metadata: remoteModelSpanMetadata(event)
                ),
                job: job,
                responseMessage: responseMessage,
                trace: trace,
                context: context
            )
            AgentDiagnostics.modelRequest(
                step: event.sequence,
                provider: event.payload["provider"]?.stringValue ?? "managed",
                model: event.payload["model"]?.stringValue ?? "configured",
                tier: "后台持续处理",
                skillID: job.selectedSkillID,
                toolNames: exposedToolNames,
                messageCount: nil
            )
        } else if event.kind == "output",
                  event.phase == "completed",
                  let answer = event.payload["answer"]?.stringValue
        {
            updateRemoteModelSpan(
                firstDeltaAt: nil,
                completedAt: event.createdAt,
                status: .succeeded,
                trace: trace,
                responseMessage: responseMessage
            )
            let presentedAnswer = answer
            job.responseTextSnapshot = presentedAnswer
            responseMessage.text = presentedAnswer
            responseMessage.agentStatus = .succeeded
            trace.apply(.completed(answer: presentedAnswer, at: event.createdAt))
            if job.state == .running || job.state == .remoteRunning {
                try job.transition(to: .succeeded, at: event.createdAt)
            }
            _ = try? ConversationTurnPersistence.append(
                kind: .completed,
                payload: .init(text: presentedAnswer),
                to: job,
                in: context.modelContext,
                at: event.createdAt
            )
            responseMessage.applyAgentEvent(.completed(
                answer: presentedAnswer,
                at: event.createdAt
            ))
            applyLiveAgentEvent(.completed(
                answer: presentedAnswer,
                at: event.createdAt
            ))
        } else if event.phase == "cancelled" {
            updateRemoteModelSpan(
                firstDeltaAt: nil,
                completedAt: event.createdAt,
                status: .cancelled,
                trace: trace,
                responseMessage: responseMessage
            )
            let message = "后台任务已取消。"
            trace.apply(.failed(
                message: message,
                cancelled: false,
                at: event.createdAt
            ))
            responseMessage.text = ""
            responseMessage.agentStatus = .failed
            responseMessage.applyAgentEvent(.failed(
                message: message,
                cancelled: false,
                at: event.createdAt
            ))
            try? ConversationTurnPersistence.waitForUser(
                job,
                message: message,
                in: context.modelContext
            )
        } else if event.kind == "error" || event.phase == "failed" {
            updateRemoteModelSpan(
                firstDeltaAt: nil,
                completedAt: event.createdAt,
                status: .failed,
                trace: trace,
                responseMessage: responseMessage
            )
            let code = event.payload["code"]?.stringValue ?? "remote_failed"
            let message = AppErrorMessage.remoteMessage(code: code)
            trace.apply(.failed(
                message: message,
                cancelled: false,
                at: event.createdAt
            ))
            failRemoteJob(job, message: message, context: context)
            responseMessage.text = ""
            responseMessage.agentStatus = .failed
            responseMessage.applyAgentEvent(.failed(
                message: message,
                cancelled: false,
                at: event.createdAt
            ))
        }
    }

    private func projectRemoteReasoning(
        _ event: RemoteAgentEvent,
        job: AgentJob,
        responseMessage: CoachMessage,
        trace: AgentTrace,
        context: ConversationProcessingContext
    ) -> Bool {
        guard event.kind == "reasoning" else { return false }
        let itemID = event.payload["itemID"]?.stringValue
            .flatMap(UUID.init(uuidString:))
            ?? UUID(uuidString: event.id)
            ?? UUID()
        if event.phase == "updated",
           let delta = event.payload["delta"]?.stringValue
        {
            if !remoteModelReceivedFirstDelta {
                updateRemoteModelSpan(
                    firstDeltaAt: event.createdAt,
                    completedAt: nil,
                    status: nil,
                    trace: trace,
                    responseMessage: responseMessage
                )
                remoteModelReceivedFirstDelta = true
            }
            applyLiveAgentEvent(.reasoningDelta(itemID: itemID, delta: delta))
        } else if event.phase == "completed" {
            let text = event.payload["text"]?.stringValue
                ?? (liveReasoningItemID == itemID ? liveReasoningTextBuffer.text : "")
            let traceEvent = AgentTraceEvent.reasoningCompleted(
                itemID: itemID,
                text: text,
                at: event.createdAt
            )
            PersistentAgentEventProjection.persistAndProject(
                traceEvent,
                job: job,
                responseMessage: responseMessage,
                trace: trace,
                in: context.modelContext
            )
            applyLiveAgentEvent(traceEvent)
        }
        return true
    }
}
