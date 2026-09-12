import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case openAI
    case deepSeek
    case bailian
    case volcano
    case tencent
    case openCode
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
        case .openCode: "opencode"
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
        case .openCode: "https://opencode.ai/zen/v1"
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
        case .openCode: "claude-sonnet-4"
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

enum AIModelTier: String, CaseIterable, Identifiable, Codable, Sendable {
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

struct AIModelRoute: Equatable, Codable, Sendable {
    var tier: AIModelTier
    var provider: AIProvider
    var baseURL: String
    var model: String
    var reason: String
}

struct AgentVideoInput: Equatable, Sendable {
    var data: Data
    var mimeType: String
    var messageIndex: Int?
    var frameFallback: VideoFrameSet?
}

enum AgentMediaMode: String, Codable, Equatable, Sendable {
    case text
    case images
    case keyframes
    case directVideo = "direct_video"
}

struct DirectVideoCapability: Equatable, Sendable {
    static let standard = DirectVideoCapability(maximumRawBytes: 7 * 1024 * 1024, preferredMIMEType: "video/mp4")
    var maximumRawBytes: Int
    var preferredMIMEType: String
}

enum MultimodalSupport: String, Codable, Hashable, Sendable {
    case supported
    case unsupported
    case unknown

    var label: String {
        switch self {
        case .supported: "支持图片输入；完整视频按平台能力处理"
        case .unsupported: "不支持多模态：只能发送文字"
        case .unknown: "多模态能力未知：平台模型目录未提供明确标注"
        }
    }
}

struct MultimodalCapabilityAssessment: Codable, Hashable, Sendable {
    let support: MultimodalSupport
    /// 只记录平台 `/models` 响应中实际出现的字段路径；模型名称永远不是证据。
    let source: String?
    /// 只有平台明确列出 video 输入时才为 true；图片能力不能推导出直传视频能力。
    let directVideoSupport: Bool?

    static let unknown = MultimodalCapabilityAssessment(
        support: .unknown,
        source: nil,
        directVideoSupport: nil
    )

    var sourceLabel: String {
        source.map { "来源：平台模型目录 \($0)" }
            ?? "来源：平台未提供能力信息"
    }
}

struct AIModelInfo: Identifiable, Hashable {
    let id: String
    let status: String?
    let multimodalAssessment: MultimodalCapabilityAssessment

    var multimodalSupport: MultimodalSupport {
        multimodalAssessment.support
    }
}

enum ModelCapability {
    /// 供应商与模型名称不是能力证据。没有平台元数据时统一返回 unknown。
    static func multimodalSupport(
        provider _: AIProvider,
        model _: String
    ) -> MultimodalSupport {
        .unknown
    }

    static func assessment(
        inputModalities: [String],
        source: String
    ) -> MultimodalCapabilityAssessment {
        let normalized = Set(inputModalities.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty })
        guard !normalized.isEmpty else { return .unknown }
        let visual = ["image", "images", "vision", "video"]
        return MultimodalCapabilityAssessment(
            support: normalized.contains(where: visual.contains) ? .supported : .unsupported,
            source: source,
            directVideoSupport: normalized.contains("video")
        )
    }

    static func assessment(
        explicitVisionSupport: Bool,
        source: String
    ) -> MultimodalCapabilityAssessment {
        MultimodalCapabilityAssessment(
            support: explicitVisionSupport ? .supported : .unsupported,
            source: source,
            directVideoSupport: nil
        )
    }

    static func supportsDirectVideo(
        assessment: MultimodalCapabilityAssessment
    ) -> Bool {
        assessment.directVideoSupport == true
    }

    static func directVideoCapability(
        assessment: MultimodalCapabilityAssessment
    ) -> DirectVideoCapability? {
        guard assessment.support != .unsupported, assessment.directVideoSupport != false else { return nil }
        return DirectVideoCapability(
            maximumRawBytes: 7 * 1024 * 1024,
            preferredMIMEType: "video/mp4"
        )
    }
}
