@testable import Soma
import SwiftOpenAI
import Foundation
import XCTest

final class MockAgentStreamTransport {
    enum Response {
        case toolCall(name: String, argumentsFragments: [String])
        case toolCalls([(name: String, arguments: String)])
        case text([String])
    }

    private var responses: [Response]
    private(set) var requests: [ChatCompletionParameters] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func load(
        _ parameters: ChatCompletionParameters,
        _ provider: AIProvider,
        _ baseURL: String,
        _ apiKey: String
    ) async throws -> AsyncThrowingStream<ChatCompletionChunkObject, Error> {
        requests.append(parameters)
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let response = responses.removeFirst()
        let chunks: [ChatCompletionChunkObject] = switch response {
        case let .toolCall(name, fragments):
            try fragments.enumerated().map { index, fragment in
                try Self.chunk([
                    "id": "chatcmpl_tool",
                    "object": "chat.completion.chunk",
                    "choices": [[
                        "index": 0,
                        "delta": [
                            "tool_calls": [[
                                "index": 0,
                                "id": index == 0 ? "call_1" : NSNull(),
                                "type": "function",
                                "function": [
                                    "name": index == 0 ? name : "",
                                    "arguments": fragment
                                ]
                            ]]
                        ],
                        "finish_reason": index == fragments.count - 1 ? "tool_calls" : NSNull()
                    ]]
                ])
            }
        case let .toolCalls(calls):
            try [Self.chunk([
                "id": "chatcmpl_tools",
                "object": "chat.completion.chunk",
                "choices": [[
                    "index": 0,
                    "delta": [
                        "tool_calls": calls.enumerated().map { index, call in
                            [
                                "index": index,
                                "id": "call_\(index + 1)",
                                "type": "function",
                                "function": [
                                    "name": call.name,
                                    "arguments": call.arguments
                                ]
                            ] as [String: Any]
                        }
                    ],
                    "finish_reason": "tool_calls"
                ]]
            ])]
        case let .text(fragments):
            try fragments.enumerated().map { index, fragment in
                try Self.chunk([
                    "id": "chatcmpl_text",
                    "object": "chat.completion.chunk",
                    "choices": [[
                        "index": 0,
                        "delta": ["content": fragment],
                        "finish_reason": index == fragments.count - 1 ? "stop" : NSNull()
                    ]]
                ])
            }
        }

        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    private static func chunk(_ object: [String: Any]) throws -> ChatCompletionChunkObject {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(ChatCompletionChunkObject.self, from: data)
    }
}
