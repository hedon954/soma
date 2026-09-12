@testable import Soma
import SwiftData
import XCTest

final class AgentUserQuestionsTests: XCTestCase {
    func testQuestionSchemaSupportsTextActionAndCustomInput() throws {
        let arguments = AgentToolArguments(questions: [question()])
        let data = try JSONEncoder().encode(arguments)
        try AgentToolSchemaValidator.validate(data, for: .askUserQuestions, schemaVersion: 1)
        let result = AgentUserQuestionsTool.result(questions: arguments.questions)
        XCTAssertTrue(result.ok, result.message)
        let restored = try XCTUnwrap(AgentUserQuestionRequest.from(result))
        XCTAssertEqual(restored.questions[0].options[1].action?.schemaVersion, 2)
        XCTAssertTrue(restored.historyText.contains("我想先聊聊"))
        XCTAssertFalse(AgentToolName.askUserQuestions.isMutation)
    }

    func testQuestionsRejectAmbiguityAndInvalidOrUnexposedActions() {
        let value = question()
        XCTAssertFalse(AgentUserQuestionsTool.result(questions: [value, value]).ok)
        var invalid = value
        invalid.options[1].action?.argumentsJSON = #"{"weight":"猜一个"}"#
        XCTAssertFalse(AgentUserQuestionsTool.result(questions: [invalid]).ok)
        XCTAssertFalse(AgentUserQuestionsTool.result(questions: [value], allowedNames: ["ask_user_questions"]).ok)
        invalid.options[1].action?.toolName = .askUserQuestions
        XCTAssertFalse(AgentUserQuestionsTool.result(questions: [invalid]).ok)
        invalid = value
        invalid.options[1].action?.schemaVersion = 999
        XCTAssertFalse(AgentUserQuestionsTool.result(questions: [invalid]).ok)
        invalid = value
        invalid.options = []
        invalid.allowsCustomInput = false
        XCTAssertFalse(AgentUserQuestionsTool.result(questions: [invalid]).ok)
        invalid.allowsCustomInput = true
        XCTAssertTrue(AgentUserQuestionsTool.result(questions: [invalid]).ok)
    }

    @MainActor
    func testQuestionEndsModelLoopAndCheckpointResumeDoesNotInvokeModel() async throws {
        let suite = "AgentQuestionsLoop.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = try JSONEncoder().encode(AgentToolArguments(questions: [question()]))
        let transport = try MockAgentStreamTransport(responses: [
            .toolCall(name: "ask_user_questions", argumentsFragments: [XCTUnwrap(String(data: data, encoding: .utf8))])
        ])
        let ai = AIService(defaults: defaults, apiKeyOverride: "fictional-test-key", agentStreamLoader: transport.load)
        ai.configure(provider: .openAI, baseURL: "https://example.invalid/v1", model: "fixture")
        var checkpoint: AgentLoopCheckpoint?
        let first = try await ai.runAgent(
            text: "先问清楚我的需求", images: [], hasVideo: false, context: "虚构测试",
            onCheckpoint: { checkpoint = $0 }
        ) { _ in
            XCTFail("提问不能执行绑定的业务动作")
            return .failure("unexpected")
        }
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertTrue(first.finalAnswer.contains("我想先聊聊"))
        let resumed = try await ai.runAgent(
            text: "先问清楚我的需求", images: [], hasVideo: false, context: "虚构测试", checkpoint: XCTUnwrap(checkpoint)
        ) { _ in
            XCTFail("已完成提问不能重复执行")
            return .failure("unexpected")
        }
        XCTAssertEqual(resumed.finalAnswer, first.finalAnswer)
        XCTAssertEqual(transport.requests.count, 1)
    }

    @MainActor
    func testDeterministicAnswerPersistsUserTextAndRunsWithoutKeyOnlyOnce() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        XCTAssertTrue(try fixture.processor.submitQuestionAnswer(
            from: fixture.message, questionID: "goal", optionID: "save",
            context: fixture.processing, locationService: LocationContextService()
        ))
        XCTAssertThrowsError(try fixture.processor.submitQuestionAnswer(
            from: fixture.message, questionID: "goal", optionID: "save",
            context: fixture.processing, locationService: LocationContextService()
        ))
        for _ in 0 ..< 100 where fixture.processor.isProcessing {
            try await Task.sleep(for: .milliseconds(20))
        }
        let jobs = try fixture.context.fetch(FetchDescriptor<AgentJob>())
        let job = try XCTUnwrap(jobs.first)
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(job.state, .succeeded)
        XCTAssertEqual(job.executionKind, .deterministicQuestion)
        XCTAssertEqual(job.userText, "帮我记录体重 68 千克")
        let records = try fixture.context.fetch(FetchDescriptor<BodyEntry>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.weight, 68)
        let traces = try fixture.context.fetch(FetchDescriptor<AgentTrace>())
        XCTAssertTrue(traces.allSatisfy { $0.model == "deterministic-question-v1" })
        let response = try XCTUnwrap(ConversationTurnPersistence.message(id: XCTUnwrap(job.responseMessageID), in: fixture.context))
        XCTAssertTrue(response.agentTurnItems.contains { $0.kind == .tool && $0.status == .succeeded })
        XCTAssertEqual(response.recordType, .body)
        let reopened = ModelContext(fixture.context.container)
        let restored = try XCTUnwrap(reopened.fetch(FetchDescriptor<AgentJob>()).first)
        XCTAssertEqual(restored.deterministicQuestionAction?.toolName, .createBodyEntry)
    }

    @MainActor
    func testFailedAndCancelledActionRetriesRemainDeterministic() async throws {
        let fixture = try makeFixture(action: .init(toolName: .updateBody, argumentsJSON: #"{"record_id":9876,"weight":68}"#))
        defer { fixture.cleanup() }
        XCTAssertTrue(try fixture.processor.submitQuestionAnswer(
            from: fixture.message, questionID: "goal", optionID: "save",
            context: fixture.processing, locationService: LocationContextService()
        ))
        await waitUntilIdle(fixture.processor)
        let job = try XCTUnwrap(fixture.context.fetch(FetchDescriptor<AgentJob>()).first)
        XCTAssertEqual(job.state, .waitingForUser)
        let user = try XCTUnwrap(ConversationTurnPersistence.message(id: job.userMessageID, in: fixture.context))
        XCTAssertTrue(fixture.processor.retry(userMessage: user, context: fixture.processing))
        await waitUntilIdle(fixture.processor)
        XCTAssertEqual(job.state, .waitingForUser)
        try job.transition(to: .cancelled)
        try fixture.context.save()
        XCTAssertTrue(fixture.processor.retry(userMessage: user, context: fixture.processing))
        await waitUntilIdle(fixture.processor)
        let jobs = try fixture.context.fetch(FetchDescriptor<AgentJob>())
        XCTAssertEqual(jobs.count, 2)
        XCTAssertTrue(jobs.allSatisfy { $0.executionKind == .deterministicQuestion && $0.backend == .local })
        XCTAssertTrue(jobs.allSatisfy { $0.deterministicQuestionAction == job.deterministicQuestionAction })
        let traces = try fixture.context.fetch(FetchDescriptor<AgentTrace>())
        XCTAssertEqual(traces.count, 3)
        XCTAssertTrue(traces.allSatisfy { $0.model == "deterministic-question-v1" && $0.status == .failed })
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<BodyEntry>()).isEmpty)
    }

    @MainActor
    private func waitUntilIdle(_ processor: ConversationProcessingService) async {
        for _ in 0 ..< 100 where processor.isProcessing {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(processor.isProcessing)
    }

    @MainActor
    func testPlainOptionAndCustomInputUseOrdinaryAgentJobs() throws {
        for custom in [false, true] {
            let fixture = try makeFixture()
            defer { fixture.cleanup() }
            XCTAssertTrue(try fixture.processor.submitQuestionAnswer(
                from: fixture.message, questionID: "goal", optionID: custom ? nil : "talk",
                customText: custom ? "我今天只想聊恢复" : nil,
                context: fixture.processing, locationService: LocationContextService()
            ))
            let job = try XCTUnwrap(fixture.context.fetch(FetchDescriptor<AgentJob>()).first)
            XCTAssertEqual(job.executionKind, .react)
            XCTAssertNil(job.deterministicQuestionAction)
            XCTAssertEqual(job.userText, custom ? "我今天只想聊恢复" : "我想先聊聊")
            XCTAssertEqual(job.state, .staged, "没有 Key 的普通文本沿用现有暂存规则")
            XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<BodyEntry>()).isEmpty)
        }
    }

    @MainActor
    func testNewUserTurnHidesLateQuestionsAndPreventsStaleOrCrossSessionSelection() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let reopened = ModelContext(fixture.context.container)
        let restored = try XCTUnwrap(reopened.fetch(FetchDescriptor<CoachMessage>()).first { $0.isFromCoach })
        XCTAssertNoThrow(try ConversationQuestionAnswers.activeRequest(from: restored, sessionID: fixture.session.id, in: reopened))
        XCTAssertThrowsError(try ConversationQuestionAnswers.activeRequest(from: restored, sessionID: UUID(), in: reopened))
        let newer = CoachMessage(sessionID: fixture.session.id, isFromCoach: false, text: "换个话题", turnID: UUID())
        fixture.context.insert(newer)
        fixture.message.date = newer.date.addingTimeInterval(1)
        try fixture.context.save()
        XCTAssertThrowsError(try ConversationQuestionAnswers.activeRequest(from: fixture.message, sessionID: fixture.session.id, in: fixture.context))
        let projection = CoachMessageRenderProjection(
            recentMessages: [fixture.message, newer, fixture.user], messageLimit: 30, agentJobs: []
        )
        XCTAssertNotEqual(projection.latestUserTurnID, fixture.message.turnID)
        XCTAssertNotNil(CoachMessageRenderPayloadCache.payload(for: fixture.message).userQuestions)
        XCTAssertEqual(CoachMessageRenderPayloadCache.payload(for: fixture.message).visibleText, "")
    }

    private func question() -> AgentUserQuestion {
        AgentUserQuestion(id: "goal", question: "接下来想做什么？", options: [
            AgentQuestionOption(id: "talk", text: "我想先聊聊"),
            AgentQuestionOption(id: "save", text: "帮我记录体重 68 千克", action: AgentQuestionAction(
                toolName: .createBodyEntry, argumentsJSON: #"{"weight":68}"#
            ))
        ], allowsCustomInput: true)
    }

    @MainActor
    private func makeFixture(action: AgentQuestionAction? = nil) throws -> Fixture {
        let suite = "AgentQuestionAnswers.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let spaces = DataSpaceController(defaults: defaults, isStoredInMemoryOnly: true)
        let context = ModelContext(spaces.personalContainer)
        let session = ConversationSession()
        let user = CoachMessage(date: .now.addingTimeInterval(-10), sessionID: session.id, isFromCoach: false, text: "虚构测试", turnID: UUID())
        var value = question()
        if let action {
            value.options[1].action = action
        }
        let result = AgentUserQuestionsTool.result(questions: [value])
        let message = CoachMessage(date: .now.addingTimeInterval(-9), sessionID: session.id, isFromCoach: true,
                                   text: result.message, agentStatus: .succeeded, turnID: user.turnID)
        message.applyAgentEvent(.span(AgentTraceSpan(kind: .tool, title: "等待你的回答", status: .succeeded, startedAt: .now, endedAt: .now, output: AgentTraceText.json(result))))
        context.insert(session)
        context.insert(user)
        context.insert(message)
        try context.save()
        let ai = AIService(defaults: defaults, apiKeyOverride: "")
        let processing = ConversationProcessingContext(
            structuredContext: "虚构测试", session: session, dataSpace: .personal,
            gyms: [], equipment: [], ai: ai, modelContext: context
        )
        return Fixture(context: context, session: session, message: message, user: user,
                       processing: processing, processor: ConversationProcessingService(),
                       cleanup: { defaults.removePersistentDomain(forName: suite) })
    }

    @MainActor
    private struct Fixture {
        let context: ModelContext
        let session: ConversationSession
        let message: CoachMessage
        let user: CoachMessage
        let processing: ConversationProcessingContext
        let processor: ConversationProcessingService
        let cleanup: () -> Void
    }
}
