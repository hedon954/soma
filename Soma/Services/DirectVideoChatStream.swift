import Foundation
import SwiftOpenAI

extension AIService {
    func directVideoStream(
        parameters: ChatCompletionParameters,
        videos: [AgentVideoInput],
        provider: AIProvider,
        baseURL: String,
        apiKey: String
    ) async throws -> AsyncThrowingStream<ChatCompletionChunkObject, Error> {
        guard let url = provider.endpoint(
            baseURL: baseURL,
            path: "chat/completions"
        ) else {
            throw AIServiceError.invalidURL
        }
        let encoded = try JSONEncoder().encode(parameters)
        guard var body = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              var messages = body["messages"] as? [[String: Any]],
              let userIndex = messages.lastIndex(where: { $0["role"] as? String == "user" })
        else {
            throw AIServiceError.invalidResponse
        }
        var content = messages[userIndex]["content"] as? [[String: Any]]
            ?? [["type": "text", "text": messages[userIndex]["content"] as? String ?? ""]]
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
        body["stream"] = true

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        return AsyncThrowingStream { continuation in
            Task {
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
                            directVideoErrorMessage(
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
                        try continuation.yield(
                            decoder.decode(
                                ChatCompletionChunkObject.self,
                                from: data
                            )
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func directVideoErrorMessage(
        data: Data,
        statusCode: Int
    ) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = root["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            return message
        }
        return "视频请求失败（\(statusCode)）"
    }
}
