@testable import Soma
import XCTest

/// ADR 0046：每个平台都能改写 Base URL，模型是可自由输入的值，
/// 刷新候选不覆盖已填写的模型。
final class LLMConfigurationTests: XCTestCase {
    func testOpenCodeProviderDefaultsAndEndpoint() {
        XCTAssertEqual(AIProvider.openCode.displayName, "opencode")
        XCTAssertEqual(
            AIProvider.openCode.defaultBaseURL,
            "https://opencode.ai/zen/v1"
        )
        XCTAssertEqual(
            AIProvider.openCode.endpoint(
                baseURL: AIProvider.openCode.defaultBaseURL,
                path: "chat/completions"
            )?.absoluteString,
            "https://opencode.ai/zen/v1/chat/completions"
        )
        XCTAssertEqual(
            AIProvider.openCode.endpoint(
                baseURL: "https://opencode.ai/zen/v1/",
                path: "models"
            )?.absoluteString,
            "https://opencode.ai/zen/v1/models"
        )
    }

    func testOpenCodeCapabilityMarksResponsesOnlyModelsUnsupported() {
        XCTAssertEqual(
            ModelCapability.multimodalSupport(
                provider: .openCode,
                model: "gpt-5.6-sol"
            ),
            .unsupported
        )
        XCTAssertEqual(
            ModelCapability.multimodalSupport(
                provider: .openCode,
                model: "gpt-5-codex"
            ),
            .unsupported
        )
        XCTAssertEqual(
            ModelCapability.multimodalSupport(
                provider: .openCode,
                model: "claude-sonnet-4"
            ),
            .supported
        )
        XCTAssertEqual(
            ModelCapability.multimodalSupport(
                provider: .openCode,
                model: "qwen3-coder"
            ),
            .unknown
        )
    }

    @MainActor
    func testEveryProviderKeepsCustomBaseURLPerTier() throws {
        let suiteName = "LLMConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ai = AIService(defaults: defaults)

        for provider in AIProvider.allCases {
            ai.configure(
                tier: .standard,
                provider: provider,
                baseURL: "https://standard.example.com/\(provider.rawValue)",
                model: "standard-model"
            )
            ai.configure(
                tier: .small,
                provider: provider,
                baseURL: "https://small.example.com/\(provider.rawValue)",
                model: "small-model"
            )

            XCTAssertEqual(
                ai.baseURL(for: provider, tier: .standard),
                "https://standard.example.com/\(provider.rawValue)"
            )
            XCTAssertEqual(
                ai.baseURL(for: provider, tier: .small),
                "https://small.example.com/\(provider.rawValue)"
            )
            XCTAssertEqual(ai.model(for: provider, tier: .standard), "standard-model")
            XCTAssertEqual(ai.model(for: provider, tier: .small), "small-model")
        }
    }

    @MainActor
    func testCustomModelSurvivesReconfigurationAndBlankFallsBackToDefault() throws {
        let suiteName = "LLMConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ai = AIService(defaults: defaults)

        ai.configure(
            tier: .standard,
            provider: .openAI,
            baseURL: "  https://api.openai.com/v1  ",
            model: "  my-private-deployment  "
        )
        XCTAssertEqual(ai.model(for: .openAI), "my-private-deployment")
        XCTAssertEqual(ai.baseURL(for: .openAI), "https://api.openai.com/v1")

        // 重复写同一份配置不会把手输模型换成平台默认值。
        ai.configure(
            tier: .standard,
            provider: .openAI,
            baseURL: ai.baseURL(for: .openAI),
            model: ai.model(for: .openAI)
        )
        XCTAssertEqual(ai.model(for: .openAI), "my-private-deployment")

        ai.configure(
            tier: .standard,
            provider: .openAI,
            baseURL: "",
            model: ""
        )
        XCTAssertEqual(ai.model(for: .openAI), AIProvider.openAI.fallbackModel)
        XCTAssertEqual(ai.baseURL(for: .openAI), AIProvider.openAI.defaultBaseURL)
    }

    @MainActor
    func testConfigurationChangeNotificationWakesStagedQueue() throws {
        let suiteName = "LLMConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ai = AIService(defaults: defaults)

        expectation(
            forNotification: .llmConfigurationDidChange,
            object: nil
        )
        ai.notifyConfigurationChanged()
        waitForExpectations(timeout: 1)
    }
}
