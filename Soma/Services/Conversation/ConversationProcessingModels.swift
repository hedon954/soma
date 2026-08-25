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

struct PreparedConversationMedia: Sendable {
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

/// 流式文字在段落完成前只存在于内存，不反复改写 SwiftData 模型。
/// `itemID` 保留 ReAct 文本卡顺序；完成、失败或取消时再一次性落盘。
struct LiveAgentTextChunk: Equatable, Identifiable, Sendable {
    let id: Int
    var text: String
}

/// 长回复不能在每个 UI 节拍重新布局从开头到末尾的整段 `Text`。这个缓冲区只在
/// 换行边界冻结已经完成的块；没有换行的单段文字保持原样，避免人为插入可见断行。
struct LiveAgentTextBuffer: Equatable, Sendable {
    /// 可变尾块越长，5 Hz 流式更新时 CoreText 需要重复断行的正文越多。
    /// 约 256 个中文字符能覆盖多行连续内容，同时把每次重排限制在一个小尾块内。
    static let defaultTargetCharacterCount = 256

    let targetCharacterCount: Int
    private(set) var chunks: [LiveAgentTextChunk] = []

    /// 只在流式完成、失败或测试断言时合并一次；渲染路径只消费 `chunks`。
    var text: String {
        chunks.map(\.text).joined()
    }

    init(targetCharacterCount: Int = defaultTargetCharacterCount) {
        self.targetCharacterCount = max(32, targetCharacterCount)
    }

    mutating func append(_ delta: String) {
        guard !delta.isEmpty else { return }
        if chunks.isEmpty {
            chunks.append(.init(id: 0, text: delta))
        } else {
            chunks[chunks.count - 1].text += delta
        }
        guard delta.contains("\n") else { return }
        freezeCompletedLinesIfNeeded()
    }

    mutating func reset() {
        chunks = []
    }

    private mutating func freezeCompletedLinesIfNeeded() {
        while let tail = chunks.last,
              tail.text.count >= targetCharacterCount,
              let lineEnd = completedLineEnd(in: tail.text)
        {
            let remainderStart = tail.text.index(after: lineEnd)
            let frozenText = String(tail.text[..<remainderStart])
            let remainder = String(tail.text[remainderStart...])
            chunks[chunks.count - 1].text = frozenText
            guard !remainder.isEmpty else {
                chunks.append(.init(id: tail.id + 1, text: ""))
                break
            }
            chunks.append(.init(id: tail.id + 1, text: remainder))
        }
    }

    private func completedLineEnd(in tail: String) -> String.Index? {
        let target = tail.index(
            tail.startIndex,
            offsetBy: targetCharacterCount,
            limitedBy: tail.endIndex
        ) ?? tail.endIndex
        if let lineEnd = tail[..<target].lastIndex(of: "\n") {
            return lineEnd
        }
        return tail[target...].firstIndex(of: "\n")
    }
}

/// UI 只需要稳定 identity 与分块，不携带会随每个 delta 增长的完整字符串。
struct LiveAgentTextRenderSnapshot: Equatable, Sendable {
    var itemID: UUID
    var chunks: [LiveAgentTextChunk]
}

struct LiveAgentTextSnapshot: Equatable, Sendable {
    var itemID: UUID
    var text: String
    var chunks: [LiveAgentTextChunk]

    init(itemID: UUID, text: String) {
        var buffer = LiveAgentTextBuffer()
        buffer.append(text)
        self.init(itemID: itemID, text: text, chunks: buffer.chunks)
    }

    init(itemID: UUID, text: String, chunks: [LiveAgentTextChunk]) {
        self.itemID = itemID
        self.text = text
        self.chunks = chunks
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
