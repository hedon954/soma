import Foundation
import Observation
import Security
import SwiftData
import SwiftOpenAI

@MainActor
@Observable
final class AIService {
    @ObservationIgnored
    let defaults: UserDefaults
    @ObservationIgnored
    let apiKeyOverride: String?
    @ObservationIgnored
    var apiKeyCache: [String: String] = [:]
    @ObservationIgnored
    private let requestLoader: AIRequestLoader
    @ObservationIgnored
    let agentStreamLoader: AgentStreamLoader?
    @ObservationIgnored
    let streamDeadlinePolicy: AgentStreamDeadlinePolicy
    @ObservationIgnored
    let agentRetrySleeper: AgentRetrySleeper

    init(
        defaults: UserDefaults = .standard,
        apiKeyOverride: String? = nil,
        requestLoader: @escaping AIRequestLoader = { request in
            try await URLSession.shared.data(for: request)
        },
        agentStreamLoader: AgentStreamLoader? = nil,
        streamDeadlinePolicy: AgentStreamDeadlinePolicy = .init(),
        agentRetrySleeper: @escaping AgentRetrySleeper = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.defaults = defaults
        self.apiKeyOverride = apiKeyOverride
        self.requestLoader = requestLoader
        self.agentStreamLoader = agentStreamLoader
        self.streamDeadlinePolicy = streamDeadlinePolicy
        self.agentRetrySleeper = agentRetrySleeper
    }

    func fetchAvailableModels(
        provider: AIProvider,
        baseURL: String,
        apiKey: String
    ) async throws -> [AIModelInfo] {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            throw AIServiceError.missingAPIKey(provider.displayName)
        }
        guard let url = provider.endpoint(baseURL: baseURL, path: "models") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(normalizedKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await requestLoader(request)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw AIServiceError.remote(serviceErrorMessage(from: data, statusCode: http.statusCode))
        }

        let identifiers = modelIdentifiers(from: data)
        guard !identifiers.isEmpty else { throw AIServiceError.invalidResponse }
        let availableModels = identifiers
            .map {
                AIModelInfo(
                    id: $0.id,
                    status: $0.status,
                    multimodalAssessment: $0.multimodalAssessment
                )
            }
            .filter { model in
                guard let status = model.status?.lowercased() else { return true }
                return !["inactive", "disabled", "unavailable", "offline", "failed"]
                    .contains(where: status.contains)
            }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        guard !availableModels.isEmpty else {
            throw AIServiceError.remote("\(provider.displayName) 当前没有返回可用模型")
        }
        cacheMultimodalAssessments(
            availableModels,
            provider: provider,
            baseURL: baseURL
        )
        return availableModels
    }

    func generateImage(prompt: String) async throws -> Data {
        let provider = provider(for: .standard)
        let model = imageModel(for: provider)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw AIServiceError.imageGenerationUnsupported(provider.displayName)
        }
        let apiKey = apiKey(for: provider, tier: .standard)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey(provider.displayName)
        }
        guard let url = provider.endpoint(
            baseURL: baseURL(for: provider, tier: .standard),
            path: "images/generations"
        ) else {
            throw AIServiceError.invalidURL
        }
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024",
            "quality": "medium",
            "output_format": "jpeg",
            "output_compression": 82
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        let (data, response) = try await requestLoader(request)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            if imageGenerationErrorCode(from: data) == "moderation_blocked" {
                throw AIServiceError.imageGenerationBlocked
            }
            throw AIServiceError.remote(
                serviceErrorMessage(from: data, statusCode: http.statusCode)
            )
        }
        guard let root = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let values = root["data"] as? [[String: Any]],
            let base64 = values.first?["b64_json"] as? String,
            let image = Data(base64Encoded: base64),
            !image.isEmpty
        else {
            throw AIServiceError.invalidResponse
        }
        return image
    }

    func agentErrorDescription(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.displayDescription
        }
        return error.localizedDescription
    }

    private func modelIdentifiers(
        from data: Data
    ) -> [(
        id: String,
        status: String?,
        multimodalAssessment: MultimodalCapabilityAssessment
    )] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var candidates = root["data"] as? [[String: Any]] ?? []
        if candidates.isEmpty {
            candidates = root["models"] as? [[String: Any]] ?? []
        }
        if candidates.isEmpty,
           let output = root["output"] as? [String: Any]
        {
            candidates = output["models"] as? [[String: Any]] ?? []
        }

        var seen = Set<String>()
        return candidates.compactMap { item in
            let identifier = (item["id"] as? String)
                ?? (item["model_name"] as? String)
                ?? (item["name"] as? String)
            guard let identifier, !identifier.isEmpty, seen.insert(identifier).inserted else {
                return nil
            }
            return (
                identifier,
                item["status"] as? String,
                catalogMultimodalAssessment(from: item)
            )
        }
    }

    /// 只接受模型目录响应中的显式能力字段。模型 ID、供应商和营销名称都不是证据。
    private func catalogMultimodalAssessment(
        from item: [String: Any]
    ) -> MultimodalCapabilityAssessment {
        let modalityPaths = [
            ["input_modalities"],
            ["inputModalities"],
            ["architecture", "input_modalities"],
            ["architecture", "inputModalities"],
            ["capabilities", "input_modalities"],
            ["capabilities", "inputModalities"]
        ]
        for path in modalityPaths {
            guard let modalities = stringList(value(at: path, in: item)) else { continue }
            return ModelCapability.assessment(
                inputModalities: modalities,
                source: path.joined(separator: ".")
            )
        }

        let booleanPaths = [
            ["supports_vision"],
            ["supportsVision"],
            ["capabilities", "vision"],
            ["capabilities", "multimodal"],
            ["capabilities", "supports_vision"],
            ["capabilities", "supportsVision"]
        ]
        for path in booleanPaths {
            guard let supported = value(at: path, in: item) as? Bool else { continue }
            return ModelCapability.assessment(
                explicitVisionSupport: supported,
                source: path.joined(separator: ".")
            )
        }
        return .unknown
    }

    private func value(
        at path: [String],
        in item: [String: Any]
    ) -> Any? {
        var current: Any = item
        for component in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[component]
            else {
                return nil
            }
            current = next
        }
        return current
    }

    private func stringList(_ value: Any?) -> [String]? {
        if let values = value as? [String] {
            return values
        }
        guard let value = value as? String else { return nil }
        return value.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func serviceErrorMessage(from data: Data, statusCode: Int) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = root["error"] as? [String: Any],
               let message = error["message"] as? String
            {
                return message
            }
            if let message = root["message"] as? String {
                return message
            }
        }
        if let text = String(data: data, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return String(text.prefix(240))
        }
        return "模型服务错误（\(statusCode)）"
    }

    private func imageGenerationErrorCode(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let error = root["error"] as? [String: Any]
        else {
            return nil
        }
        return error["code"] as? String
    }
}
