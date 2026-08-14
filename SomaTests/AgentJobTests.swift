@testable import Soma
import SwiftData
import SwiftOpenAI
import XCTest

final class AgentJobTests: XCTestCase {
    @MainActor
    func testStateMachineRejectsTerminalRestart() throws {
        let job = makeJob()

        try job.transition(to: .running)
        try job.transition(to: .succeeded)

        XCTAssertTrue(job.state.isTerminal)
        XCTAssertThrowsError(try job.transition(to: .queued)) { error in
            XCTAssertEqual(
                error as? AgentJobStateError,
                .invalidTransition(from: .succeeded, to: .queued)
            )
        }
    }

    @MainActor
    func testEventSequenceIsStableAndCursorDoesNotDeleteEvents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let job = makeJob()
        context.insert(job)
        try context.save()

        _ = try AgentJobStore.append(kind: .jobQueued, to: job, in: context)
        _ = try AgentJobStore.append(
            kind: .assistantTextCompleted,
            payload: .init(text: "完成"),
            to: job,
            in: context
        )

        XCTAssertEqual(
            AgentJobStore.events(for: job.id, in: context).map(\.sequence),
            [1, 2]
        )
        XCTAssertEqual(
            AgentJobStore.events(for: job.id, after: 1, in: context)
                .first?.payload.text,
            "完成"
        )
        XCTAssertEqual(
            AgentJobStore.events(for: job.id, in: context).count,
            2
        )
    }

    @MainActor
    func testRemoteTextDeltasReplayWithoutWaitingForCompletion() {
        let jobID = UUID()
        let turnID = UUID()
        let itemID = UUID()
        let message = CoachMessage(isFromCoach: true, text: "")
        let events = [
            PersistentAgentEvent(
                jobID: jobID,
                turnID: turnID,
                sequence: 1,
                attemptNumber: 1,
                kind: .assistantTextDelta,
                payload: .init(itemID: itemID, text: "第一段")
            ),
            PersistentAgentEvent(
                jobID: jobID,
                turnID: turnID,
                sequence: 2,
                attemptNumber: 1,
                kind: .assistantTextDelta,
                payload: .init(itemID: itemID, text: "完成。")
            ),
            PersistentAgentEvent(
                jobID: jobID,
                turnID: turnID,
                sequence: 3,
                attemptNumber: 1,
                kind: .assistantTextCompleted,
                payload: .init(itemID: itemID)
            )
        ]

        PersistentAgentEventProjection.replayChat(
            events: events,
            onto: message
        )

        XCTAssertEqual(message.text, "第一段完成。")
        XCTAssertEqual(message.agentTurnItems.count, 1)
        XCTAssertEqual(message.agentTurnItems.first?.text, "第一段完成。")
        XCTAssertEqual(message.agentTurnItems.first?.status, .succeeded)
    }

    @MainActor
    func testClaimAndExpiredLeaseRecoveryStayInsideDataSpace() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 100)
        let personal = makeJob(dataSpace: .personal, createdAt: now)
        let demo = makeJob(dataSpace: .demo, createdAt: now.addingTimeInterval(1))
        context.insert(personal)
        context.insert(demo)
        try context.save()

        let claimed = try XCTUnwrap(AgentJobStore.claimNext(
            dataSpace: .personal,
            owner: "test-runner",
            now: now,
            leaseDuration: 5,
            in: context
        ))

        XCTAssertEqual(claimed.id, personal.id)
        XCTAssertEqual(claimed.activeAttemptNumber, 1)
        XCTAssertEqual(claimed.loopStartedAt, now)
        XCTAssertEqual(demo.state, .queued)
        XCTAssertEqual(
            try AgentJobStore.recoverExpiredLeases(
                dataSpace: .personal,
                now: now.addingTimeInterval(6),
                in: context
            ),
            [personal.id]
        )
        XCTAssertEqual(personal.state, .waitingForForeground)
        XCTAssertEqual(demo.state, .queued)
    }

    @MainActor
    func testLoopStartTimeIsFrozenAcrossManualRetry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sentAt = Date(timeIntervalSince1970: 100)
        let firstStart = sentAt.addingTimeInterval(20)
        let interruptedAt = firstStart.addingTimeInterval(35)
        let retryAt = sentAt.addingTimeInterval(3600)
        let job = makeJob(createdAt: sentAt)
        context.insert(job)
        try context.save()

        try AgentJobStore.claim(job, owner: "runner", now: firstStart, in: context)
        try AgentJobStore.waitForUser(
            job,
            message: "手动重试",
            now: interruptedAt,
            in: context
        )
        XCTAssertEqual(job.loopActiveDuration, 35)
        try AgentJobStore.releaseForManualRetry(
            job,
            dataSpace: .personal,
            now: retryAt,
            in: context
        )
        XCTAssertEqual(job.loopActiveDuration, 0)
        try AgentJobStore.claim(job, owner: "runner", now: retryAt, in: context)

        XCTAssertEqual(job.loopStartedAt, firstStart)
        XCTAssertEqual(
            job.activeLoopDuration(at: retryAt.addingTimeInterval(5)),
            5
        )
    }

    @MainActor
    func testAutomaticResumeExcludesWaitingTimeWithoutResettingConsumedBudget() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let firstStart = Date(timeIntervalSince1970: 100)
        let waitingAt = firstStart.addingTimeInterval(12)
        let resumedAt = firstStart.addingTimeInterval(3600)
        let job = makeJob(createdAt: firstStart)
        context.insert(job)
        try context.save()

        try AgentJobStore.claim(job, owner: "runner", now: firstStart, in: context)
        try job.transition(to: .waitingForNetwork, at: waitingAt)
        try job.transition(to: .queued, at: resumedAt)
        try AgentJobStore.claim(job, owner: "runner", now: resumedAt, in: context)

        XCTAssertEqual(job.loopStartedAt, firstStart)
        XCTAssertEqual(job.loopActiveDuration, 12)
        XCTAssertEqual(
            job.activeLoopDuration(at: resumedAt.addingTimeInterval(8)),
            20
        )
    }

    @MainActor
    func testAgentJobArchivePreservesPausedActiveBudget() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let startedAt = Date(timeIntervalSince1970: 100)
        let job = makeJob(createdAt: startedAt)
        context.insert(job)
        try context.save()

        try AgentJobStore.claim(job, owner: "runner", now: startedAt, in: context)
        try job.transition(
            to: .waitingForNetwork,
            at: startedAt.addingTimeInterval(14)
        )

        let restored = AgentJobDTO(job).makeModel(mediaPathMapping: [:])

        XCTAssertEqual(restored.loopActiveDuration, 14)
        XCTAssertNil(restored.loopActiveStartedAt)
    }

    @MainActor
    func testBackgroundLeaseExpirationKeepsJobRecoverable() async throws {
        let suiteName = "AgentJobTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let context = ModelContext(spaces.personalContainer)
        let session = ConversationSession()
        context.insert(session)
        let lease = TestBackgroundExecutionLease()
        let processor = ConversationProcessingService(backgroundLease: lease)
        let ai = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key",
            agentStreamLoader: { _, _, _, _ in
                AsyncThrowingStream { continuation in
                    Task {
                        try? await Task.sleep(for: .seconds(30))
                        continuation.finish()
                    }
                }
            }
        )
        ai.configure(
            provider: .openAI,
            baseURL: "https://example.com/v1",
            model: "gpt-4.1-mini"
        )

        XCTAssertTrue(processor.submit(
            text: "记录测试训练",
            attachments: [],
            context: ConversationProcessingContext(
                structuredContext: "测试上下文",
                session: session,
                dataSpace: .personal,
                gyms: [],
                equipment: [],
                ai: ai,
                modelContext: context
            ),
            includeLocation: false,
            locationService: LocationContextService()
        ))
        // ADR 0045：已有任务在途时继续发送只是排队，不再被拒绝。
        XCTAssertTrue(processor.submit(
            text: "继续记录下一组",
            attachments: [],
            context: ConversationProcessingContext(
                structuredContext: "测试上下文",
                session: session,
                dataSpace: .personal,
                gyms: [],
                equipment: [],
                ai: ai,
                modelContext: context
            ),
            includeLocation: false,
            locationService: LocationContextService()
        ))
        lease.expire()

        for _ in 0 ..< 100 where processor.isProcessing {
            try await Task.sleep(for: .milliseconds(20))
        }

        let jobs = try context.fetch(
            FetchDescriptor<AgentJob>(sortBy: [SortDescriptor(\.createdAt)])
        )
        XCTAssertEqual(jobs.count, 2)
        let job = try XCTUnwrap(jobs.first)
        XCTAssertEqual(job.state, .waitingForForeground)
        XCTAssertFalse(job.state.isTerminal)
        XCTAssertTrue(
            AgentJobStore.events(for: job.id, in: context)
                .contains { $0.kind == .waitingForForeground }
        )
        // 排在后面的消息保持可运行，不因为前一条被挂起而丢失。
        XCTAssertEqual(jobs.last?.state, .queued)
    }

    @MainActor
    func testAttachmentPersistenceFailureDoesNotCreateTurnOrJob() throws {
        let suiteName = "AgentJobTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let context = ModelContext(spaces.personalContainer)
        let session = ConversationSession()
        context.insert(session)
        let ai = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key"
        )
        ai.configure(
            provider: .openAI,
            baseURL: "https://example.com/v1",
            model: "gpt-4.1-mini"
        )
        let processor = ConversationProcessingService(
            backgroundLease: TestBackgroundExecutionLease()
        )

        XCTAssertFalse(processor.submit(
            text: "",
            attachments: [PendingAttachment(kind: .video)],
            context: ConversationProcessingContext(
                structuredContext: "",
                session: session,
                dataSpace: .personal,
                gyms: [],
                equipment: [],
                ai: ai,
                modelContext: context
            ),
            includeLocation: false,
            locationService: LocationContextService()
        ))
        XCTAssertTrue(try context.fetch(FetchDescriptor<AgentJob>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CoachMessage>()).isEmpty)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: AgentJob.self,
            PersistentAgentEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor
    private func makeJob(
        dataSpace: DataSpace = .personal,
        createdAt: Date = .now
    ) -> AgentJob {
        let turnID = UUID()
        return AgentJob(
            turnID: turnID,
            sessionID: UUID(),
            userMessageID: UUID(),
            dataSpace: dataSpace,
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
private final class TestBackgroundExecutionLease: BackgroundExecutionLease {
    private var expiration: (@MainActor () -> Void)?
    private(set) var isActive = false

    func begin(expiration: @escaping @MainActor () -> Void) {
        self.expiration = expiration
        isActive = true
    }

    func end() {
        isActive = false
    }

    func expire() {
        expiration?()
    }
}
