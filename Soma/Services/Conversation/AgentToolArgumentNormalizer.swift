import Foundation

/// Provider 的 strict tool calling 不是所有兼容服务都可靠执行。这里只依据 App 自己注册的
/// JSON Schema，把无单位的数字字符串收敛为数值；其余内容原样交给严格校验，绝不猜单位或事实。
enum AgentToolArgumentNormalizer {
    static func normalize(
        _ argumentData: Data,
        for name: AgentToolName
    ) throws -> Data {
        let raw = try JSONSerialization.jsonObject(with: argumentData)
        let schema = try AgentToolSchemaValidator.parameterSchema(for: name)
        let normalized = normalize(raw, schema: schema)
        return try JSONSerialization.data(
            withJSONObject: normalized,
            options: [.sortedKeys]
        )
    }

    private static func normalize(_ value: Any, schema: [String: Any]) -> Any {
        let expectedTypes: [String]
        if let type = schema["type"] as? String {
            expectedTypes = [type]
        } else {
            expectedTypes = schema["type"] as? [String] ?? []
        }

        if let text = value as? String {
            if expectedTypes.contains("integer"),
               let number = parsedNumber(text, requiresInteger: true)
            {
                return number
            }
            if expectedTypes.contains("number"),
               let number = parsedNumber(text, requiresInteger: false)
            {
                return number
            }
        }

        if let object = value as? [String: Any], expectedTypes.contains("object") {
            let properties = schema["properties"] as? [String: Any] ?? [:]
            var result = object
            for (key, item) in object {
                guard let child = properties[key] as? [String: Any] else { continue }
                result[key] = normalize(item, schema: child)
            }
            return result
        }

        if let array = value as? [Any], expectedTypes.contains("array"),
           let itemSchema = schema["items"] as? [String: Any]
        {
            return array.map { normalize($0, schema: itemSchema) }
        }
        return value
    }

    private static func parsedNumber(
        _ text: String,
        requiresInteger: Bool
    ) -> NSNumber? {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return nil }

        let value: Double?
        let fraction = compact.split(separator: "/", omittingEmptySubsequences: false)
        if fraction.count == 2,
           let numerator = Double(fraction[0].trimmingCharacters(in: .whitespaces)),
           let denominator = Double(fraction[1].trimmingCharacters(in: .whitespaces)),
           denominator != 0
        {
            value = numerator / denominator
        } else if fraction.count == 1 {
            value = Double(compact)
        } else {
            value = nil
        }

        guard let value, value.isFinite, value >= 0 else { return nil }
        if requiresInteger, value.rounded() != value {
            return nil
        }
        return NSNumber(value: value)
    }
}
