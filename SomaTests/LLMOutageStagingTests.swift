@testable import Soma
import SwiftData
import SwiftOpenAI
import XCTest

/// 失败一旦越过 ReAct Loop 就等待用户重试，队列保持严格 FIFO。
final class LLMOutageStagingTests: XCTestCase {
    func testTransportFailuresWaitForManualRetryOutsideLoop() {
        for error in [
            URLError(.notConnectedToInternet),
            URLError(.timedOut),
            URLError(.networkConnectionLost)
        ] {
            guard case let .waitForUser(message) =
                LLMOutageClassifier.disposition(for: error)
            else {
                return XCTFail("传输失败越过 Loop 后必须等待用户")
            }
            XCTAssertTrue(message.contains("手动重试"))
        }
    }

    func testMissingConfigurationAndInvalidEndpointWaitForUser() {
        guard case .waitForUser = LLMOutageClassifier.disposition(
            for: AIServiceError.missingAPIKey("OpenAI")
        ) else {
            return XCTFail("缺少 API Key 应该等待用户")
        }
        XCTAssertTrue(
            LLMOutageClassifier
                .signal(for: AIServiceError.missingAPIKey("OpenAI"))
                .isMissingConfiguration
        )
        guard case .waitForUser = LLMOutageClassifier.disposition(
            for: AIServiceError.invalidURL
        ) else {
            return XCTFail("地址无效应该等待用户")
        }
    }

    func testProviderFailuresWaitForUserAndRequestErrorsFail() {
        for status in [401, 403, 408, 409, 425, 429, 500, 502, 503] {
            guard case .waitForUser = disposition(forStatus: status) else {
                return XCTFail("\(status) 应该等待用户手动重试")
            }
        }
        for status in [400, 404, 413, 422] {
            XCTAssertEqual(
                disposition(forStatus: status),
                .fail,
                "\(status) 不应该进入暂存循环"
            )
        }
    }

    func testQuotaExhaustionWaitsForExplicitUserRetry() {
        let quotaDisposition = LLMOutageClassifier.disposition(
            for: APIError.responseUnsuccessful(
                description: #"{"error":{"code":"insufficient_quota"}}"#,
                statusCode: 429
            )
        )
        guard case let .waitForUser(message) = quotaDisposition else {
            return XCTFail("欠费必须等待用户手动重试")
        }
        XCTAssertTrue(message.contains("不会自动继续"))
        guard case .waitForUser = disposition(forStatus: 429) else {
            return XCTFail("普通 429 越过 Loop 后也必须等待用户")
        }
    }

    func testUnsupportedMultimodalFailsWithoutStaging() {
        XCTAssertEqual(
            LLMOutageClassifier.disposition(
                for: AIServiceError.multimodalUnsupported(
                    provider: "DeepSeek",
                    model: "deepseek-chat"
                )
            ),
            .fail
        )
    }

    func testOnlyLoopRetryPolicyKeepsThreeExponentialRetries() {
        XCTAssertEqual(AgentStepRetryPolicy.maximumRetryCount, 3)
        XCTAssertEqual((1 ... 3).map(AgentStepRetryPolicy.delay), [1, 2, 4])
        XCTAssertTrue(
            LLMOutageClassifier.isLoopRetryable(URLError(.networkConnectionLost))
        )
        XCTAssertFalse(
            LLMOutageClassifier.isLoopRetryable(AIServiceError.missingAPIKey("OpenAI"))
        )
    }

    @MainActor
    func testStagedStateAllowsResumeButNotTerminalRestart() throws {
        let job = makeJob()

        try job.transition(to: .staged)
        XCTAssertFalse(job.state.isRunnable)
        XCTAssertFalse(job.state.isTerminal)
        XCTAssertTrue(job.state.canTransition(to: .running))
        XCTAssertTrue(job.state.canTransition(to: .queued))

        try job.transition(to: .running)
        try job.transition(to: .succeeded)
        XCTAssertFalse(job.state.canTransition(to: .staged))
    }

    @MainActor
    func testWaitingForUserBlocksFollowingJobsUntilManualRelease() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = makeJob(createdAt: Date(timeIntervalSince1970: 10))
        let second = makeJob(createdAt: Date(timeIntervalSince1970: 20))
        context.insert(first)
        context.insert(second)
        try context.save()
        try AgentJobStore.claim(first, owner: "runner", in: context)
        try AgentJobStore.waitForUser(first, message: "额度已用尽", in: context)
        try AgentJobStore.stageFollowingJobs(
            after: first,
            message: "等待前一条",
            in: context
        )

        XCTAssertEqual(first.state, .waitingForUser)
        XCTAssertEqual(second.state, .staged)
        XCTAssertNil(try AgentJobStore.claimNext(
            dataSpace: .personal,
            owner: "runner",
            in: context
        ))

        try AgentJobStore.releaseForManualRetry(
            first,
            dataSpace: .personal,
            in: context
        )
        XCTAssertEqual(first.state, .queued)
        XCTAssertEqual(second.state, .queued)
        XCTAssertEqual(
            try AgentJobStore.claimNext(
                dataSpace: .personal,
                owner: "runner",
                in: context
            )?.id,
            first.id
        )
    }

    @MainActor
    func testUserInterruptionUsesTheSameManualRetryBarrier() throws {
        let suiteName = "ConversationInterruptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(defaults: defaults, isStoredInMemoryOnly: true)
        let modelContext = ModelContext(spaces.personalContainer)
        let session = ConversationSession()
        let userMessage = CoachMessage(
            sessionID: session.id,
            isFromCoach: false,
            text: "分析这次虚构训练",
            turnID: UUID()
        )
        let job = try AgentJob(
            turnID: XCTUnwrap(userMessage.turnID),
            sessionID: session.id,
            userMessageID: userMessage.id,
            dataSpace: .personal,
            userText: userMessage.text,
            mediaAttachments: [],
            contextSnapshot: AgentJobContextSnapshot(
                structuredContext: "虚构上下文",
                includeLocation: false
            )
        )
        modelContext.insert(session)
        modelContext.insert(userMessage)
        modelContext.insert(job)
        try modelContext.save()
        try AgentJobStore.claim(job, owner: "test-runner", in: modelContext)
        let ai = AIService(defaults: defaults, apiKeyOverride: "test-key")
        let context = ConversationProcessingContext(
            structuredContext: "",
            session: session,
            dataSpace: .personal,
            gyms: [],
            equipment: [],
            ai: ai,
            modelContext: modelContext
        )
        let processor = ConversationProcessingService(
            backgroundLease: StagingTestBackgroundLease()
        )
        processor.isProcessing = true
        processor.dataSpace = .personal
        processor.sessionID = session.id
        processor.activeJobID = job.id

        XCTAssertTrue(processor.interruptActiveProcessing(context: context))

        let response = try XCTUnwrap(
            try modelContext.fetch(FetchDescriptor<CoachMessage>())
                .first(where: \.isFromCoach)
        )
        XCTAssertEqual(job.state, .waitingForUser)
        XCTAssertEqual(response.agentStatus, .cancelled)
        XCTAssertTrue(response.agentTurnItems.contains { $0.kind == .error })
        XCTAssertTrue(ConversationTurnProjection.canRetry(
            response,
            in: [userMessage, response],
            job: job
        ))
        XCTAssertNil(try AgentJobStore.claimNext(
            dataSpace: .personal,
            owner: "another-runner",
            in: modelContext
        ))
    }

    @MainActor
    func testRetryAllPendingReleasesEveryItemInFIFOOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = makeJob(createdAt: Date(timeIntervalSince1970: 10))
        let second = makeJob(createdAt: Date(timeIntervalSince1970: 20))
        let third = makeJob(createdAt: Date(timeIntervalSince1970: 30))
        for job in [first, second, third] {
            context.insert(job)
        }
        try context.save()
        try AgentJobStore.claim(first, owner: "runner", in: context)
        try AgentJobStore.waitForUser(first, message: "额度已用尽", in: context)
        try AgentJobStore.stageFollowingJobs(
            after: first,
            message: "等待前一条",
            in: context
        )

        let released = try AgentJobStore.releasePendingQueueForManualRetry(
            dataSpace: .personal,
            in: context
        )

        XCTAssertEqual(released, [first.id, second.id, third.id])
        XCTAssertTrue([first, second, third].allSatisfy { $0.state == .queued })
        XCTAssertEqual(
            try AgentJobStore.claimNext(
                dataSpace: .personal,
                owner: "runner",
                in: context
            )?.id,
            first.id
        )
    }

    @MainActor
    func testStagingRecordsEventAndClearsLease() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let job = makeJob()
        context.insert(job)
        try context.save()
        try AgentJobStore.claim(job, owner: "test", in: context)

        try AgentJobStore.stage(
            job,
            message: "还没有可用的 LLM 配置，消息已暂存。",
            retryDelay: nil,
            in: context
        )

        XCTAssertEqual(job.state, .staged)
        XCTAssertNil(job.leaseOwner)
        XCTAssertNil(job.leaseExpiresAt)
        XCTAssertNil(job.nextRetryAt)
        XCTAssertTrue(
            AgentJobStore.events(for: job.id, in: context)
                .contains { $0.kind == .staged }
        )
    }

    @MainActor
    func testStagingWithDelaySetsBoundedRetryWindow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let job = makeJob()
        context.insert(job)
        try context.save()

        let now = Date(timeIntervalSince1970: 1_000_000)
        try AgentJobStore.stage(
            job,
            message: "模型服务暂时不可用，消息已暂存。",
            retryDelay: 300,
            now: now,
            in: context
        )

        XCTAssertEqual(job.nextRetryAt, now.addingTimeInterval(300))
    }

    @MainActor
    func testReleaseStagedJobsRespectsReadinessAndClearsBackoff() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let ready = makeJob(createdAt: Date(timeIntervalSince1970: 10))
        let blocked = makeJob(createdAt: Date(timeIntervalSince1970: 20))
        blocked.backend = .remote
        context.insert(ready)
        context.insert(blocked)
        try context.save()
        for job in [ready, blocked] {
            try AgentJobStore.stage(
                job,
                message: "暂存",
                retryDelay: 300,
                in: context
            )
        }
        XCTAssertEqual(
            AgentJobStore.stagedJobCount(dataSpace: .personal, in: context),
            2
        )

        let released = try AgentJobStore.releaseStagedJobs(
            dataSpace: .personal,
            in: context
        ) { $0.backend == .local }

        XCTAssertEqual(released, [ready.id])
        XCTAssertEqual(ready.state, .queued)
        XCTAssertNil(ready.nextRetryAt)
        XCTAssertEqual(blocked.state, .staged)
        XCTAssertEqual(
            AgentJobStore.stagedJobCount(dataSpace: .personal, in: context),
            1
        )
    }

    @MainActor
    func testFailedResponsePromotesOutOfAutomaticRecovery() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let job = makeJob()
        let response = CoachMessage(
            isFromCoach: true,
            text: "这次没有处理成功",
            agentStatus: .failed,
            turnID: job.turnID
        )
        context.insert(response)
        context.insert(job)
        try context.save()
        job.responseMessageID = response.id
        try job.transition(to: .running)
        try job.transition(to: .waitingForNetwork)

        let promoted = try AgentJobStore.promoteFailedResponsesToManualRetry(
            dataSpace: .personal,
            in: context
        )

        XCTAssertEqual(promoted, [job.id])
        XCTAssertEqual(job.state, .waitingForUser)
        XCTAssertNil(job.nextRetryAt)
        XCTAssertTrue(
            ConversationTurnProjection.canRetry(response, in: [response], job: job)
        )
        XCTAssertNil(try AgentJobStore.claimNext(
            dataSpace: .personal,
            owner: "runner",
            in: context
        ))
    }

    @MainActor
    func testWaitingForNetworkRequiresManualRelease() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let job = makeJob()
        let response = CoachMessage(
            isFromCoach: true,
            text: "网络连接中断。请检查网络后手动重试。",
            agentStatus: .failed,
            turnID: job.turnID
        )
        context.insert(response)
        context.insert(job)
        try context.save()
        job.responseMessageID = response.id
        try job.transition(to: .running)
        try job.transition(to: .waitingForNetwork)
        job.nextRetryAt = nil
        try context.save()

        XCTAssertEqual(try AgentJobStore.promoteFailedResponsesToManualRetry(
            dataSpace: .personal,
            in: context
        ), [job.id])
        XCTAssertEqual(job.state, .waitingForUser)
        XCTAssertTrue(
            ConversationTurnProjection.canRetry(response, in: [response], job: job)
        )
        XCTAssertNil(try AgentJobStore.claimNext(
            dataSpace: .personal,
            owner: "runner",
            in: context
        ))
    }

    @MainActor
    func testMissingAPIKeyStagesMessageInsteadOfRejectingSend() throws {
        let suiteName = "LLMOutageStagingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let context = ModelContext(spaces.personalContainer)
        let session = ConversationSession()
        context.insert(session)
        let ai = AIService(defaults: defaults, apiKeyOverride: "")
        ai.configure(
            provider: .openAI,
            baseURL: "https://example.com/v1",
            model: "gpt-4.1-mini"
        )
        let processor = ConversationProcessingService(
            backgroundLease: StagingTestBackgroundLease()
        )
        let processingContext = ConversationProcessingContext(
            structuredContext: "",
            session: session,
            dataSpace: .personal,
            gyms: [],
            equipment: [],
            ai: ai,
            modelContext: context
        )

        for text in ["卧推 60kg 8 次 3 组", "深蹲 80kg 5 次 5 组", "硬拉 100kg 3 次"] {
            XCTAssertTrue(processor.submit(
                text: text,
                attachments: [],
                context: processingContext,
                includeLocation: false,
                locationService: LocationContextService()
            ))
        }

        let jobs = try context.fetch(
            FetchDescriptor<AgentJob>(sortBy: [SortDescriptor(\.createdAt)])
        )
        XCTAssertEqual(jobs.count, 3)
        XCTAssertTrue(jobs.allSatisfy { $0.state == .staged })
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CoachMessage>()).count,
            6
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<AgentTrace>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutEntry>()).isEmpty)
    }

    @MainActor
    func testPendingQueueSupportsSingleDiscardAndClearAll() throws {
        let suiteName = "LLMOutageStagingTests.queue.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(defaults: defaults, isStoredInMemoryOnly: true)
        let modelContext = ModelContext(spaces.personalContainer)
        let session = ConversationSession()
        modelContext.insert(session)
        let ai = AIService(defaults: defaults, apiKeyOverride: "")
        ai.configure(
            provider: .openAI,
            baseURL: "https://example.com/v1",
            model: "gpt-4.1-mini"
        )
        let processor = ConversationProcessingService(
            backgroundLease: StagingTestBackgroundLease()
        )
        let processingContext = ConversationProcessingContext(
            structuredContext: "",
            session: session,
            dataSpace: .personal,
            gyms: [],
            equipment: [],
            ai: ai,
            modelContext: modelContext
        )
        let location = LocationContextService()
        for text in ["记录深蹲 4组8次", "记录卧推 3组10次", "记录硬拉 5组5次"] {
            XCTAssertTrue(processor.submit(
                text: text,
                attachments: [],
                context: processingContext,
                includeLocation: false,
                locationService: location
            ))
        }
        let jobs = try modelContext.fetch(
            FetchDescriptor<AgentJob>(sortBy: [SortDescriptor(\.createdAt)])
        )
        XCTAssertEqual(jobs.count, 3)

        XCTAssertTrue(processor.discardPendingTurn(
            turnID: jobs[0].turnID,
            context: processingContext,
            locationService: location
        ))
        XCTAssertEqual(try modelContext.fetch(FetchDescriptor<AgentJob>()).count, 2)
        XCTAssertEqual(try modelContext.fetch(FetchDescriptor<CoachMessage>()).count, 4)

        XCTAssertTrue(processor.clearPendingQueue(context: processingContext))
        XCTAssertTrue(try modelContext.fetch(FetchDescriptor<AgentJob>()).isEmpty)
        XCTAssertTrue(try modelContext.fetch(FetchDescriptor<CoachMessage>()).isEmpty)
        XCTAssertTrue(
            try modelContext.fetch(FetchDescriptor<PersistentAgentEvent>()).isEmpty
        )
    }

    @MainActor
    func testExactQuickWorkoutRunsWithoutLLMAndUsesStableTurnTime() async throws {
        let suiteName = "QuickWorkoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(defaults: defaults, isStoredInMemoryOnly: true)
        let context = ModelContext(spaces.personalContainer)
        let session = ConversationSession()
        let exercise = ExerciseDefinition(canonicalName: "杠铃深蹲")
        context.insert(session)
        context.insert(exercise)
        try context.save()
        let ai = AIService(defaults: defaults, apiKeyOverride: "")
        let processor = ConversationProcessingService(
            backgroundLease: StagingTestBackgroundLease()
        )
        XCTAssertTrue(processor.submitQuickWorkout(
            text: "杠铃深蹲：60kg × 8 × 4组",
            draft: ExerciseQuickRecordDraft(
                exerciseID: exercise.id,
                exerciseName: exercise.canonicalName,
                setEntries: (0 ..< 4).map { _ in
                    WorkoutSetEvidence(reps: 8, externalWeightKG: 60)
                },
                restSeconds: 90,
                durationMinutes: nil
            ),
            context: ConversationProcessingContext(
                structuredContext: "",
                session: session,
                dataSpace: .personal,
                gyms: [],
                equipment: [],
                ai: ai,
                modelContext: context
            ),
            locationService: LocationContextService()
        ))
        for _ in 0 ..< 100 where processor.isProcessing {
            try await Task.sleep(for: .milliseconds(20))
        }

        let workout = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WorkoutEntry>()).first
        )
        let job = try XCTUnwrap(try context.fetch(FetchDescriptor<AgentJob>()).first)
        XCTAssertEqual(job.executionKind, .deterministicWorkout)
        XCTAssertEqual(job.state, .succeeded)
        XCTAssertEqual(workout.setEntries.count, 4)
        XCTAssertEqual(workout.date, job.stableDefaultOccurredAt)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AgentTrace>()).allSatisfy {
            $0.provider == "Soma 本机规则"
        })
    }

    private func disposition(forStatus status: Int) -> LLMFailureDisposition {
        LLMOutageClassifier.disposition(
            for: APIError.responseUnsuccessful(
                description: "服务端错误",
                statusCode: status
            )
        )
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: AgentJob.self,
            PersistentAgentEvent.self,
            CoachMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor
    private func makeJob(createdAt: Date = .now) -> AgentJob {
        AgentJob(
            turnID: UUID(),
            sessionID: UUID(),
            userMessageID: UUID(),
            dataSpace: .personal,
            userText: "测试",
            mediaAttachments: [],
            contextSnapshot: AgentJobContextSnapshot(
                structuredContext: "测试上下文",
                includeLocation: false,
                createdAt: createdAt
            ),
            createdAt: createdAt
        )
    }
}

@MainActor
private final class StagingTestBackgroundLease: BackgroundExecutionLease {
    private(set) var isActive = false

    func begin(expiration _: @escaping @MainActor () -> Void) {
        isActive = true
    }

    func end() {
        isActive = false
    }
}
