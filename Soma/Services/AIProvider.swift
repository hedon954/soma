import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case openAI
    case deepSeek
    case bailian
    case volcano
    case tencent
    case other

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .deepSeek: "DeepSeek"
        case .bailian: "阿里云百炼"
        case .volcano: "火山引擎"
        case .tencent: "腾讯云"
        case .other: "其他"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .deepSeek: "https://api.deepseek.com"
        case .bailian: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .volcano: "https://ark.cn-beijing.volces.com/api/v3"
        case .tencent: "https://tokenhub.tencentmaas.com/v1"
        case .other: ""
        }
    }

    var fallbackModel: String {
        switch self {
        case .openAI: "gpt-4.1-mini"
        case .deepSeek: "deepseek-chat"
        case .bailian: "qwen3.5-plus"
        case .volcano: "doubao-seed-1-6-vision-250815"
        case .tencent: "hy-vision-2.0-instruct"
        case .other: ""
        }
    }

    var keychainAccount: String {
        "ai.apiKey.\(rawValue)"
    }

    var baseURLDefaultsKey: String {
        "ai.baseURL.\(rawValue)"
    }

    var modelDefaultsKey: String {
        "ai.model.\(rawValue)"
    }

    func endpoint(baseURL: String, path: String) -> URL? {
        var root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") {
            root.removeLast()
        }
        for suffix in ["/chat/completions", "/responses", "/models"] where root.hasSuffix(suffix) {
            root.removeLast(suffix.count)
            break
        }
        guard let url = URL(string: "\(root)/\(path)"),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host != nil
        else {
            return nil
        }
        return url
    }
}

enum AIModelTier: String, CaseIterable, Identifiable {
    case small
    case standard

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .small: "小模型"
        case .standard: "标准"
        }
    }
}

struct AIModelRoute: Equatable {
    var tier: AIModelTier
    var provider: AIProvider
    var baseURL: String
    var model: String
    var reason: String
}

struct AgentVideoInput: Equatable {
    var data: Data
    var mimeType: String
}

enum MultimodalSupport: String {
    case supported
    case unsupported
    case unknown

    var label: String {
        switch self {
        case .supported: "支持图片与视频关键帧"
        case .unsupported: "不支持多模态"
        case .unknown: "能力未标注，发送时验证"
        }
    }
}

struct AIModelInfo: Identifiable, Hashable {
    let id: String
    let status: String?
    let multimodalSupport: MultimodalSupport
}

enum ModelCapability {
    static func multimodalSupport(provider: AIProvider, model: String) -> MultimodalSupport {
        let value = model.lowercased()

        if containsAny(value, ["embedding", "rerank", "tts", "speech", "moderation"]) {
            return .unsupported
        }

        switch provider {
        case .deepSeek:
            return .unsupported
        case .openAI:
            if containsAny(value, ["gpt-4o", "gpt-4.1", "gpt-5", "o1", "o3", "o4"]) {
                return .supported
            }
            if containsAny(value, ["whisper", "dall-e", "image-", "audio-"]) {
                return .unsupported
            }
        case .bailian:
            if containsAny(value, ["qwen-vl", "qwen3-vl", "qwen-omni", "qvq", "qwen3.5", "qwen3.6", "qwen3.7"]) {
                return .supported
            }
            if containsAny(value, ["coder", "text-"]) {
                return .unsupported
            }
        case .volcano:
            if containsAny(value, ["vision", "doubao-seed"]) {
                return .supported
            }
            if containsAny(value, ["code", "image-generation", "video-generation"]) {
                return .unsupported
            }
        case .tencent:
            if containsAny(value, ["vision", "vita", "glm-5v"]) {
                return .supported
            }
            if containsAny(value, ["image-generation", "video-generation", "3d"]) {
                return .unsupported
            }
        case .other:
            return .unknown
        }
        return .unknown
    }

    static func supportsDirectVideo(
        provider: AIProvider,
        model: String
    ) -> Bool {
        guard provider == .bailian else { return false }
        let value = model.lowercased()
        return containsAny(
            value,
            [
                "qwen-vl", "qwen3-vl", "qwen-omni", "qwen3.5",
                "qwen3.6", "qwen3.7", "qvq"
            ]
        )
    }

    private static func containsAny(_ value: String, _ candidates: [String]) -> Bool {
        candidates.contains(where: value.contains)
    }
}
