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
    case attachmentUnavailable
    case historicalAttachmentUnavailable
    case imageLimitExceeded
    case historicalImageLimitExceeded
    case fullVideoUnavailable
    case nativeVideoUnsupported
    case nativeVideoCapabilityUnverified

    var errorDescription: String? {
        switch self {
        case .attachmentPersistenceFailed:
            "附件未能完整保存到本机，请检查存储空间后重试"
        case .attachmentUnavailable:
            "本次发送的图片或视频有一项无法从本机读取。请在待处理列表移除这条任务，再重新选择原件发送。"
        case .historicalAttachmentUnavailable:
            "找不到这次引用的历史图片或视频。请在待处理列表移除这条任务，再重新选择原件发送。"
        case .imageLimitExceeded:
            "本次选中的图片过多。请在待处理列表移除这条任务，再分次发送。"
        case .historicalImageLimitExceeded:
            "这次引用的图片超出了单轮上限。请在待处理列表移除这条任务，再指出要查看的哪一张或分次发送。"
        case .nativeVideoUnsupported:
            "当前模型不支持完整视频分析。视频仍保存在本机，请切换支持视频的模型后重试"
        case .nativeVideoCapabilityUnverified:
            "当前模型目录未确认支持完整视频。视频仍保存在本机，请在「LLM 配置」中选择标明支持视频输入的模型后重试。"
        case .fullVideoUnavailable:
            "视频已保存在本机，但未能准备完整视频。请确认模型支持视频，并尝试体积更小的可播放文件后重试"
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

    @MainActor
    func structuredContext(for businessDate: Date, selectedSkillID: String? = nil) -> String {
        AgentContextPackBuilder.build(
            gyms: gyms,
            equipment: equipment,
            in: modelContext,
            sessionID: session.id,
            businessDate: businessDate,
            timeZone: session.businessTimeZone,
            focus: AgentContextPackFocus(skillID: selectedSkillID)
        )
    }
}

struct PreparedConversationMedia: Sendable {
    var attachments: [MediaAttachmentReference]
    var frames: [Data]
    var videos: [AgentVideoInput] = []
    var imageCount: Int
    var videoCount: Int
    var mode: AgentMediaMode = .text
    var preparationMilliseconds: Int = 0
    var preparationFailure: ConversationMediaPreparationError?

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

/// 长回复不能在每个 UI 节拍重新布局从开头到末尾的整段正文。块边界只是 TextKit
/// 增量存储边界，不会插入字符或可见换行；因此无换行长段也必须保持硬上限。
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
            chunks.append(.init(id: 0, text: ""))
        }
        var remainder = delta[...]
        while !remainder.isEmpty {
            let available = targetCharacterCount - chunks[chunks.count - 1].text.count
            if available == 0 {
                let nextID = (chunks.last?.id ?? -1) + 1
                chunks.append(.init(id: nextID, text: ""))
                continue
            }
            let end = remainder.index(
                remainder.startIndex,
                offsetBy: available,
                limitedBy: remainder.endIndex
            ) ?? remainder.endIndex
            chunks[chunks.count - 1].text += remainder[..<end]
            remainder = remainder[end...]
        }
    }

    mutating func reset() {
        chunks = []
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
        items.filter {
            $0.status == .succeeded
                && $0.kind != .error
                && $0.kind != .activity
        }
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
