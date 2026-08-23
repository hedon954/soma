import Foundation
import SwiftData

struct AssistantFeedbackSpanSummary: Equatable, Sendable {
    var kind: String
    var title: String
    var status: String
    var durationMilliseconds: Int
    var error: String?
}

/// 用户主动点按某条 AI 回复的反馈入口时生成。这里只携带当前 Turn 的可见内容与
/// 脱敏执行摘要，明确排除 Trace input/output/metadata、上下文快照、位置和媒体数据。
struct AssistantFeedbackContext: Identifiable, Equatable, Sendable {
    var id: UUID {
        messageID
    }

    var messageID: UUID
    var turnID: UUID?
    var messageDate: Date
    var userText: String
    var assistantText: String
    var originalMediaSummary: String
    var assistantStatus: String
    var jobID: UUID?
    var backend: String?
    var jobState: String?
    var submissionAttemptCount: Int?
    var selectedSkillID: String?
    var selectedShortcutID: String?
    var traceID: UUID?
    var provider: String?
    var model: String?
    var traceStatus: String?
    var spans: [AssistantFeedbackSpanSummary]
    var appVersion: String
    var buildNumber: String
    var operatingSystem: String
}

enum AssistantFeedbackContextBuilder {
    @MainActor
    static func make(
        messageID: UUID,
        in modelContext: ModelContext,
        bundle: Bundle = .main,
        operatingSystem: String = ProcessInfo.processInfo.operatingSystemVersionString
    ) -> AssistantFeedbackContext? {
        var messageDescriptor = FetchDescriptor<CoachMessage>(
            predicate: #Predicate { $0.id == messageID }
        )
        messageDescriptor.fetchLimit = 1
        guard let message = try? modelContext.fetch(messageDescriptor).first else {
            return nil
        }

        let userMessage: CoachMessage? = if let turnID = message.turnID {
            {
                var descriptor = FetchDescriptor<CoachMessage>(
                    predicate: #Predicate {
                        !$0.isFromCoach && $0.turnID == turnID
                    },
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
                descriptor.fetchLimit = 1
                return try? modelContext.fetch(descriptor).first
            }()
        } else {
            nil
        }
        var jobDescriptor = FetchDescriptor<AgentJob>(
            predicate: #Predicate { $0.responseMessageID == messageID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        jobDescriptor.fetchLimit = 1
        let job = try? modelContext.fetch(jobDescriptor).first
        let trace: AgentTrace? = if let traceID = message.agentTraceID {
            {
                var descriptor = FetchDescriptor<AgentTrace>(
                    predicate: #Predicate { $0.id == traceID }
                )
                descriptor.fetchLimit = 1
                return try? modelContext.fetch(descriptor).first
            }()
        } else if let turnID = message.turnID {
            {
                var descriptor = FetchDescriptor<AgentTrace>(
                    predicate: #Predicate { $0.turnID == turnID },
                    sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
                )
                descriptor.fetchLimit = 1
                return try? modelContext.fetch(descriptor).first
            }()
        } else {
            nil
        }
        let mediaCounts = Dictionary(
            grouping: userMessage?.mediaAttachments ?? [],
            by: \.kind
        )
        let mediaSummary = [
            mediaCounts[.image].map { "图片 \($0.count)" },
            mediaCounts[.video].map { "视频 \($0.count)" }
        ]
        .compactMap { $0 }
        .joined(separator: "，")

        return AssistantFeedbackContext(
            messageID: message.id,
            turnID: message.turnID,
            messageDate: message.date,
            userText: bounded(userMessage?.text ?? "", maximum: 1200),
            assistantText: bounded(
                AgentVisibleTextSanitizer.sanitize(message.text),
                maximum: 1600
            ),
            originalMediaSummary: mediaSummary.isEmpty ? "无" : mediaSummary,
            assistantStatus: message.agentStatus?.title ?? "未知",
            jobID: job?.id,
            backend: job?.backend.rawValue,
            jobState: job?.state.rawValue,
            submissionAttemptCount: job?.submissionAttemptCount,
            selectedSkillID: job?.selectedSkillID,
            selectedShortcutID: job?.selectedShortcutID,
            traceID: trace?.id,
            provider: trace?.provider,
            model: trace?.model,
            traceStatus: trace?.status.title,
            spans: (trace?.spans ?? []).suffix(20).map { span in
                AssistantFeedbackSpanSummary(
                    kind: span.kind.rawValue,
                    title: bounded(span.title, maximum: 120),
                    status: span.status.rawValue,
                    durationMilliseconds: Int(span.durationMilliseconds),
                    error: span.errorMessage.map { bounded($0, maximum: 240) }
                )
            },
            appVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown",
            buildNumber: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "unknown",
            operatingSystem: operatingSystem
        )
    }

    private static func bounded(_ value: String, maximum: Int) -> String {
        guard value.count > maximum else { return value }
        return String(value.prefix(maximum)) + "…"
    }
}

enum AssistantFeedbackEnvelope {
    static func compose(
        userFeedback: String,
        rating: Int?,
        context: AssistantFeedbackContext
    ) -> String {
        let normalizedFeedback = userFeedback.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let spanLines = context.spans.enumerated().map { index, span in
            let error = span.error.map { " | error=\($0)" } ?? ""
            return "\(index + 1). [\(span.kind)/\(span.status)] \(span.title) | \(span.durationMilliseconds)ms\(error)"
        }
        let sections = [
            "用户反馈：\n\(normalizedFeedback.isEmpty ? "（仅评分或附件）" : normalizedFeedback)",
            "评分：\(rating.map(String.init) ?? "未评分") / 5",
            "对应提问：\n\(context.userText.isEmpty ? "（仅媒体提问）" : context.userText)",
            "对应 AI 回复：\n\(context.assistantText.isEmpty ? "（无可见文字）" : context.assistantText)",
            "原提问媒体：\(context.originalMediaSummary)（不自动附带原文件）",
            [
                "执行摘要：",
                "message_id=\(context.messageID.uuidString.lowercased())",
                "turn_id=\(context.turnID?.uuidString.lowercased() ?? "none")",
                "message_date=\(context.messageDate.formatted(.iso8601))",
                "assistant_status=\(context.assistantStatus)",
                "job_id=\(context.jobID?.uuidString.lowercased() ?? "none")",
                "backend=\(context.backend ?? "unknown")",
                "job_state=\(context.jobState ?? "unknown")",
                "submission_attempts=\(context.submissionAttemptCount.map(String.init) ?? "unknown")",
                "skill=\(context.selectedSkillID ?? "none")",
                "shortcut=\(context.selectedShortcutID ?? "none")",
                "trace_id=\(context.traceID?.uuidString.lowercased() ?? "none")",
                "provider=\(context.provider ?? "unknown")",
                "model=\(context.model ?? "unknown")",
                "trace_status=\(context.traceStatus ?? "unknown")",
                "app=\(context.appVersion) (\(context.buildNumber))",
                "os=\(context.operatingSystem)"
            ].joined(separator: "\n"),
            "脱敏步骤摘要：\n" + (spanLines.isEmpty ? "（无）" : spanLines.joined(separator: "\n"))
        ]
        let joined = DiagnosticsLogStore.redact(
            sections.joined(separator: "\n\n")
        )
        return String(joined.prefix(FeedbackSubmissionPolicy.maximumMessageCharacters))
    }
}
