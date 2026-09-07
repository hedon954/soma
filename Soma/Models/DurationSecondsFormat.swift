import Foundation

/// 持久化仍是秒；展示和输入按「时分秒」省略为零的单位。
enum DurationSecondsFormat {
    static func display(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        var parts: [String] = []
        if hours > 0 {
            parts.append("\(hours)时")
        }
        if minutes > 0 {
            parts.append("\(minutes)分")
        }
        if remainder > 0 || parts.isEmpty {
            parts.append("\(remainder)秒")
        }
        return parts.joined()
    }

    static func parse(_ text: String) -> Int? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "小时", with: "时")
            .replacingOccurrences(of: "分钟", with: "分")
        guard !normalized.isEmpty else {
            return nil
        }
        if let value = Int(normalized) {
            return value
        }
        var hours = 0
        var minutes = 0
        var seconds = 0
        var rest = normalized
        if let range = rest.range(of: "时") {
            guard let value = Int(rest[..<range.lowerBound]) else {
                return nil
            }
            hours = value
            rest = String(rest[range.upperBound...])
        }
        if let range = rest.range(of: "分") {
            guard let value = Int(rest[..<range.lowerBound]) else {
                return nil
            }
            minutes = value
            rest = String(rest[range.upperBound...])
        }
        if rest.hasSuffix("秒") {
            rest.removeLast()
        }
        if !rest.isEmpty {
            guard let value = Int(rest) else {
                return nil
            }
            seconds = value
        }
        return hours * 3600 + minutes * 60 + seconds
    }
}
