import Foundation
import SwiftOpenAI

extension AIService {
    func directVideoStream(
        parameters: ChatCompletionParameters,
        videos: [AgentVideoInput],
        provider: AIProvider,
        baseURL: String,
        apiKey: String,
        assistantReasoningByMessageIndex: [Int: String] = [:]
    ) async throws -> AsyncThrowingStream<ChatCompletionChunkObject, Error> {
        guard let url = provider.endpoint(
            baseURL: baseURL,
            path: "chat/completions"
        ) else {
            throw AIServiceError.invalidURL
        }
        let body = try openAICompatibleChatRequestBody(
            parameters: parameters,
            videos: videos,
            baseURL: baseURL,
            assistantReasoningByMessageIndex: assistantReasoningByMessageIndex
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        return AsyncThrowingStream { continuation in
            // AIService 属于 MainActor；网络字节解析不能继承它的执行器。
            // 只捕获不可变请求，终止流时同步取消这个生产任务。
            let task = Task.detached {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AIServiceError.invalidResponse
                    }
                    guard (200 ..< 300).contains(http.statusCode) else {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                            if data.count >= 4096 {
                                break
                            }
                        }
                        throw AIServiceError.remote(
                            Self.directVideoErrorMessage(
                                data: data,
                                statusCode: http.statusCode
                            )
                        )
                    }
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5)
                            .trimmingCharacters(in: .whitespaces)
                        guard payload != "[DONE]" else { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        let normalized = try OpenAICompatibleStreamPayload.normalize(data)
                        try continuation.yield(
                            decoder.decode(
                                ChatCompletionChunkObject.self,
                                from: normalized
                            )
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func openAICompatibleChatRequestBody(
        parameters: ChatCompletionParameters,
        videos: [AgentVideoInput],
        baseURL: String,
        assistantReasoningByMessageIndex: [Int: String] = [:]
    ) throws -> [String: Any] {
        let encoded = try JSONEncoder().encode(parameters)
        guard var body = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw AIServiceError.invalidResponse
        }
        if !videos.isEmpty {
            guard var messages = body["messages"] as? [[String: Any]],
                  let userIndex = messages.lastIndex(where: {
                      $0["role"] as? String == "user"
                  })
            else { throw AIServiceError.invalidResponse }
            var content = messages[userIndex]["content"] as? [[String: Any]]
                ?? [[
                    "type": "text",
                    "text": messages[userIndex]["content"] as? String ?? ""
                ]]
            content.append(contentsOf: videos.map { video in
                [
                    "type": "video_url",
                    "video_url": [
                        "url": "data:\(video.mimeType);base64,\(video.data.base64EncodedString())",
                        "fps": 2
                    ]
                ]
            })
            messages[userIndex]["content"] = content
            body["messages"] = messages
        }
        if !assistantReasoningByMessageIndex.isEmpty,
           var messages = body["messages"] as? [[String: Any]]
        {
            for (index, reasoning) in assistantReasoningByMessageIndex
                where messages.indices.contains(index) && !reasoning.isEmpty
            {
                messages[index]["reasoning_content"] = reasoning
            }
            body["messages"] = messages
        }
        body["stream"] = true
        let requestModel = body["model"] as? String ?? ""
        let extraConfig = effectiveExtraConfig(
            baseURL: baseURL,
            model: requestModel
        )
        try AIExtraConfig.merge(extraConfig, into: &body)
        return body
    }

    private nonisolated static func directVideoErrorMessage(
        data: Data,
        statusCode: Int
    ) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = root["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            return message
        }
        return "模型请求失败（\(statusCode)）"
    }
}

/// OpenAI-compatible vendors do not all use the same delta key for thinking.
/// SwiftOpenAI decodes `reasoning_content`; normalize established aliases first.
enum OpenAICompatibleStreamPayload {
    static func normalize(_ data: Data) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var choices = root["choices"] as? [[String: Any]]
        else {
            return data
        }
        var changed = false
        for index in choices.indices {
            guard var delta = choices[index]["delta"] as? [String: Any],
                  (delta["reasoning_content"] as? String)?.isEmpty != false
            else { continue }
            for alias in ["reasoning", "analysis"] {
                guard let reasoning = delta[alias] as? String, !reasoning.isEmpty else {
                    continue
                }
                delta["reasoning_content"] = reasoning
                choices[index]["delta"] = delta
                changed = true
                break
            }
        }
        guard changed else { return data }
        root["choices"] = choices
        return try JSONSerialization.data(withJSONObject: root)
    }
}
