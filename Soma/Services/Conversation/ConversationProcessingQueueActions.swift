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
        let businessDate = context.businessDate(for: text, turnSentAt: submittedAt)
        let contextEnvelope = AgentTurnContextBuilder.build(
            turnID: turnID,
            userText: text,
            hasCurrentMedia: false,
            turnSentAt: submittedAt,
            businessSummary: context.structuredContext(for: businessDate),
            effectiveBusinessDate: businessDate,
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
            turnSentAt: submittedAt,
            effectiveBusinessDate: businessDate,
            businessTimeZone: context.session.businessTimeZone,
            createdAt: submittedAt
        )
        job.executionKind = .deterministicWorkout
        job.deterministicWorkoutDraft = draft
        do {
            context.session.recordUserMessage(text, at: submittedAt)
            try ConversationTurnPersistence.enqueue(
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
                && ($0.state == .waitingForUser
                    || $0.state == .staged
                    || $0.state == .waitingForNetwork)
        }) {
            do {
                if let responseID = existing.responseMessageID,
                   let response = ConversationTurnPersistence.message(
                       id: responseID,
                       in: context.modelContext
                   )
                {
                    ConversationTurnPersistence.prepareResponseMessageForManualRetry(
                        response,
                        from: existing
                    )
                }
                try ConversationTurnPersistence.releaseForManualRetry(
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
        let previousJob = existingJobs.first { $0.userMessageID == userMessage.id }
        let businessDate = context.businessDate(
            for: userMessage.text,
            turnSentAt: userMessage.date
        )
        let contextEnvelope = AgentTurnContextBuilder.build(
            turnID: retryTurnID,
            userText: userMessage.text,
            hasCurrentMedia: !userMessage.mediaAttachments.isEmpty,
            turnSentAt: userMessage.date,
            businessSummary: context.structuredContext(
                for: businessDate,
                selectedSkillID: previousJob?.selectedSkillID
            ),
            effectiveBusinessDate: businessDate,
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
            turnSentAt: userMessage.date,
            effectiveBusinessDate: businessDate,
            businessTimeZone: context.session.businessTimeZone,
            selectedSkillID: existingJobs.first(where: {
                $0.userMessageID == userMessage.id
            })?.selectedSkillID,
            selectedShortcutID: existingJobs.first(where: {
                $0.userMessageID == userMessage.id
            })?.selectedShortcutID,
            createdAt: submittedAt
        )
        do {
            if let previous = existingJobs.first(where: {
                $0.userMessageID == userMessage.id && $0.state.isTerminal
            }),
                let responseID = previous.responseMessageID,
                let response = ConversationTurnPersistence.message(
                    id: responseID,
                    in: context.modelContext
                )
            {
                ConversationTurnPersistence.prepareResponseMessageForManualRetry(
                    response,
                    from: previous,
                    to: job
                )
            } else {
                let response = CoachMessage(
                    date: submittedAt,
                    sessionID: job.sessionID,
                    isFromCoach: true,
                    text: "",
                    agentStatus: .running,
                    agentTurnItems: [AgentTurnItem(
                        sequence: 1,
                        kind: .activity,
                        status: .running,
                        phase: .queued,
                        title: "已收到，正在准备处理…",
                        text: "已收到，正在准备处理…",
                        startedAt: submittedAt
                    )],
                    turnID: job.turnID,
                    attemptNumber: ConversationTurnPersistence.nextAttemptNumber(
                        for: job.turnID,
                        in: context.modelContext
                    )
                )
                job.responseMessageID = response.id
                context.modelContext.insert(response)
            }
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
        expectedCandidateID: UUID? = nil
    ) {
        guard !isProcessing else { return }
        if let expectedCandidateID {
            var descriptor = FetchDescriptor<AgentJob>(
                predicate: #Predicate { $0.id == expectedCandidateID }
            )
            descriptor.fetchLimit = 1
            guard (try? modelContext.fetch(descriptor).first) != nil else {
                return
            }
        }
        do {
            _ = try ConversationTurnPersistence.recoverExpiredLeases(
                dataSpace: dataSpace,
                in: modelContext
            )
            _ = try ConversationTurnPersistence.resumeForegroundJobs(
                dataSpace: dataSpace,
                in: modelContext
            )
        } catch {
            return
        }
        // startNextPendingJob 会在领取 FIFO 队头前统一收口失败回复；
        // 这里不再对同一组非终态 Job 重复扫描一次。
        startNextPendingJob(
            dataSpace: dataSpace,
            ai: ai,
            modelContext: modelContext,
            locationService: locationService
        )
    }

    func resumePendingJobsAfterForeground(
        dataSpace: DataSpace,
        ai: AIService,
        modelContainer: ModelContainer,
        modelContext: ModelContext,
        locationService: LocationContextService
    ) async {
        guard !isProcessing else { return }
        let interval = AppPerformance.begin(
            .jobRecovery,
            detail: "phase=candidate_read"
        )
        let reader = AgentJobRecoveryCandidateReader(modelContainer: modelContainer)
        let candidateID = try? await reader.firstCandidateID(dataSpace: dataSpace)
        guard let candidateID else {
            AppPerformance.end(interval, detail: "result=empty")
            return
        }
        AppPerformance.end(interval, detail: "result=candidate")
        resumePendingJobs(
            dataSpace: dataSpace,
            ai: ai,
            modelContext: modelContext,
            locationService: locationService,
            expectedCandidateID: candidateID
        )
    }

    @discardableResult
    func retryPendingQueue(
        dataSpace: DataSpace,
        ai: AIService,
        modelContext: ModelContext,
        locationService: LocationContextService
    ) -> Bool {
        guard !isProcessing else { return false }
        do {
            let released = try ConversationTurnPersistence.releasePendingQueueForManualRetry(
                dataSpace: dataSpace,
                in: modelContext
            )
            guard !released.isEmpty else { return false }
        } catch {
            modelContext.rollback()
            return false
        }
        startNextPendingJob(
            dataSpace: dataSpace,
            ai: ai,
            modelContext: modelContext,
            locationService: locationService
        )
        return true
    }

    @discardableResult
    func discardPendingTurn(
        turnID: UUID,
        context: ConversationProcessingContext,
        locationService: LocationContextService
    ) -> Bool {
        guard !isProcessing else { return false }
        var jobDescriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate { $0.turnID == turnID }
        )
        jobDescriptor.fetchLimit = 1
        guard let job = try? context.modelContext.fetch(jobDescriptor).first,
              [.staged, .waitingForUser, .queued, .waitingForNetwork]
              .contains(job.state)
        else {
            return false
        }
        let attachments = job.mediaAttachments
        let messageIDs = Set([job.userMessageID, job.responseMessageID].compactMap { $0 })
        let jobID = job.id
        let events = (try? context.modelContext.fetch(
            FetchDescriptor<PersistentAgentEvent>(
                predicate: #Predicate { $0.jobID == jobID }
            )
        )) ?? []
        events.forEach(context.modelContext.delete)
        for messageID in messageIDs {
            var messageDescriptor = FetchDescriptor<CoachMessage>(
                predicate: #Predicate { $0.id == messageID }
            )
            messageDescriptor.fetchLimit = 1
            guard let message = try? context.modelContext.fetch(messageDescriptor).first else {
                continue
            }
            if let traceID = message.agentTraceID {
                var traceDescriptor = FetchDescriptor<AgentTrace>(
                    predicate: #Predicate { $0.id == traceID }
                )
                traceDescriptor.fetchLimit = 1
                if let trace = try? context.modelContext.fetch(traceDescriptor).first {
                    context.modelContext.delete(trace)
                }
            }
            context.modelContext.delete(message)
        }
        context.modelContext.delete(job)
        do {
            try context.modelContext.save()
            for attachment in attachments {
                _ = MediaStore.removeStoredFile(at: attachment.path)
            }
            _ = try ConversationTurnPersistence.releaseStagedJobs(
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
        let dataSpaceRaw = context.dataSpace.rawValue
        let candidates = (try? context.modelContext.fetch(FetchDescriptor<AgentJob>(
            predicate: #Predicate { $0.dataSpaceRaw == dataSpaceRaw }
        ))) ?? []
        let targets = candidates.filter {
            [.staged, .waitingForUser, .queued, .waitingForNetwork].contains($0.state)
        }
        guard !targets.isEmpty else { return false }
        let messageIDs = Set(targets.flatMap {
            [$0.userMessageID, $0.responseMessageID].compactMap { $0 }
        })
        let attachments = targets.flatMap(\.mediaAttachments)
        for target in targets {
            let targetID = target.id
            let events = (try? context.modelContext.fetch(
                FetchDescriptor<PersistentAgentEvent>(
                    predicate: #Predicate { $0.jobID == targetID }
                )
            )) ?? []
            events.forEach(context.modelContext.delete)
        }
        for messageID in messageIDs {
            var messageDescriptor = FetchDescriptor<CoachMessage>(
                predicate: #Predicate { $0.id == messageID }
            )
            messageDescriptor.fetchLimit = 1
            guard let message = try? context.modelContext.fetch(messageDescriptor).first else {
                continue
            }
            if let traceID = message.agentTraceID {
                var traceDescriptor = FetchDescriptor<AgentTrace>(
                    predicate: #Predicate { $0.id == traceID }
                )
                traceDescriptor.fetchLimit = 1
                if let trace = try? context.modelContext.fetch(traceDescriptor).first {
                    context.modelContext.delete(trace)
                }
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
            try? ConversationTurnPersistence.waitForUser(
                job,
                message: "快捷训练数据已损坏，请删除后重新选择建议。",
                in: context.modelContext
            )
            return
        }
        let (responseMessage, attemptNumber) = ConversationTurnPersistence.bindResponseMessage(
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
        try? BusinessIDAllocator.assignMissingIDs(in: context.modelContext)
        let exerciseID = draft.exerciseID
        var definitionDescriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { $0.id == exerciseID }
        )
        definitionDescriptor.fetchLimit = 1
        let exerciseBusinessID = (
            try? context.modelContext.fetch(definitionDescriptor).first?.businessID
        ) ?? 0
        let call = AgentToolCall(
            name: .createWorkout,
            arguments: AgentToolArguments(
                workouts: [
                    AgentWorkoutCreateInput(
                        exerciseID: exerciseBusinessID,
                        setEntries: draft.setEntries.map {
                            AgentWorkoutSetInput(
                                reps: $0.reps,
                                externalWeightKG: $0.externalWeightKG
                            )
                        },
                        restSeconds: draft.restSeconds,
                        durationMinutes: draft.durationMinutes
                    )
                ]
            )
        )
        let spanID = UUID()
        let operationID = spanID.uuidString.lowercased()
        let startedAt = Date.now
        PersistentAgentEventProjection.persistAndProject(
            .span(AgentTraceSpan(
                id: spanID,
                step: 1,
                kind: .tool,
                title: "保存最近训练数据",
                status: .running,
                operationID: operationID,
                phase: .preparing,
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
        PersistentAgentEventProjection.persistAndProject(
            .span(AgentTraceSpan(
                id: spanID,
                step: 1,
                kind: .tool,
                title: "保存最近训练数据",
                status: .running,
                operationID: operationID,
                phase: .running,
                startedAt: startedAt,
                endedAt: .now,
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
            sourceDate: job.stableDefaultOccurredAt,
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
                operationID: operationID,
                phase: result.ok ? .completed : .failed,
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
            responseMessage.text = ""
            responseMessage.agentStatus = .failed
            responseMessage.applyAgentEvent(.failed(
                message: result.observation,
                cancelled: false,
                at: endedAt
            ))
            try? ConversationTurnPersistence.waitForUser(
                job,
                message: result.observation,
                in: context.modelContext
            )
            return
        }
        let answer = "已按你选择的最近一次训练数据完成记录。"
        let itemID = UUID()
        PersistentAgentEventProjection.persistAndProject(
            .assistantTextCompleted(itemID: itemID, at: endedAt),
            job: job,
            responseMessage: responseMessage,
            trace: trace,
            liveText: LiveAgentTextSnapshot(itemID: itemID, text: answer),
            in: context.modelContext
        )
        responseMessage.text = answer
        responseMessage.recordType = .workout
        responseMessage.agentStatus = .succeeded
        trace.apply(.completed(answer: answer, at: endedAt))
        try? job.transition(to: .succeeded, at: endedAt)
        _ = try? ConversationTurnPersistence.append(
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
