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
        XCTAssertFalse(processor.submit(
            text: "重复发送",
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
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<AgentJob>()).count,
            1
        )
        lease.expire()

        for _ in 0 ..< 100 where processor.isProcessing {
            try await Task.sleep(for: .milliseconds(20))
        }

        let job = try XCTUnwrap(context.fetch(FetchDescriptor<AgentJob>()).first)
        XCTAssertEqual(job.state, .waitingForForeground)
        XCTAssertFalse(job.state.isTerminal)
        XCTAssertTrue(
            AgentJobStore.events(for: job.id, in: context)
                .contains { $0.kind == .waitingForForeground }
        )
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
