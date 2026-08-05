@testable import Soma
import SwiftData
import SwiftOpenAI
import XCTest

/// ADR 0045：LLM 失效只允许三种处置，暂存队列在恢复后先进先出补偿消费。
final class LLMOutageStagingTests: XCTestCase {
    func testTransportFailuresRetryAsNetwork() {
        XCTAssertEqual(
            LLMOutageClassifier.disposition(for: URLError(.notConnectedToInternet)),
            .retryNetwork
        )
        XCTAssertEqual(
            LLMOutageClassifier.disposition(for: APIError.timeOutError),
            .retryNetwork
        )
        XCTAssertEqual(
            LLMOutageClassifier.disposition(
                for: NSError(domain: NSURLErrorDomain, code: -1009)
            ),
            .retryNetwork
        )
    }

    func testMissingConfigurationAndInvalidEndpointAreStaged() {
        guard case .stage = LLMOutageClassifier.disposition(
            for: AIServiceError.missingAPIKey("OpenAI")
        ) else {
            return XCTFail("缺少 API Key 应该进入暂存")
        }
        XCTAssertTrue(
            LLMOutageClassifier
                .signal(for: AIServiceError.missingAPIKey("OpenAI"))
                .isMissingConfiguration
        )
        guard case .stage = LLMOutageClassifier.disposition(
            for: AIServiceError.invalidURL
        ) else {
            return XCTFail("地址无效应该进入暂存")
        }
    }

    func testRecoverableStatusCodesAreStagedAndRequestErrorsFail() {
        for status in [401, 403, 408, 409, 425, 429, 500, 502, 503] {
            guard case .stage = disposition(forStatus: status) else {
                return XCTFail("\(status) 应该进入暂存")
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

    func testStagingRetryDelayGrowsAndCapsAtFiveMinutes() {
        XCTAssertEqual(LLMOutageClassifier.stagingRetryDelay(attemptCount: 0), 1)
        XCTAssertEqual(LLMOutageClassifier.stagingRetryDelay(attemptCount: 1), 2)
        XCTAssertEqual(LLMOutageClassifier.stagingRetryDelay(attemptCount: 3), 8)
        XCTAssertEqual(
            LLMOutageClassifier.stagingRetryDelay(attemptCount: 40),
            LLMOutageClassifier.maximumStagingRetryDelay
        )
        XCTAssertEqual(LLMOutageClassifier.maximumStagingRetryDelay, 300)
    }

    @MainActor
    func testStagedStateAllowsResumeButNotTerminalRestart() throws {
        let job = makeJob()

        try job.transition(to: .staged)
        XCTAssertTrue(job.state.isRunnable)
        XCTAssertFalse(job.state.isTerminal)
        XCTAssertTrue(job.state.canTransition(to: .running))
        XCTAssertTrue(job.state.canTransition(to: .queued))

        try job.transition(to: .running)
        try job.transition(to: .succeeded)
        XCTAssertFalse(job.state.canTransition(to: .staged))
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
            retryDelay: LLMOutageClassifier.stagingRetryDelay(attemptCount: 40),
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
            3
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<AgentTrace>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutEntry>()).isEmpty)
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
