import Foundation
import SwiftUI

/// 真机性能 harness 的指令适配器保持在独立支持文件中，避免测试基础设施继续扩大
/// Coach 主 View。普通启动不会发送这些通知，因此不改变生产交互路径。
struct CoachPerformanceSessionSelectionModifier: ViewModifier {
    let onSelect: (ConversationSession) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .performanceSelectCoachSession)
        ) { notification in
            guard let session = notification.object as? ConversationSession else { return }
            onSelect(session)
        }
    }
}

struct CoachPerformanceScrollModifier: ViewModifier {
    let proxy: ScrollViewProxy
    let firstMessageID: UUID?

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .performanceScrollCoach)
        ) { notification in
            guard let target = notification.object as? String else { return }
            if target == "top", let firstMessageID {
                proxy.scrollTo(firstMessageID, anchor: .top)
            } else if target == "bottom" {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}

struct CoachMessageTopPagingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.top, for: .alignment)
        } else {
            content
                .defaultScrollAnchor(.top)
        }
    }
}

struct CoachMessageScrollPosition: Equatable {
    let isAtTop: Bool
    let isNearBottom: Bool
}

struct CoachMessageScrollTrackingModifier: ViewModifier {
    let onPositionChange: (CoachMessageScrollPosition) -> Void
    let onUserInteraction: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: CoachMessageScrollPosition.self) { geometry in
                    CoachMessageScrollPosition(
                        isAtTop: geometry.visibleRect.minY <= 24,
                        isNearBottom: geometry.contentSize.height
                            - geometry.visibleRect.maxY <= 80
                    )
                } action: { _, position in
                    onPositionChange(position)
                }
                .onScrollPhaseChange { _, phase in
                    guard phase == .interacting else { return }
                    onUserInteraction()
                }
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in onUserInteraction() }
            )
        }
    }
}

/// iOS 18+ 直接观察“加载更早”哨兵是否真正进入屏幕。分页与渲染缓存都以
/// 用户实际看见的内容为边界，不为尚未打开的 Session 或历史消息预热。
struct CoachOlderMessageVisibilityModifier: ViewModifier {
    let onVisible: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onAppear(perform: onVisible)
                .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                    guard isVisible else { return }
                    onVisible()
                }
        } else {
            content.onAppear(perform: onVisible)
        }
    }
}

struct CoachMessageAutoScrollGate {
    private(set) var lastMessageID: UUID?

    mutating func shouldScroll(to messageID: UUID?) -> Bool {
        guard let messageID, messageID != lastMessageID else { return false }
        lastMessageID = messageID
        return true
    }
}

enum CoachMessageStackPolicy {
    static let eagerUpperBound = CoachMessagePagePolicy.pageSize - 1

    static func usesLazyStack(messageCount: Int) -> Bool {
        messageCount > eagerUpperBound
    }
}

enum CoachMessagePagePolicy {
    static let pageSize = 10

    static func nextLimit(after currentLimit: Int) -> Int {
        max(currentLimit, pageSize) + pageSize
    }
}

/// 单次渲染只构造一份有序消息和 Job 索引。避免同一 `body` 多次反转消息，
/// 以及每个气泡都在线性扫描最近 Job。
struct CoachMessageRenderProjection {
    let messages: [CoachMessage]
    let hasEarlierMessages: Bool
    let latestAssistantMessageID: UUID?
    let stagedTurnIDs: Set<UUID>
    let retryableMessageIDs: Set<UUID>
    let pendingJobCount: Int

    init(
        recentMessages: [CoachMessage],
        messageLimit: Int,
        agentJobs: [AgentJob]
    ) {
        let messages = Array(recentMessages.prefix(messageLimit).reversed())
        self.messages = messages
        hasEarlierMessages = recentMessages.count > messageLimit
        latestAssistantMessageID = ChatRecordEditPolicy
            .latestEditableAssistantMessageID(in: messages)

        var stagedTurnIDs = Set<UUID>()
        var jobByResponseMessageID: [UUID: AgentJob] = [:]
        var pendingJobCount = 0
        for job in agentJobs {
            if job.state == .staged || job.state == .waitingForUser {
                stagedTurnIDs.insert(job.turnID)
            }
            if job.state == .staged
                || job.state == .waitingForUser
                || job.state == .queued
                || job.state == .waitingForNetwork
            {
                pendingJobCount += 1
            }
            if let responseMessageID = job.responseMessageID,
               jobByResponseMessageID[responseMessageID] == nil
            {
                jobByResponseMessageID[responseMessageID] = job
            }
        }
        self.stagedTurnIDs = stagedTurnIDs
        self.pendingJobCount = pendingJobCount
        retryableMessageIDs = ConversationTurnProjection
            .retryableAssistantMessageIDs(
                in: messages,
                jobByResponseMessageID: jobByResponseMessageID
            )
    }
}

/// SwiftData 为 JSON-backed 字段提供的是 `Data`。直接在 `body` 里读取
/// `agentTurnItems`、附件和位置会在每次 Tab 状态变化时重新解码；过程分段还会
/// 再次解析每个 Tool 输出。这里按消息 ID 和原始 Data 做有界缓存，数据一变即失效。
@MainActor
struct CoachMessageRenderPayload {
    let visibleText: String
    let turnItems: [AgentTurnItem]
    let transcriptSegments: [AgentTurnTranscriptSegment]
    let mediaAttachments: [MediaAttachmentReference]
    let location: LocationSnapshot?
    let isAutomaticMediaSummary: Bool
}

@MainActor
enum CoachMessageRenderPayloadCache {
    private struct Entry {
        let text: String
        let isFromCoach: Bool
        let mediaKindRaw: String
        let mediaPath: String?
        let mediaAttachmentsData: Data
        let turnItemsData: Data
        let locationData: Data
        let payload: CoachMessageRenderPayload

        func matches(_ message: CoachMessage) -> Bool {
            text == message.text
                && isFromCoach == message.isFromCoach
                && mediaKindRaw == message.mediaKindRaw
                && mediaPath == message.mediaPath
                && mediaAttachmentsData == message.mediaAttachmentsData
                && turnItemsData == message.agentTurnItemsData
                && locationData == message.locationData
        }
    }

    private static let countLimit = 64
    private static var entries: [UUID: Entry] = [:]
    private static var insertionOrder: [UUID] = []

    static func payload(for message: CoachMessage) -> CoachMessageRenderPayload {
        if let entry = entries[message.id], entry.matches(message) {
            return entry.payload
        }

        let items = message.agentTurnItems
        let attachments = message.mediaAttachments
        let payload = CoachMessageRenderPayload(
            visibleText: message.isFromCoach
                ? AgentVisibleTextSanitizer.sanitize(message.text)
                : message.text,
            turnItems: items,
            transcriptSegments: AgentTurnTranscriptSegments.make(from: items),
            mediaAttachments: attachments,
            location: message.location,
            isAutomaticMediaSummary: automaticMediaSummary(
                text: message.text,
                isFromCoach: message.isFromCoach,
                attachments: attachments
            )
        )
        let entry = Entry(
            text: message.text,
            isFromCoach: message.isFromCoach,
            mediaKindRaw: message.mediaKindRaw,
            mediaPath: message.mediaPath,
            mediaAttachmentsData: message.mediaAttachmentsData,
            turnItemsData: message.agentTurnItemsData,
            locationData: message.locationData,
            payload: payload
        )
        if entries.updateValue(entry, forKey: message.id) == nil {
            insertionOrder.append(message.id)
        }
        while insertionOrder.count > countLimit {
            entries.removeValue(forKey: insertionOrder.removeFirst())
        }
        return payload
    }

    static func removeAll() {
        entries.removeAll(keepingCapacity: false)
        insertionOrder.removeAll(keepingCapacity: false)
    }

    static var cachedCount: Int {
        entries.count
    }

    private static func automaticMediaSummary(
        text: String,
        isFromCoach: Bool,
        attachments: [MediaAttachmentReference]
    ) -> Bool {
        guard !isFromCoach, !attachments.isEmpty else { return false }
        let normalized = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "个", with: "")
        let imageCount = attachments.count { $0.kind == .image }
        let videoCount = attachments.count { $0.kind == .video }
        let parts = [
            imageCount > 0 ? "\(imageCount)张图片" : nil,
            videoCount > 0 ? "\(videoCount)视频" : nil
        ].compactMap { $0 }
        return normalized == "发送了" + parts.joined(separator: "和")
    }
}
