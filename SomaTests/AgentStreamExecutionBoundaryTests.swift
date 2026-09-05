@testable import Soma
import SwiftOpenAI
import XCTest

final class AgentStreamExecutionBoundaryTests: XCTestCase {
    func testRawChunksNeverRequireTheMainThreadBeforeOrAfterFirstDelta() async throws {
        let chunk = try makeChunk(["content": "虚构增量"])
        for enforceFirstDelta in [true, false] {
            let stream = AsyncThrowingStream<ChatCompletionChunkObject, Error> { continuation in
                for _ in 0 ..< 3 {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
            var processed = 0
            try await AgentStreamDeadline.consume(
                stream: stream,
                mode: .text,
                policy: AgentStreamDeadlinePolicy(),
                enforceFirstDelta: enforceFirstDelta
            ) { _ in
                XCTAssertFalse(Thread.isMainThread, "原始 chunk 处理不能逐 token 占用 UI 执行器")
                processed += 1
                return true
            }
            XCTAssertEqual(processed, 3)
        }
    }

    func testEmptyCanonicalReasoningDoesNotHideVendorAlias() throws {
        for canonical in [NSNull(), ""] as [Any] {
            for alias in ["reasoning", "analysis"] {
                let chunk = try makeChunk([
                    "reasoning_content": canonical,
                    alias: "仅属于思考卡的虚构内容",
                    "content": "真正的回答"
                ])
                XCTAssertEqual(chunk.choices?.first?.delta?.reasoningContent, "仅属于思考卡的虚构内容")
                XCTAssertEqual(chunk.choices?.first?.delta?.content, "真正的回答")
            }
        }
    }

    private func makeChunk(_ delta: [String: Any]) throws -> ChatCompletionChunkObject {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "fictional-boundary-test", "object": "chat.completion.chunk",
            "choices": [["index": 0, "delta": delta]]
        ])
        return try JSONDecoder().decode(
            ChatCompletionChunkObject.self,
            from: OpenAICompatibleStreamPayload.normalize(data)
        )
    }
}
