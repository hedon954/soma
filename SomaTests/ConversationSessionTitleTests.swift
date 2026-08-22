@testable import Soma
import SwiftOpenAI
import XCTest

final class ConversationSessionTitleTests: XCTestCase {
    func testFallbackTitleIsImmediateNormalizedAndBounded() {
        let sentAt = Date(timeIntervalSince1970: 1_787_342_400)
        let session = ConversationSession(startedAt: sentAt.addingTimeInterval(-60))

        session.recordUserMessage(
            "  请帮我\n分析一下今天的卧推训练动作和肩膀发力是否合理，给出改进建议  ",
            at: sentAt
        )

        XCTAssertEqual(session.title, "请帮我 分析一下今天的卧推训练动作和肩膀发力是否合理，给")
        XCTAssertEqual(session.title.count, 28)
        XCTAssertEqual(session.titleSource, .fallback)
        XCTAssertEqual(session.updatedAt, sentAt)
    }

    func testManualTitleWinsOverLateGeneratedTitleWithoutReorderingSession() {
        let updatedAt = Date(timeIntervalSince1970: 1_787_342_400)
        let session = ConversationSession(
            updatedAt: updatedAt,
            title: "卧推动作分析"
        )

        XCTAssertTrue(session.setManualTitle("  我的\n卧推复盘  "))
        XCTAssertEqual(session.title, "我的 卧推复盘")
        XCTAssertEqual(session.titleSource, .manual)
        XCTAssertEqual(session.updatedAt, updatedAt)

        XCTAssertFalse(session.applyGeneratedTitle("肩部训练建议"))
        XCTAssertEqual(session.title, "我的 卧推复盘")
        XCTAssertEqual(session.updatedAt, updatedAt)
    }

    func testRestoreAutomaticTitleAllowsOneGeneratedReplacement() {
        let updatedAt = Date(timeIntervalSince1970: 1_787_342_400)
        let session = ConversationSession(
            updatedAt: updatedAt,
            title: "自定义标题",
            titleSource: .manual
        )

        session.restoreAutomaticTitle(from: "  帮我分析\n卧推动作  ")

        XCTAssertEqual(session.title, "帮我分析 卧推动作")
        XCTAssertEqual(session.titleSource, .fallback)
        XCTAssertTrue(session.applyGeneratedTitle("卧推动作复盘"))
        XCTAssertEqual(session.titleSource, .generated)
        XCTAssertFalse(session.applyGeneratedTitle("迟到的第二个标题"))
        XCTAssertEqual(session.title, "卧推动作复盘")
        XCTAssertEqual(session.updatedAt, updatedAt)
    }

    func testGeneratedTitleNormalizationRemovesPresentationNoise() {
        XCTAssertEqual(
            ConversationSessionTitleService.normalizeGeneratedTitle(
                " **标题：** “卧推训练复盘。”\n额外解释"
            ),
            "卧推训练复盘"
        )
        XCTAssertNil(ConversationSessionTitleService.normalizeGeneratedTitle(" ```\n``` "))
        XCTAssertEqual(
            ConversationSessionTitleService.normalizeGeneratedTitle(
                "这是一个明显超过二十八个字符的会话标题需要在本机被确定性截断以保护列表布局"
            )?.count,
            28
        )
    }

    @MainActor
    func testTitleGenerationPrefersEnabledSmallModel() async throws {
        let suiteName = "ConversationSessionTitleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let transport = MockAgentStreamTransport(responses: [
            .text(["卧推训练复盘"])
        ])
        let ai = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key",
            agentStreamLoader: transport.load
        )
        ai.configure(
            tier: .small,
            provider: .openAI,
            baseURL: "https://small.example.com/v1",
            model: "small-title-model"
        )
        ai.configure(
            tier: .standard,
            provider: .openAI,
            baseURL: "https://standard.example.com/v1",
            model: "standard-title-model"
        )
        ai.setTierEnabled(true, tier: .small)

        let generated = await ConversationSessionTitleService.generate(
            input: ConversationSessionTitleInput(
                userText: "帮我分析今天的卧推",
                assistantText: "卧推时肩部略微前移，建议收紧肩胛。"
            ),
            ai: ai
        )
        let result = try XCTUnwrap(generated)

        XCTAssertEqual(result.title, "卧推训练复盘")
        XCTAssertEqual(result.tier, .small)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.model, "small-title-model")
    }

    @MainActor
    func testTitleGenerationFallsBackToStandardModel() async throws {
        let suiteName = "ConversationSessionTitleFallback.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let transport = ConversationTitleFallbackTransport()
        let ai = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key",
            agentStreamLoader: transport.load
        )
        ai.configure(
            tier: .small,
            provider: .openAI,
            baseURL: "https://small.example.com/v1",
            model: "small-title-model"
        )
        ai.configure(
            tier: .standard,
            provider: .openAI,
            baseURL: "https://standard.example.com/v1",
            model: "standard-title-model"
        )
        ai.setTierEnabled(true, tier: .small)

        let generated = await ConversationSessionTitleService.generate(
            input: ConversationSessionTitleInput(
                userText: "规划下周训练",
                assistantText: "可以按推、拉、腿安排三次训练。"
            ),
            ai: ai
        )
        let result = try XCTUnwrap(generated)

        XCTAssertEqual(result.title, "下周训练计划")
        XCTAssertEqual(result.tier, .standard)
        XCTAssertEqual(transport.requestedModels, [
            "small-title-model",
            "standard-title-model"
        ])
    }

    func testLegacyArchiveWithoutTitleSourceDecodesAsFallback() throws {
        struct LegacySessionDTO: Encodable {
            var id: UUID
            var startedAt: Date
            var updatedAt: Date
            var title: String
        }
        let legacy = LegacySessionDTO(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_787_342_400),
            updatedAt: Date(timeIntervalSince1970: 1_787_342_460),
            title: "旧会话标题"
        )

        let decoded = try JSONDecoder().decode(
            ConversationSessionDTO.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertNil(decoded.titleSourceRaw)
        XCTAssertEqual(decoded.makeModel().titleSource, .fallback)
    }
}

private final class ConversationTitleFallbackTransport: @unchecked Sendable {
    private(set) var requestedModels: [String] = []

    func load(
        _ parameters: ChatCompletionParameters,
        _: AIProvider,
        _: String,
        _: String
    ) async throws -> AsyncThrowingStream<ChatCompletionChunkObject, Error> {
        let model = parameters.model
        requestedModels.append(model)
        if requestedModels.count == 1 {
            throw URLError(.cannotConnectToHost)
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "chatcmpl_title",
            "object": "chat.completion.chunk",
            "choices": [[
                "index": 0,
                "delta": ["content": "下周训练计划"],
                "finish_reason": "stop"
            ]]
        ])
        let chunk = try JSONDecoder().decode(ChatCompletionChunkObject.self, from: data)
        return AsyncThrowingStream { continuation in
            continuation.yield(chunk)
            continuation.finish()
        }
    }
}
