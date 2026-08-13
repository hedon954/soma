import Foundation
import SwiftData

@MainActor
extension ConversationProcessingService {
    @discardableResult
    func submitQuickWorkout(
        text: String,
        draft: ExerciseQuickRecordDraft,
        context: ConversationProcessingContext,
        locationService: LocationContextService
    ) -> Bool {
        let submittedAt = Date.now
        let turnID = UUID()
        let contextEnvelope = AgentTurnContextBuilder.build(
            turnID: turnID,
            userText: text,
            hasCurrentMedia: false,
            turnSentAt: submittedAt,
            businessSummary: context.structuredContext,
            sessionID: context.session.id,
            in: context.modelContext
        )
        let userMessage = CoachMessage(
            date: submittedAt,
            sessionID: context.session.id,
            isFromCoach: false,
            text: text,
            turnID: turnID
        )
        let job = AgentJob(
            turnID: turnID,
            sessionID: context.session.id,
            userMessageID: userMessage.id,
            dataSpace: context.dataSpace,
            backend: .local,
            userText: text,
            mediaAttachments: [],
            contextSnapshot: AgentJobContextSnapshot(
                structuredContext: contextEnvelope.promptText(at: submittedAt),
                includeLocation: false,
                createdAt: submittedAt,
                envelope: contextEnvelope
            ),
            createdAt: submittedAt
        )
        job.executionKind = .deterministicWorkout
        job.deterministicWorkoutDraft = draft
        do {
            context.session.recordUserMessage(text, at: submittedAt)
            try AgentJobStore.enqueue(
                job,
                userMessage: userMessage,
                in: context.modelContext,
                at: submittedAt
            )
        } catch {
            context.modelContext.rollback()
            return false
        }
        dispatch(
            job: job,
            userMessage: userMessage,
            context: context,
            locationService: locationService
        )
        return true
    }

    @discardableResult
    func retry(
        userMessage: CoachMessage,
        context: ConversationProcessingContext,
        locationService: LocationContextService? = nil,
        forceLocal: Bool = false
    ) -> Bool {
        let useRemote = !forceLocal && RemoteAgentPreference.isEnabled()
        guard !userMessage.isFromCoach,
              userMessage.turnID != nil
        else {
            return false
        }

        let existingJobs = (
            try? context.modelContext.fetch(
                FetchDescriptor<AgentJob>(
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
            )
        ) ?? []
        if let existing = existingJobs.first(where: {
            $0.userMessageID == userMessage.id
                && ($0.state == .waitingForUser || $0.state == .staged)
        }) {
            do {
                try AgentJobStore.releaseForManualRetry(
                    existing,
                    dataSpace: context.dataSpace,
                    in: context.modelContext
                )
            } catch {
                context.modelContext.rollback()
                return false
            }
            dispatch(
                job: existing,
                userMessage: userMessage,
                context: context,
                locationService: locationService
            )
            return true
        }

        let submittedAt = Date.now
        let retryTurnID = userMessage.turnID ?? UUID()
        let contextEnvelope = AgentTurnContextBuilder.build(
            turnID: retryTurnID,
            userText: userMessage.text,
            hasCurrentMedia: !userMessage.mediaAttachments.isEmpty,
            turnSentAt: userMessage.date,
            businessSummary: context.structuredContext,
            sessionID: context.session.id,
            in: context.modelContext
        )
        let job = AgentJob(
            turnID: retryTurnID,
            sessionID: context.session.id,
            userMessageID: userMessage.id,
            dataSpace: context.dataSpace,
            backend: useRemote ? .remote : .local,
            userText: userMessage.text,
            mediaAttachments: userMessage.mediaAttachments,
            contextSnapshot: AgentJobContextSnapshot(
                structuredContext: contextEnvelope.promptText(at: submittedAt),
                includeLocation: userMessage.location != nil,
                createdAt: submittedAt,
                envelope: contextEnvelope
            ),
            createdAt: submittedAt
        )
        do {
            job.lastEventSequence = 1
            context.modelContext.insert(job)
            context.modelContext.insert(PersistentAgentEvent(
                jobID: job.id,
                turnID: job.turnID,
                sequence: 1,
                attemptNumber: 0,
                kind: .jobQueued,
                createdAt: submittedAt
            ))
            try context.modelContext.save()
        } catch {
            context.modelContext.rollback()
            return false
        }
        dispatch(
            job: job,
            userMessage: userMessage,
            context: context,
            locationService: locationService
        )
        return true
    }

    func resumePendingJobs(
        dataSpace: DataSpace,
        ai: AIService,
        modelContext: ModelContext,
        locationService: LocationContextService,
        releaseStaged: Bool = false
    ) {
        guard !isProcessing else { return }
        do {
            _ = try AgentJobStore.recoverExpiredLeases(
                dataSpace: dataSpace,
                in: modelContext
            )
            _ = try AgentJobStore.resumeForegroundJobs(
                dataSpace: dataSpace,
                in: modelContext
            )
            if releaseStaged {
                _ = try AgentJobStore.releaseStagedJobs(
                    dataSpace: dataSpace,
                    in: modelContext
                ) { job in
                    isExecutionAvailable(job, ai: ai)
                }
            }
        } catch {
            return
        }
        startNextPendingJob(
            dataSpace: dataSpace,
            ai: ai,
            modelContext: modelContext,
            locationService: locationService
        )
    }

    @discardableResult
    func discardPendingTurn(
        turnID: UUID,
        context: ConversationProcessingContext,
        locationService: LocationContextService
    ) -> Bool {
        guard !isProcessing else { return false }
        let jobs = (
            try? context.modelContext.fetch(FetchDescriptor<AgentJob>())
        ) ?? []
        guard let job = jobs.first(where: {
            $0.turnID == turnID
                && [.staged, .waitingForUser, .queued, .waitingForNetwork]
                .contains($0.state)
        }) else {
            return false
        }
        let messages = (
            try? context.modelContext.fetch(FetchDescriptor<CoachMessage>())
        ) ?? []
        let events = (
            try? context.modelContext.fetch(FetchDescriptor<PersistentAgentEvent>())
        ) ?? []
        let traces = (
            try? context.modelContext.fetch(FetchDescriptor<AgentTrace>())
        ) ?? []
        let attachments = job.mediaAttachments
        let messageIDs = Set([job.userMessageID, job.responseMessageID].compactMap { $0 })
        events.filter { $0.jobID == job.id }.forEach(context.modelContext.delete)
        messages.filter { messageIDs.contains($0.id) }.forEach { message in
            if let traceID = message.agentTraceID,
               let trace = traces.first(where: { $0.id == traceID })
            {
                context.modelContext.delete(trace)
            }
            context.modelContext.delete(message)
        }
        context.modelContext.delete(job)
        do {
            try context.modelContext.save()
            for attachment in attachments {
                _ = MediaStore.removeStoredFile(at: attachment.path)
            }
            _ = try AgentJobStore.releaseStagedJobs(
                dataSpace: context.dataSpace,
                in: context.modelContext
            ) { queued in
                self.isExecutionAvailable(queued, ai: context.ai)
            }
            startNextPendingJob(
                dataSpace: context.dataSpace,
                ai: context.ai,
                modelContext: context.modelContext,
                locationService: locationService
            )
            return true
        } catch {
            context.modelContext.rollback()
            return false
        }
    }

    @discardableResult
    func clearPendingQueue(
        context: ConversationProcessingContext
    ) -> Bool {
        guard !isProcessing else { return false }
        let jobs = (
            try? context.modelContext.fetch(FetchDescriptor<AgentJob>())
        ) ?? []
        let targets = jobs.filter {
            $0.dataSpace == context.dataSpace
                && [.staged, .waitingForUser, .queued, .waitingForNetwork]
                .contains($0.state)
        }
        guard !targets.isEmpty else { return false }
        let targetIDs = Set(targets.map(\.id))
        let messageIDs = Set(targets.flatMap {
            [$0.userMessageID, $0.responseMessageID].compactMap { $0 }
        })
        let attachments = targets.flatMap(\.mediaAttachments)
        let events = (
            try? context.modelContext.fetch(FetchDescriptor<PersistentAgentEvent>())
        ) ?? []
        let messages = (
            try? context.modelContext.fetch(FetchDescriptor<CoachMessage>())
        ) ?? []
        let traces = (
            try? context.modelContext.fetch(FetchDescriptor<AgentTrace>())
        ) ?? []
        events.filter { targetIDs.contains($0.jobID) }.forEach(context.modelContext.delete)
        messages.filter { messageIDs.contains($0.id) }.forEach { message in
            if let traceID = message.agentTraceID,
               let trace = traces.first(where: { $0.id == traceID })
            {
                context.modelContext.delete(trace)
            }
            context.modelContext.delete(message)
        }
        targets.forEach(context.modelContext.delete)
        do {
            try context.modelContext.save()
            for attachment in attachments {
                _ = MediaStore.removeStoredFile(at: attachment.path)
            }
            return true
        } catch {
            context.modelContext.rollback()
            return false
        }
    }

    func runDeterministicWorkoutAttempt(
        job: AgentJob,
        userMessage: CoachMessage,
        context: ConversationProcessingContext
    ) async {
        guard let draft = job.deterministicWorkoutDraft else {
            try? AgentJobStore.waitForUser(
                job,
                message: "快捷训练数据已损坏，请删除后重新选择建议。",
                in: context.modelContext
            )
            return
        }
        let (responseMessage, attemptNumber) = bindResponseMessage(
            job: job,
            turnID: job.turnID,
            resumable: job.responseMessageID != nil,
            context: context
        )
        let trace = AgentTrace(
            provider: "Soma 本机规则",
            model: "deterministic-workout-v1",
            endpoint: "local://conversation-recorder",
            dataSpaceRaw: context.dataSpace.rawValue,
            userInput: userMessage.text,
            contextSnapshot: "精确命中未修改的最近训练建议；跳过 LLM。",
            mediaKind: .none,
            imageCount: 0,
            imageAttachmentCount: 0,
            videoAttachmentCount: 0,
            turnID: job.turnID,
            attemptNumber: attemptNumber
        )
        responseMessage.agentTraceID = trace.id
        context.modelContext.insert(trace)
        let call = AgentToolCall(
            name: .mutateUserData,
            arguments: AgentToolArguments(
                operation: "create",
                payload: AgentMutationPayload(
                    exerciseID: draft.exerciseID.uuidString,
                    setEntries: draft.setEntries.map {
                        AgentWorkoutSetInput(
                            reps: $0.reps,
                            externalWeightKG: $0.externalWeightKG
                        )
                    },
                    restSeconds: draft.restSeconds,
                    durationMinutes: draft.durationMinutes
                ),
                recordType: "workout"
            )
        )
        let spanID = UUID()
        let startedAt = Date.now
        PersistentAgentEventProjection.persistAndProject(
            .span(AgentTraceSpan(
                id: spanID,
                step: 1,
                kind: .tool,
                title: "保存最近训练数据",
                status: .running,
                startedAt: startedAt,
                endedAt: startedAt,
                input: AgentTraceText.json(call),
                metadata: AgentTraceText.jsonObject([
                    "execution_path": "deterministic_quick_workout",
                    "llm_invoked": false
                ])
            )),
            job: job,
            responseMessage: responseMessage,
            trace: trace,
            in: context.modelContext
        )
        let result = ConversationRecorder.executeAgentTool(
            call,
            sourceText: userMessage.text,
            sourceDate: .now,
            sourceSessionID: context.session.id,
            sourceTurnID: job.turnID,
            mediaKind: .none,
            mediaPath: nil,
            in: context.modelContext
        )
        let endedAt = Date.now
        PersistentAgentEventProjection.persistAndProject(
            .span(AgentTraceSpan(
                id: spanID,
                step: 1,
                kind: .tool,
                title: "保存最近训练数据",
                status: result.ok ? .succeeded : .failed,
                startedAt: startedAt,
                endedAt: endedAt,
                input: AgentTraceText.json(call),
                output: AgentTraceText.json(result),
                metadata: AgentTraceText.jsonObject([
                    "execution_path": "deterministic_quick_workout",
                    "llm_invoked": false
                ]),
                errorMessage: result.ok ? nil : result.observation
            )),
            job: job,
            responseMessage: responseMessage,
            trace: trace,
            in: context.modelContext
        )
        guard result.ok else {
            responseMessage.text = result.observation
            responseMessage.agentStatus = .failed
            try? AgentJobStore.waitForUser(
                job,
                message: result.observation,
                in: context.modelContext
            )
            return
        }
        let answer = "已按你选择的最近一次训练数据完成记录。"
        let itemID = UUID()
        PersistentAgentEventProjection.persistAndProject(
            .assistantTextDelta(itemID: itemID, delta: answer),
            job: job,
            responseMessage: responseMessage,
            trace: trace,
            in: context.modelContext
        )
        PersistentAgentEventProjection.persistAndProject(
            .assistantTextCompleted(itemID: itemID, at: endedAt),
            job: job,
            responseMessage: responseMessage,
            trace: trace,
            in: context.modelContext
        )
        responseMessage.text = answer
        responseMessage.recordType = .workout
        responseMessage.agentStatus = .succeeded
        trace.apply(.completed(answer: answer, at: endedAt))
        try? job.transition(to: .succeeded, at: endedAt)
        _ = try? AgentJobStore.append(
            kind: .completed,
            payload: .init(text: answer),
            to: job,
            in: context.modelContext,
            at: endedAt
        )
        responseMessage.applyAgentEvent(.completed(answer: answer, at: endedAt))
        context.session.touch(at: endedAt)
        try? context.modelContext.save()
    }
}
