@testable import Soma
import SwiftData
import SwiftOpenAI
import XCTest

final class LLMKeyAndRoutingTests: XCTestCase {
    @MainActor
    func testStandardAPIKeyIsRequiredWithoutFeatureToggle() throws {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let missingKeyService = AIService(defaults: defaults)
        XCTAssertFalse(missingKeyService.hasRequiredAPIKey)

        let configuredService = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key"
        )
        configuredService.configure(
            provider: .openAI,
            baseURL: "https://example.com/v1",
            model: "gpt-4.1-mini"
        )
        XCTAssertTrue(configuredService.hasRequiredAPIKey)
        XCTAssertNoThrow(try configuredService.resolvedRoute(
            requested: nil,
            text: "你好",
            hasMedia: false,
            hasVideo: false
        ))
    }

    /// ADR 0045：缺少 API Key 不再拒绝发送，而是把回合暂存到 LLM 恢复。

    func testProviderEndpointsUseCompatiblePaths() {
        XCTAssertEqual(
            AIProvider.openAI.endpoint(baseURL: "https://api.openai.com/v1", path: "models")?.absoluteString,
            "https://api.openai.com/v1/models"
        )
        XCTAssertEqual(
            AIProvider.tencent.endpoint(baseURL: "https://tokenhub.tencentmaas.com/v1/", path: "chat/completions")?.absoluteString,
            "https://tokenhub.tencentmaas.com/v1/chat/completions"
        )
        XCTAssertNil(
            AIProvider.other.endpoint(
                baseURL: "",
                path: "chat/completions"
            )
        )
        XCTAssertEqual(
            AIProvider.other.endpoint(
                baseURL: "https://example.com/custom/v1",
                path: "models"
            )?.absoluteString,
            "https://example.com/custom/v1/models"
        )
    }

    func testModelNamesStayUnknownWithoutExplicitCatalogEvidence() {
        XCTAssertEqual(
            ModelCapability.multimodalSupport(provider: .bailian, model: "qwen3.5-plus"),
            .unknown
        )
        XCTAssertEqual(
            ModelCapability.multimodalSupport(provider: .tencent, model: "hy-vision-2.0-instruct"),
            .unknown
        )
        XCTAssertFalse(
            ModelCapability.supportsDirectVideo(
                assessment: .unknown
            )
        )
        XCTAssertTrue(ModelCapability.supportsDirectVideo(
            assessment: ModelCapability.assessment(
                inputModalities: ["text", "video"],
                source: "capabilities.input_modalities"
            )
        ))
    }

    @MainActor
    func testModelRouterUsesOptionalSmallProfileOnlyForSimpleText() throws {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AIService(defaults: defaults, apiKeyOverride: "test-key")
        service.configure(
            tier: .standard,
            provider: .openAI,
            baseURL: "https://standard.example.com/v1",
            model: "gpt-standard"
        )
        service.configure(
            tier: .small,
            provider: .other,
            baseURL: "https://small.example.com/v1",
            model: "small-chat"
        )
        service.setTierEnabled(true, tier: .small)

        let simple = service.route(
            text: "你好",
            hasMedia: false,
            hasVideo: false
        )
        let complex = service.route(
            text: "帮我记录今天的训练",
            hasMedia: false,
            hasVideo: false
        )
        let visual = service.route(
            text: "看看动作",
            hasMedia: true,
            hasVideo: true
        )

        XCTAssertEqual(simple.tier, .small)
        XCTAssertEqual(simple.provider, .other)
        XCTAssertEqual(complex.tier, .standard)
        XCTAssertEqual(visual.tier, .standard)
    }

    @MainActor
    func testAvailableModelsAreFetchedDeduplicatedAndFiltered() async throws {
        let suiteName = "SomaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var capturedRequest: URLRequest?
        let service = AIService(defaults: defaults) { request in
            capturedRequest = request
            let data = try JSONSerialization.data(withJSONObject: [
                "data": [
                    [
                        "id": "text-embedding-3-small",
                        "architecture": ["input_modalities": ["text"]]
                    ],
                    [
                        "id": "gpt-4.1-mini",
                        "status": "active",
                        "input_modalities": ["text", "image", "video"]
                    ],
                    ["id": "retired-model", "status": "inactive"],
                    ["id": "gpt-4.1-mini", "status": "active"]
                ]
            ])
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ))
            return (data, response)
        }

        let models = try await service.fetchAvailableModels(
            provider: .openAI,
            baseURL: "https://example.com/v1/chat/completions",
            apiKey: "test-key"
        )

        XCTAssertEqual(models.map(\.id), ["gpt-4.1-mini", "text-embedding-3-small"])
        XCTAssertEqual(models.first?.multimodalSupport, .supported)
        XCTAssertEqual(models.first?.multimodalAssessment.directVideoSupport, true)
        XCTAssertEqual(models.last?.multimodalSupport, .unsupported)
        XCTAssertEqual(models.first?.multimodalAssessment.source, "input_modalities")
        XCTAssertEqual(
            models.last?.multimodalAssessment.source,
            "architecture.input_modalities"
        )
        XCTAssertEqual(
            service.modelMultimodalAssessment(
                provider: .openAI,
                baseURL: "https://example.com/v1/chat/completions",
                model: "gpt-4.1-mini"
            ).support,
            .supported
        )
        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://example.com/v1/models")
        XCTAssertEqual(
            capturedRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-key"
        )
    }
}

