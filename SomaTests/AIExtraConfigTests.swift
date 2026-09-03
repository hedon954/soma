@testable import Soma
import SwiftOpenAI
import XCTest

@MainActor
final class AIExtraConfigTests: XCTestCase {
    func testJSONEditorSmartIndentMatchesNestedObjectStructure() {
        let edit = JSONAutoIndenter.newlineEdit(
            before: "{\n  \"reasoning\": {",
            after: "}"
        )
        XCTAssertEqual(edit.replacement, "\n    \n  ")
        XCTAssertEqual(edit.cursorOffset, 5)
    }

    func testJSONSyntaxTokenizerDistinguishesKeysValuesAndKeywords() {
        let tokens = JSONSyntaxHighlighter.tokens(
            in: #"{"enabled":false,"effort":2}"#
        )
        XCTAssertTrue(tokens.contains { $0.kind == .key })
        XCTAssertTrue(tokens.contains { $0.kind == .keyword })
        XCTAssertTrue(tokens.contains { $0.kind == .number })
        XCTAssertTrue(tokens.contains { $0.kind == .punctuation })
    }

    func testBuiltInThinkingDefaultsMatchProviderProtocols() {
        XCTAssertEqual(
            AIThinkingExtraConfig.defaultObject(
                baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                model: "qwen3.5-plus"
            ) as NSDictionary,
            ["enable_thinking": false] as NSDictionary
        )
        XCTAssertEqual(
            AIThinkingExtraConfig.defaultObject(
                baseURL: "https://openrouter.ai/api/v1",
                model: "openai/gpt-5"
            ) as NSDictionary,
            ["reasoning": ["enabled": false]] as NSDictionary
        )
        XCTAssertEqual(
            AIThinkingExtraConfig.defaultObject(
                baseURL: "https://api.deepseek.com/v1",
                model: "deepseek-reasoner"
            ) as NSDictionary,
            ["thinking": ["type": "disabled"]] as NSDictionary
        )
        XCTAssertTrue(
            AIThinkingExtraConfig.defaultObject(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4.1-mini"
            ).isEmpty
        )
    }

    func testUnknownQwenAndGLMModelsReceiveModelDefaults() {
        XCTAssertEqual(
            AIThinkingExtraConfig.defaultObject(
                baseURL: "https://example.com/v1",
                model: "qwen3-coder"
            ) as NSDictionary,
            ["chat_template_kwargs": ["enable_thinking": false]] as NSDictionary
        )
        XCTAssertEqual(
            AIThinkingExtraConfig.defaultObject(
                baseURL: "https://example.com/v1",
                model: "glm-4.5"
            ) as NSDictionary,
            ["thinking": ["type": "disabled"]] as NSDictionary
        )
    }

    func testValidationRejectsNonObjectsAndReservedTransportKeys() throws {
        XCTAssertThrowsError(try AIExtraConfig.validatedJSON("[]")) { error in
            XCTAssertEqual(error as? AIExtraConfigError, .notObject)
        }
        XCTAssertThrowsError(
            try AIExtraConfig.validatedJSON("{\"messages\": [], \"stream\": false}")
        ) { error in
            XCTAssertEqual(
                error as? AIExtraConfigError,
                .reservedKeys(["messages", "stream"])
            )
        }
    }

    func testEmptyRestoresDefaultWhileExplicitEmptyObjectDisablesIt() throws {
        let baseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        let model = "qwen3.5-plus"
        XCTAssertEqual(
            try AIExtraConfig.liveJSON("", baseURL: baseURL, model: model),
            "{\n  \"enable_thinking\" : false\n}"
        )
        XCTAssertEqual(
            try AIExtraConfig.liveJSON("{}", baseURL: baseURL, model: model),
            "{}"
        )
    }

    func testExtraConfigDeepMergesAndCannotReplaceReservedRequestFields() throws {
        var body: [String: Any] = [
            "model": "qwen3",
            "messages": [["role": "user", "content": "hi"]],
            "stream": true,
            "metadata": ["source": "soma", "stable": true]
        ]
        try AIExtraConfig.merge(
            "{\"metadata\":{\"source\":\"user\",\"trace\":false}}",
            into: &body
        )
        XCTAssertEqual(
            body["metadata"] as? NSDictionary,
            ["source": "user", "stable": true, "trace": false] as NSDictionary
        )
        XCTAssertEqual(body["stream"] as? Bool, true)
    }

    func testSettingsAreScopedByCanonicalEndpoint() throws {
        let suite = "AIExtraConfigTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let ai = AIService(defaults: defaults)
        let baseURL = "https://example.com/v1/"

        try ai.saveExtraConfig("{\"thinking\":{\"type\":\"enabled\"}}", for: baseURL)
        XCTAssertEqual(
            ai.storedExtraConfig(for: "https://example.com/v1"),
            "{\n  \"thinking\" : {\n    \"type\" : \"enabled\"\n  }\n}"
        )
        try ai.saveExtraConfig("", for: baseURL)
        XCTAssertEqual(ai.storedExtraConfig(for: baseURL), "")
    }

    func testProductionChatRequestBodyMergesArbitraryExtraConfigWithoutChangingTextMessages() throws {
        let suite = "AIExtraConfigRequestBodyTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let ai = AIService(defaults: defaults)
        let baseURL = "https://openrouter.ai/api/v1"
        try ai.saveExtraConfig(
            #"{"reasoning":{"enabled":true},"top_k":32}"#,
            for: baseURL
        )
        let parameters = ChatCompletionParameters(
            messages: [
                .init(role: .system, content: .text("系统提示")),
                .init(role: .user, content: .text("普通文本输出"))
            ],
            model: .custom("provider/model"),
            streamOptions: .init(includeUsage: true)
        )

        let body = try ai.openAICompatibleChatRequestBody(
            parameters: parameters,
            videos: [],
            baseURL: baseURL
        )

        XCTAssertEqual(body["top_k"] as? Int, 32)
        XCTAssertEqual(
            body["reasoning"] as? NSDictionary,
            ["enabled": true] as NSDictionary
        )
        XCTAssertEqual(body["stream"] as? Bool, true)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.last?["content"] as? String, "普通文本输出")
    }

    func testProductionRequestCarriesReasoningWithAssistantToolCallContinuation() throws {
        let suite = "AIReasoningContinuationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ai = AIService(defaults: defaults)
        let parameters = ChatCompletionParameters(
            messages: [
                .init(role: .system, content: .text("系统提示")),
                .init(role: .assistant, content: .text("")),
                .init(role: .tool, content: .text("工具结果"), toolCallID: "call_1")
            ],
            model: .custom("deepseek-chat")
        )

        let body = try ai.openAICompatibleChatRequestBody(
            parameters: parameters,
            videos: [],
            baseURL: "https://api.deepseek.com/v1",
            assistantReasoningByMessageIndex: [1: "先判断要调用哪个工具。"]
        )

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[1]["reasoning_content"] as? String, "先判断要调用哪个工具。")
        XCTAssertNil(messages[0]["reasoning_content"])
        XCTAssertNil(messages[2]["reasoning_content"])
    }
}
