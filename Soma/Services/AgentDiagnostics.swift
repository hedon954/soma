import Foundation

/// ADR 0083：Agent 运行的关键面包屑统一从这里进入本机诊断日志。只写能解释故障的元数据，
/// 不写工具入参、用户正文与媒体内容。
enum AgentDiagnostics {
    private static let category = "agent"

    /// PRD 033：每次 LLM 调用都记录实际绑定的工具清单，让"模型说自己没有某个工具"
    /// 可以被日志证伪。
    static func modelRequest(
        step: Int,
        provider: String,
        model: String,
        tier: String,
        skillID: String?,
        toolNames: [String],
        messageCount: Int
    ) {
        DiagnosticsLogStore.shared.append(
            category: category,
            message: "LLM 调用",
            fields: [
                "step": "\(step)",
                "provider": provider,
                "model": model,
                "tier": tier,
                "skill_id": skillID ?? "none",
                "message_count": "\(messageCount)",
                "tool_count": "\(toolNames.count)",
                "tools": toolNames.isEmpty
                    ? "none"
                    : toolNames.joined(separator: ",")
            ]
        )
    }

    static func toolFinished(
        name: String,
        step: Int,
        status: String,
        startedAt: Date,
        endedAt: Date,
        deduplicated: Bool,
        detail: String?
    ) {
        var fields = [
            "tool": name,
            "step": "\(step)",
            "status": status,
            "duration_ms": "\(Int((max(0, endedAt.timeIntervalSince(startedAt)) * 1000).rounded()))",
            "deduplicated": "\(deduplicated)"
        ]
        if let detail, !detail.isEmpty {
            fields["detail"] = String(detail.prefix(240))
        }
        DiagnosticsLogStore.shared.append(
            category: category,
            message: "Tool 执行",
            fields: fields
        )
    }

    static func turnFinished(
        sessionID: UUID?,
        turnID: UUID?,
        status: String,
        detail: String?
    ) {
        var fields = [
            "session_id": sessionID?.uuidString ?? "none",
            "turn_id": turnID?.uuidString ?? "none",
            "status": status
        ]
        if let detail, !detail.isEmpty {
            fields["detail"] = String(detail.prefix(240))
        }
        DiagnosticsLogStore.shared.append(
            category: category,
            message: "Turn 结束",
            fields: fields
        )
    }
}

/// ADR 0083：进程生命周期是判断"上次是否异常终止"的基础事实。
enum AppLifecycleDiagnostics {
    private static let category = "lifecycle"

    static func launched(
        version: String,
        build: String,
        previousRunEndedCleanly: Bool
    ) {
        DiagnosticsLogStore.shared.append(
            category: category,
            message: "启动",
            fields: [
                "version": version,
                "build": build,
                "previous_run_clean": "\(previousRunEndedCleanly)"
            ]
        )
    }

    static func phase(_ phase: String) {
        DiagnosticsLogStore.shared.append(
            category: category,
            message: "生命周期",
            fields: ["phase": phase]
        )
    }
}
