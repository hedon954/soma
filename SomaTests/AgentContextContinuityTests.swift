@testable import Soma
import SwiftData
import XCTest

@MainActor
final class AgentContextContinuityTests: XCTestCase {
    func testFrozenInputSurvivesNewHistoryAndChangedPersona() throws {
        let suite = "AgentContextContinuityTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        ReActPromptSection.role.save("旧人格", in: defaults)
        let ai = AIService(defaults: defaults, apiKeyOverride: "fixture-key")
        let original = try ai.prepareAgentRun(request(text: "第一轮"))
        var checkpoint = AgentLoopCheckpoint.empty
        checkpoint.initialInput = original.modelInput
        checkpoint.route = original.selectedRoute
        ReActPromptSection.role.save("新人格", in: defaults)
        var resumedRequest = request(text: "不应改写原始输入", checkpoint: checkpoint)
        resumedRequest.history = [AgentConversationExchange(userText: "新增历史", assistantText: "新答案",
                                                            images: [], imageAttachmentCount: 0, videoAttachmentCount: 0)]
        let resumed = try ai.prepareAgentRun(resumedRequest)
        XCTAssertEqual(resumed.modelInput, original.modelInput)
        XCTAssertEqual(resumed.selectedRoute, original.selectedRoute)
        XCTAssertTrue(resumed.modelInput.messages[0].text.contains("旧人格"))
        XCTAssertFalse(resumed.modelInput.messages[0].text.contains("新人格"))
        let fresh = try ai.prepareAgentRun(request(text: "下一轮"))
        XCTAssertTrue(fresh.modelInput.messages[0].text.contains("新人格"))
    }

    func testNextTurnAppendsAfterNativeToolFramesWithoutRewritingPrefix() throws {
        let turnID = UUID()
        let first = try input(turnID: turnID, history: [], text: "[TURN 1] 今天记录训练")
        let frames = [
            first.envelope.messages[1],
            AgentModelMessage(role: .assistant, text: "查询", toolCalls: [
                AgentModelToolCall(id: "call_1", name: "list_workouts", arguments: "{}")
            ]),
            AgentModelMessage(role: .tool, text: "{\"ok\":true}", toolCallID: "call_1"),
            AgentModelMessage(role: .assistant, text: "已查到")
        ]
        let history = AgentConversationExchange(turnID: turnID, canonicalMessages: frames,
                                                userText: "今天记录训练", assistantText: "已查到", images: [],
                                                imageAttachmentCount: 0, videoAttachmentCount: 0)
        let next = try input(turnID: UUID(), history: [history], text: "[TURN 2] 今天呢")
        XCTAssertEqual(Array(next.envelope.messages.dropLast()), [first.envelope.messages[0]] + frames)
        let ai = AIService(apiKeyOverride: "fixture-key")
        let native = ai.chatMessages(from: next)
        let encoded = try JSONEncoder().encode(native)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        XCTAssertEqual(body[3]["tool_call_id"] as? String, "call_1")
        let calls = try XCTUnwrap(body[2]["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(calls.first?["id"] as? String, "call_1")
    }

    func testCardCorrectionInvalidatesSavedFrames() {
        let sessionID = UUID()
        let turnID = UUID()
        let user = CoachMessage(sessionID: sessionID, isFromCoach: false, text: "记录", turnID: turnID)
        let answer = CoachMessage(sessionID: sessionID, isFromCoach: true, text: "已记录",
                                  agentStatus: .succeeded, turnID: turnID)
        let saved = AgentCanonicalTurn(sourceFingerprint: AgentCanonicalTurn.fingerprint(
            user: user.text, assistant: answer.text, correction: nil
        ), messages: [AgentModelMessage(role: .user, text: "旧状态")])
        answer.manualCorrectionSummary = "训练重量已改为 12kg"
        let plan = ConversationContextProjection.make(messages: [user, answer], sessionID: sessionID,
                                                      excludingTurnID: nil, canonicalTurns: [turnID: saved])
        XCTAssertNil(plan.exchanges.first?.canonicalMessages)
        XCTAssertTrue(plan.exchanges.first?.assistantText?.contains("12kg") == true)
    }

    func testHistoricalTimeReachesFinalInput() throws {
        let time = try TrustedTurnContext.make(turnSentAt: Date(timeIntervalSince1970: 1_800_000_000),
                                               attemptStartedAt: Date(timeIntervalSince1970: 1_800_086_400),
                                               timeZone: XCTUnwrap(TimeZone(identifier: "Asia/Shanghai")))
        let exchange = AgentConversationExchange(turnID: UUID(), sentAt: time.turnSentAt, trustedTime: time,
                                                 userText: "今天训练", assistantText: "好", images: [],
                                                 imageAttachmentCount: 0, videoAttachmentCount: 0)
        let prepared = try input(turnID: UUID(), history: [exchange], text: "另一天")
        XCTAssertTrue(prepared.envelope.messages[1].text.contains(time.promptText))
        XCTAssertTrue(prepared.envelope.messages[1].text.contains("仅属于此历史轮次"))
    }

    private func request(text: String, checkpoint: AgentLoopCheckpoint? = nil) -> AgentRunPreparationRequest {
        AgentRunPreparationRequest(text: text, images: [], videos: [], hasVideo: false,
                                   imageAttachmentCount: 0, videoAttachmentCount: 0, history: [], context: "",
                                   requestedRoute: nil, selectedSkillID: nil, selectedShortcutID: nil, checkpoint: checkpoint)
    }

    private func input(turnID: UUID, history: [AgentConversationExchange], text: String) throws -> PreparedAgentModelInput {
        try AgentModelInputBuilder.build(systemPrompt: "固定契约", currentTurnID: turnID, history: history,
                                         userPrompt: text, currentImages: [], currentVideos: [], skills: [], tools: [],
                                         maxSteps: 10, deadlinePolicy: AgentStreamDeadlinePolicy())
    }
}
