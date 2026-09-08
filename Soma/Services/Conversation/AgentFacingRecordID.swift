import Foundation

/// Agent 上下文与跨轮事实只暴露 Int64 `record_id`，不暴露 SwiftData UUID。
enum AgentFacingRecordID {
    static func promptValue(_ businessID: Int64?) -> String {
        businessID.map(String.init) ?? "待确认"
    }

    static func correctionToken(_ businessID: Int64?) -> String {
        "record_id=\(promptValue(businessID))"
    }

    static func bracket(_ businessID: Int64?, key: String = "record_id") -> String? {
        businessID.map { "[\(key):\($0)]" }
    }

    static func labeled(
        _ businessID: Int64?,
        summary: String,
        key: String = "record_id"
    ) -> String {
        guard let token = bracket(businessID, key: key) else {
            return summary
        }
        return "\(token) \(summary)"
    }

    static func trailing(_ businessID: Int64?, key: String = "record_id") -> String {
        bracket(businessID, key: key).map { " \($0)" } ?? ""
    }

    static func factLine(
        kind: String,
        businessID: Int64?,
        title: String?,
        date: Date
    ) -> String? {
        guard let businessID else { return nil }
        let titlePart = title.map { " title=\($0)" } ?? ""
        return "- write \(kind) record_id=\(businessID)\(titlePart) time=\(date.ISO8601Format())"
    }
}
