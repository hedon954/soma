import Foundation

enum AIEndpointIdentity {
    static func key(_ baseURL: String) -> String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        for suffix in ["/chat/completions", "/responses", "/models"]
            where value.lowercased().hasSuffix(suffix)
        {
            value.removeLast(suffix.count)
        }
        return value.lowercased()
    }

    static func lookupKeys(_ baseURL: String) -> [String] {
        let identity = key(baseURL)
        guard !identity.isEmpty else { return [] }
        if identity.hasSuffix("/v1") {
            return [identity, String(identity.dropLast(3))]
        }
        return [identity]
    }
}

enum AIThinkingExtraConfig {
    static func defaultObject(baseURL: String, model: String) -> [String: Any] {
        let endpoint = AIEndpointIdentity.key(baseURL)
        let model = model.lowercased()
        if endpoint.contains("api.openai.com") || endpoint.contains("generativelanguage.googleapis.com") {
            return [:]
        }
        if endpoint.contains("dashscope") || endpoint.contains("bailian")
            || endpoint.contains("aliyun") || endpoint.contains("alibaba")
            || endpoint.contains("siliconflow") || endpoint.contains("idealab")
        {
            return ["enable_thinking": false]
        }
        if endpoint.contains("openrouter") {
            return ["reasoning": ["enabled": false]]
        }
        if endpoint.contains("deepseek") || endpoint.contains("bigmodel")
            || endpoint.contains("zhipu") || endpoint.contains("volces")
            || endpoint.contains("volcengine")
        {
            return ["thinking": ["type": "disabled"]]
        }
        if model.contains("qwen") || model.contains("qwq") {
            return ["chat_template_kwargs": ["enable_thinking": false]]
        }
        if model.contains("glm") || model.contains("chatglm") || model.contains("deepseek") {
            return ["thinking": ["type": "disabled"]]
        }
        return [:]
    }

    static func defaultJSON(baseURL: String, model: String) -> String {
        AIExtraConfig.prettyPrinted(defaultObject(baseURL: baseURL, model: model))
    }

    static func isEnabled(_ raw: String) -> Bool? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let value = object["enable_thinking"] as? Bool {
            return value
        }
        if let thinking = object["thinking"] as? [String: Any],
           let type = thinking["type"] as? String
        {
            return type.lowercased() == "enabled"
        }
        if let reasoning = object["reasoning"] as? [String: Any],
           let enabled = reasoning["enabled"] as? Bool
        {
            return enabled
        }
        if let template = object["chat_template_kwargs"] as? [String: Any],
           let enabled = template["enable_thinking"] as? Bool
        {
            return enabled
        }
        return nil
    }
}

enum AIExtraConfig {
    static let reservedKeys: Set<String> = ["messages", "stream", "stream_options"]

    static func validatedJSON(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let data = trimmed.data(using: .utf8) else {
            throw AIExtraConfigError.invalidJSON
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AIExtraConfigError.invalidJSON
        }
        guard let dictionary = object as? [String: Any] else {
            throw AIExtraConfigError.notObject
        }
        let reserved = dictionary.keys.filter(reservedKeys.contains).sorted()
        guard reserved.isEmpty else {
            throw AIExtraConfigError.reservedKeys(reserved)
        }
        return prettyPrinted(dictionary)
    }

    static func liveJSON(_ raw: String, baseURL: String, model: String) throws -> String {
        let validated = try validatedJSON(raw)
        return validated.isEmpty
            ? AIThinkingExtraConfig.defaultJSON(baseURL: baseURL, model: model)
            : validated
    }

    static func prettyPrinted(_ object: [String: Any]) -> String {
        guard !object.isEmpty else { return "{}" }
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return "{}" }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "{}"
    }

    static func jsonEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty || right.isEmpty {
            return left.isEmpty && right.isEmpty
        }
        guard let leftData = left.data(using: .utf8),
              let rightData = right.data(using: .utf8),
              let leftObject = try? JSONSerialization.jsonObject(with: leftData),
              let rightObject = try? JSONSerialization.jsonObject(with: rightData)
        else { return left == right }
        return NSDictionary(dictionary: ["value": leftObject])
            .isEqual(NSDictionary(dictionary: ["value": rightObject]))
    }

    static func merge(_ raw: String, into body: inout [String: Any]) throws {
        let validated = try validatedJSON(raw)
        guard !validated.isEmpty,
              let data = validated.data(using: .utf8),
              let extra = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        body = deepMerge(base: body, overlay: extra)
    }

    private static func deepMerge(
        base: [String: Any],
        overlay: [String: Any]
    ) -> [String: Any] {
        var result = base
        for (key, value) in overlay where !reservedKeys.contains(key) {
            if let existing = result[key] as? [String: Any],
               let replacement = value as? [String: Any]
            {
                result[key] = deepMerge(base: existing, overlay: replacement)
            } else {
                result[key] = value
            }
        }
        return result
    }
}

enum AIExtraConfigError: LocalizedError, Equatable {
    case invalidJSON
    case notObject
    case reservedKeys([String])

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "Extra Config 不是合法 JSON。"
        case .notObject:
            "Extra Config 必须是 JSON 对象，例如 {\"enable_thinking\": false}。"
        case let .reservedKeys(keys):
            "Extra Config 不能包含 \(keys.joined(separator: "、"))。"
        }
    }
}

extension AIService {
    private var extraConfigByEndpointDefaultsKey: String {
        "ai.extraConfig.byEndpoint"
    }

    func storedExtraConfig(for baseURL: String) -> String {
        let map = defaults.dictionary(forKey: extraConfigByEndpointDefaultsKey)
            as? [String: String] ?? [:]
        for key in AIEndpointIdentity.lookupKeys(baseURL) {
            if let value = map[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty
            {
                return value
            }
        }
        return ""
    }

    func effectiveExtraConfig(baseURL: String, model: String) -> String {
        let stored = storedExtraConfig(for: baseURL)
        return stored.isEmpty
            ? AIThinkingExtraConfig.defaultJSON(baseURL: baseURL, model: model)
            : stored
    }

    func saveExtraConfig(_ raw: String, for baseURL: String) throws {
        let key = AIEndpointIdentity.key(baseURL)
        guard !key.isEmpty else { throw AIServiceError.invalidURL }
        let validated = try AIExtraConfig.validatedJSON(raw)
        var map = defaults.dictionary(forKey: extraConfigByEndpointDefaultsKey)
            as? [String: String] ?? [:]
        if validated.isEmpty {
            map.removeValue(forKey: key)
        } else {
            map[key] = validated
        }
        defaults.set(map, forKey: extraConfigByEndpointDefaultsKey)
        notifyConfigurationChanged()
    }
}
