@testable import Soma
import XCTest

final class ExerciseImageGenerationTests: XCTestCase {
    @MainActor
    func testUsesDedicatedModelAndBase64Response() async throws {
        let suiteName = "ExerciseImageGenerationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var capturedRequest: URLRequest?
        let expected = Data([1, 2, 3, 4])
        let service = AIService(
            defaults: defaults,
            apiKeyOverride: "test-key"
        ) { request in
            capturedRequest = request
            let data = try JSONSerialization.data(withJSONObject: [
                "data": [["b64_json": expected.base64EncodedString()]]
            ])
            let response = try XCTUnwrap(HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ))
            return (data, response)
        }
        service.configure(
            provider: .openAI,
            baseURL: "https://example.com/v1/chat/completions",
            model: "gpt-5.6"
        )
        service.configureImageModel("gpt-image-2", for: .openAI)

        let result = try await service.generateImage(prompt: "动作示意图")

        XCTAssertEqual(result, expected)
        XCTAssertEqual(
            capturedRequest?.url?.absoluteString,
            "https://example.com/v1/images/generations"
        )
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["model"] as? String, "gpt-image-2")
        XCTAssertEqual(json["size"] as? String, "1024x1024")
        XCTAssertEqual(json["quality"] as? String, "medium")
        XCTAssertEqual(json["output_format"] as? String, "jpeg")
        XCTAssertNil(json["response_format"])
    }
}
