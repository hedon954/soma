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
    let lastMessageID: UUID?

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .performanceScrollCoach)
        ) { notification in
            guard let target = notification.object as? String else { return }
            if target == "top", let firstMessageID {
                proxy.scrollTo(firstMessageID, anchor: .top)
            } else if target == "bottom", let lastMessageID {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(lastMessageID, anchor: .bottom)
                }
            }
        }
    }
}

/// 独立叶子负责观察高频 revision。即使用户把 LazyVStack 的最后一条消息滚出
/// 挂载区，驱动仍在，流式底部跟随不会因为 live row 被回收而永久停止。
/// Tab 隐藏时（`\.coachTabIsActive == false`）完全停止订阅，不为不可见的
/// 画面安排布局或滚动；再次进入时 revision 从 0 跳回当前值，正好补一次滚底。
struct CoachLiveAutoScrollDriver: View {
    @Environment(ConversationProcessingService.self) private var processor
    @Environment(\.coachTabIsActive) private var isTabActive

    let isActive: Bool
    let onRevision: () -> Void

    var body: some View {
        let revision = isActive && isTabActive
            ? processor.liveEventRevision
            : 0
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: revision) { _, newValue in
                guard newValue != 0 else { return }
                onRevision()
            }
    }
}

/// 教练 Tab 激活滚底驱动：整棵教练子树里只有这枚叶子和实时转写观察者读取
/// `\.coachTabIsActive`。切换到教练时回到最新消息，切走时什么都不做。
struct CoachTabActivationDriver: View {
    @Environment(\.coachTabIsActive) private var isTabActive

    let onActivate: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: isTabActive) { _, isActive in
                guard isActive else { return }
                onActivate()
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
    let contentFitsViewport: Bool?
}

enum CoachTailScrollPolicy {
    static func shouldScroll(contentFitsViewport: Bool?) -> Bool {
        contentFitsViewport == false
    }
}

struct CoachMessageContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct CoachMessageViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// iOS 17 缺少 `onScrollGeometryChange`，由两个不持有业务状态的叶子只回报
/// 消息内容与 viewport 高度。把测量隔离在叶子可避免高频消息更新让 Coach 根视图
/// 直接依赖 GeometryReader，也不会创建可滚入的零高度锚点。
struct CoachMessageContentHeightReporter: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: CoachMessageContentHeightPreferenceKey.self,
                value: geometry.size.height
            )
        }
    }
}

struct CoachMessageViewportHeightReporter: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: CoachMessageViewportHeightPreferenceKey.self,
                value: geometry.size.height
            )
        }
    }
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
                            - geometry.visibleRect.maxY <= 80,
                        contentFitsViewport: geometry.contentSize.height
                            <= geometry.containerSize.height + 1
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
        let sessionID: UUID?
        let text: String
        let isFromCoach: Bool
        let mediaKindRaw: String
        let mediaPath: String?
        let mediaAttachmentsData: Data
        let turnItemsData: Data
        let locationData: Data
        let payload: CoachMessageRenderPayload

        var approximateCost: Int {
            text.utf8.count
                + mediaKindRaw.utf8.count
                + (mediaPath?.utf8.count ?? 0)
                + mediaAttachmentsData.count
                + turnItemsData.count
                + locationData.count
        }

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

        AppPerformance.event(.coachRenderCache, detail: "result=rebuild")

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
            sessionID: message.sessionID,
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

    /// 内存压力下只保留当前会话最近的不可变渲染 DTO。Entry 不持有任何
    /// SwiftData `@Model`，业务事实仍以数据库为准，命中时也会核对原始 revision。
    static func retainCurrentSession(
        _ sessionID: UUID?,
        maxCount: Int = 10,
        maxCost: Int = 2 * 1024 * 1024
    ) {
        guard let sessionID else {
            removeAll()
            return
        }
        var retained: [UUID] = []
        var retainedCost = 0
        for messageID in insertionOrder.reversed() {
            guard retained.count < maxCount,
                  let entry = entries[messageID],
                  entry.sessionID == sessionID,
                  retainedCost + entry.approximateCost <= maxCost
            else {
                continue
            }
            retained.append(messageID)
            retainedCost += entry.approximateCost
        }
        let retainedSet = Set(retained)
        entries = entries.filter { retainedSet.contains($0.key) }
        insertionOrder = retained.reversed()
        AppPerformance.event(
            .coachRenderCache,
            detail: "result=retained,count=\(retained.count),cost=\(retainedCost)"
        )
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
