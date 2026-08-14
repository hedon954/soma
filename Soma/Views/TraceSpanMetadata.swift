import Foundation

struct TraceSpanMetadata {
    private let values: [String: Any]

    init(_ rawValue: String?) {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            values = [:]
            return
        }
        values = dictionary
    }

    func string(_ key: String) -> String? {
        values[key] as? String
    }

    private func integer(_ key: String) -> Int? {
        if let value = values[key] as? Int {
            return value
        }
        return (values[key] as? NSNumber)?.intValue
    }

    var tokenSummary: String? {
        guard let total = integer("total_tokens") else { return nil }
        let totalText = total.formatted(.number.grouping(.automatic))
        guard let input = integer("prompt_tokens"),
              let output = integer("completion_tokens")
        else {
            return "tokens \(totalText)"
        }
        var summary = "\(totalText) tokens · 入 \(input.formatted()) / 出 \(output.formatted())"
        // 供应商侧前缀缓存的命中量。没有这个字段说明该平台不回传，不等于没命中。
        if let cached = integer("cached_prompt_tokens"), cached > 0 {
            summary += " · 缓存 \(cached.formatted())"
        }
        return summary
    }

    /// 首个增量之前是请求与供应商排队，之后是流式与本机投影：
    /// 两个数字分开才能判断慢在哪一侧。
    var latencySummary: String? {
        var parts: [String] = []
        if let firstDelta = integer("time_to_first_delta_ms") {
            parts.append("首字 \(firstDelta)ms")
        }
        if let projection = integer("projection_ms"), projection > 0 {
            parts.append("投影 \(projection)ms")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
