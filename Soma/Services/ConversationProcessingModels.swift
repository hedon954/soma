import Foundation
import SwiftData

struct ConversationProcessingContext {
    var structuredContext: String
    var session: ConversationSession
    var dataSpace: DataSpace
    var gyms: [GymProfile]
    var equipment: [GymEquipment]
    var ai: AIService
    var modelContext: ModelContext
}

enum ConversationMediaPreparationError: LocalizedError {
    case attachmentPersistenceFailed
    case videoFramesUnavailable

    var errorDescription: String? {
        switch self {
        case .attachmentPersistenceFailed:
            "附件未能完整保存到本机，请检查存储空间后重试"
        case .videoFramesUnavailable:
            "视频已保存在本机，但未能提取任何可供模型分析的画面，请换一个可播放的视频后重试"
        }
    }
}

enum ConversationMediaMetrics {
    static func videoBytes(_ attachments: [MediaAttachmentReference]) -> Int {
        attachments.reduce(0) { total, attachment in
            guard attachment.kind == .video,
                  let url = MediaStore.url(at: attachment.path),
                  let attributes = try? FileManager.default.attributesOfItem(
                      atPath: url.path
                  ),
                  let bytes = (attributes[.size] as? NSNumber)?.intValue
            else {
                return total
            }
            return total + bytes
        }
    }
}

extension ConversationProcessingContext {
    func businessDate(for text: String, turnSentAt: Date) -> Date {
        BusinessDateResolver.turnBusinessDate(
            in: text,
            sessionBusinessDate: session.effectiveBusinessDate,
            turnSentAt: turnSentAt,
            timeZone: session.businessTimeZone
        )
    }

    func structuredContext(for businessDate: Date) -> String {
        AgentContextPackBuilder.build(
            gyms: gyms,
            equipment: equipment,
            in: modelContext,
            sessionID: session.id,
            businessDate: businessDate,
            timeZone: session.businessTimeZone
        )
    }
}

struct PreparedConversationMedia {
    var attachments: [MediaAttachmentReference]
    var frames: [Data]
    var videos: [AgentVideoInput] = []
    var imageCount: Int
    var videoCount: Int
    var failedVideoCount: Int = 0
    var mode: AgentMediaMode = .text
    var preparationMilliseconds: Int = 0

    var hasVideo: Bool {
        videoCount > 0
    }

    var primaryKind: MediaKind {
        attachments.first?.kind ?? .none
    }

    var primaryPath: String? {
        attachments.first?.path
    }

    var displaySummary: String {
        let parts = [
            imageCount > 0 ? "\(imageCount) 张图片" : nil,
            videoCount > 0 ? "\(videoCount) 个视频" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "发送了媒体" : "发送了" + parts.joined(separator: "和")
    }
}

enum ConversationResumeProjection {
    static func completedItems(from items: [AgentTurnItem]) -> [AgentTurnItem] {
        items.filter { $0.status == .succeeded && $0.kind != .error }
    }
}

enum ConversationCompactionProjection {
    static func apply(
        _ result: ConversationCompactionResult,
        at date: Date,
        trace: AgentTrace,
        responseMessage: CoachMessage
    ) {
        guard result.didUpdate, let summary = result.summary else { return }
        let span = AgentTraceSpan(
            kind: .output,
            title: "已压缩更早对话",
            status: .succeeded,
            startedAt: date,
            endedAt: date,
            output: summary,
            metadata: AgentTraceText.jsonObject([
                "strategy": result.strategy?.rawValue ?? "unknown"
            ])
        )
        trace.apply(.span(span))
        responseMessage.applyAgentEvent(.span(span))
    }
}
