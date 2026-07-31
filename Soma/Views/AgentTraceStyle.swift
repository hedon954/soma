import SwiftUI

enum TraceStyle {
    static func color(for status: AgentTraceStatus) -> Color {
        switch status {
        case .running: AppTheme.warning
        case .succeeded: AppTheme.tint
        case .failed: .red
        case .cancelled: .secondary
        }
    }

    static func color(for kind: AgentTraceSpanKind) -> Color {
        switch kind {
        case .model: .purple
        case .skill: .blue
        case .tool: AppTheme.tint
        case .output: .cyan
        }
    }

    static func icon(for status: AgentTraceStatus) -> String {
        switch status {
        case .running: "hourglass"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "minus.circle.fill"
        }
    }

    static func icon(for kind: AgentTraceSpanKind) -> String {
        switch kind {
        case .model: "brain.head.profile"
        case .skill: "books.vertical.fill"
        case .tool: "wrench.and.screwdriver.fill"
        case .output: "arrow.turn.down.right"
        }
    }

    static func detailTitle(for status: AgentTraceStatus) -> String {
        switch status {
        case .running: "正在执行"
        case .succeeded: "执行成功"
        case .failed: "执行失败"
        case .cancelled: "执行已取消"
        }
    }

    static func displayTitle(for span: AgentTraceSpan, ordinal: Int) -> String {
        switch span.kind {
        case .model:
            "LLM 推理 #\(ordinal)"
        case .skill:
            "Skill: \(span.title)"
        case .tool:
            "工具: \(span.title)"
        case .output:
            span.title
        }
    }

    static func duration(_ milliseconds: Double) -> String {
        if milliseconds < 1000 {
            return "\(Int(milliseconds.rounded()))ms"
        }
        return "\((milliseconds / 1000).formatted(.number.precision(.fractionLength(2))))s"
    }

    static func relative(_ milliseconds: Double) -> String {
        if milliseconds < 1000 {
            return "+\(Int(milliseconds.rounded()))ms"
        }
        return "+\((milliseconds / 1000).formatted(.number.precision(.fractionLength(1))))s"
    }
}
