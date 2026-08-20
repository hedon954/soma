import Foundation

/// ADR 0083：崩溃报告的可读结构。所有字段都在拼装前脱敏，正文由纯函数生成，便于单测。
struct CrashReportEnvironment: Equatable, Sendable {
    var version: String
    var build: String
    var systemName: String
    var systemVersion: String
    var deviceModel: String
    var locale: String
    var thermalState: String
    var availableDiskBytes: Int64?
    var isLowPowerMode: Bool
}

struct CrashReportContext: Equatable, Sendable {
    var sessionID: UUID?
    var turnID: UUID?
    var lastActivity: String?
    var lastHeartbeat: Date?
    /// 崩溃 session 的消息，按时间正序，每条已裁剪长度。
    var sessionMessages: [String]
    /// 最后一次 Agent Trace 的 span 摘要，含工具名、入参与结果。
    var traceSpans: [String]
    var traceSummary: String?
}

struct CrashReportDiagnosis: Equatable, Sendable {
    /// `metrickit` 或 `sentinel`。
    var source: String
    var headline: String
    var terminationReason: String?
    var exceptionType: String?
    var exceptionCode: String?
    var signal: String?
    var callStack: String?
}

enum CrashReportComposer {
    static let maximumBodyCharacters = 60000
    static let maximumCallStackCharacters = 20000
    static let maximumLogCharacters = 20000

    static func subject(for diagnosis: CrashReportDiagnosis) -> String {
        "Soma 崩溃诊断 · \(diagnosis.headline)"
    }

    static func body(
        reportID: UUID,
        createdAt: Date,
        diagnosis: CrashReportDiagnosis,
        environment: CrashReportEnvironment,
        context: CrashReportContext,
        recentLog: String
    ) -> String {
        var sections: [String] = []
        sections.append(
            section("概要", lines: [
                "报告 ID：\(reportID.uuidString)",
                "生成时间：\(format(createdAt))",
                "来源：\(diagnosis.source)",
                "判定：\(diagnosis.headline)",
                "终止原因：\(diagnosis.terminationReason ?? "未提供")",
                "异常类型：\(diagnosis.exceptionType ?? "未提供")",
                "异常码：\(diagnosis.exceptionCode ?? "未提供")",
                "信号：\(diagnosis.signal ?? "未提供")"
            ])
        )
        sections.append(
            section("运行环境", lines: [
                "App 版本：\(environment.version) (\(environment.build))",
                "系统：\(environment.systemName) \(environment.systemVersion)",
                "设备：\(environment.deviceModel)",
                "区域：\(environment.locale)",
                "热状态：\(environment.thermalState)",
                "低电量模式：\(environment.isLowPowerMode ? "开" : "关")",
                "可用磁盘：\(environment.availableDiskBytes.map(formatBytes) ?? "未知")"
            ])
        )
        sections.append(
            section("崩溃上下文", lines: [
                "Session：\(context.sessionID?.uuidString ?? "未知")",
                "Turn：\(context.turnID?.uuidString ?? "未知")",
                "最后活动：\(context.lastActivity ?? "未记录")",
                "最后心跳：\(context.lastHeartbeat.map(format) ?? "未记录")",
                "Trace：\(context.traceSummary ?? "未找到")"
            ])
        )
        if !context.sessionMessages.isEmpty {
            sections.append(
                section("Session 消息", lines: context.sessionMessages)
            )
        }
        if !context.traceSpans.isEmpty {
            sections.append(section("最后一次执行过程", lines: context.traceSpans))
        }
        if let callStack = diagnosis.callStack, !callStack.isEmpty {
            sections.append(
                section(
                    "调用栈",
                    lines: [truncate(callStack, to: maximumCallStackCharacters)]
                )
            )
        }
        let log = truncate(recentLog, to: maximumLogCharacters)
        if !log.isEmpty {
            sections.append(section("最近诊断日志", lines: [log]))
        }
        let body = DiagnosticsLogStore.redact(
            sections.joined(separator: "\n\n")
        )
        return truncate(body, to: maximumBodyCharacters)
    }

    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let keep = max(0, limit - 24)
        return "…（已截断更早内容）\n" + String(text.suffix(keep))
    }

    private static func section(_ title: String, lines: [String]) -> String {
        (["## \(title)"] + lines).joined(separator: "\n")
    }

    private static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        return String(format: "%.1f MB", megabytes)
    }
}
