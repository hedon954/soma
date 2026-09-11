import Foundation

/// 原始响应只在内存中参与分类；LocalizedError 不回显服务商内容。
struct ModelRequestFailure: LocalizedError {
    let statusCode: Int
    let responseMessage: String

    init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        let bounded = Data(data.prefix(4096))
        if let root = try? JSONSerialization.jsonObject(with: bounded) as? [String: Any] {
            let error = root["error"] as? [String: Any]
            let message = error?["message"] as? String
                ?? root["message"] as? String
                ?? root["error"] as? String ?? ""
            responseMessage = [error?["code"] as? String, message].compactMap { $0 }.joined(separator: " ")
        } else {
            responseMessage = String(data: bounded, encoding: .utf8) ?? ""
        }
    }

    var errorDescription: String? {
        AppErrorMessage.modelMessage(status: statusCode, response: responseMessage)
            ?? AppErrorOperation.model.fallback
    }
}

enum VideoInputRejection {
    static func isExplicit(_ error: Error) -> Bool {
        let signal = LLMOutageClassifier.signal(for: error)
        guard let status = signal.httpStatusCode, [400, 415, 422].contains(status),
              let description = signal.responseDescription?.lowercased() else { return false }
        let mentionsVideo = description.contains("video_url")
            || description.contains("video input") || description.contains("video is not supported")
            || description.contains("video content") || description.contains("不支持视频")
        let rejectsType = [
            "unknown variant", "unsupported", "not support", "doesn't support",
            "unrecognized", "not allowed", "unexpected", "invalid content type", "不支持"
        ].contains { description.contains($0) }
        return mentionsVideo && rejectsType
    }
}
