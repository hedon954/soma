import SwiftData
import SwiftUI

struct AgentTurnTranscript: View, Equatable {
    let items: [AgentTurnItem]
    var preparedSegments: [AgentTurnTranscriptSegment]?
    let isLive: Bool
    var sourceMessage: CoachMessage?
    var isEditable = false
    var canRetry = false
    var allowsDeferredLoad = false
    var onRetry: () -> Void = {}

    static func == (lhs: AgentTurnTranscript, rhs: AgentTurnTranscript) -> Bool {
        lhs.items == rhs.items
            && lhs.preparedSegments == rhs.preparedSegments
            && lhs.isLive == rhs.isLive
            && lhs.sourceMessage === rhs.sourceMessage
            && lhs.isEditable == rhs.isEditable
            && lhs.canRetry == rhs.canRetry
            && lhs.allowsDeferredLoad == rhs.allowsDeferredLoad
    }

    private var visibleItems: [AgentTurnItem] {
        AgentTurnVisibleItems.make(from: items)
    }

    private var segments: [AgentTurnTranscriptSegment] {
        preparedSegments ?? AgentTurnTranscriptSegments.make(from: items)
    }

    /// ADR 0014 / ADR 0077 / ADR 0085：按 Item 顺序渲染全部 Event Card，不按 kind 重排。
    /// 连续 Skill/Tool 收成一条可展开过程；失败卡单独露出。写入产生的原位卡紧跟产生它的那一步。
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                switch segment {
                case let .process(_, processItems):
                    if processItems.count > 1 {
                        AgentProcessGroupCard(items: processItems)
                    } else if let item = processItems.first {
                        AgentTurnItemCard(item: item)
                    }
                case let .item(item):
                    AgentTurnItemCard(
                        item: item,
                        canRetry: canRetry && item.kind == .error,
                        onRetry: onRetry
                    )
                case let .record(reference):
                    ChatRecordEditorCard(
                        reference: reference,
                        sourceMessage: sourceMessage,
                        isEditable: isEditable,
                        allowsDeferredLoad: allowsDeferredLoad
                    )
                }
            }

            if isLive, !visibleItems.contains(where: { $0.status == .running }) {
                AgentTurnWaitingCard(message: "已收到，正在准备处理…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 实时正文直接消费稳定分块，不再先构造一个携带完整增长字符串的临时
/// `AgentTurnItem`。这样每个 UI tick 只更新尾块，避免反复清洗和扫描全文。
struct LiveAgentTurnTranscriptContent: View {
    let persistedItems: [AgentTurnItem]
    let preparedSegments: [AgentTurnTranscriptSegment]
    let persistedItemsWithoutActivity: [AgentTurnItem]
    let preparedSegmentsWithoutActivity: [AgentTurnTranscriptSegment]
    let liveReasoning: LiveAgentTextRenderSnapshot?
    let liveText: LiveAgentTextRenderSnapshot?
    let sourceMessage: CoachMessage
    let isEditable: Bool
    let canRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let stableItems = liveReasoning == nil
                ? persistedItems
                : persistedItemsWithoutActivity
            let stableSegments = liveReasoning == nil
                ? preparedSegments
                : preparedSegmentsWithoutActivity
            if !stableItems.isEmpty {
                AgentTurnTranscript(
                    items: stableItems,
                    preparedSegments: stableSegments,
                    isLive: false,
                    sourceMessage: sourceMessage,
                    isEditable: isEditable,
                    canRetry: canRetry,
                    allowsDeferredLoad: true,
                    onRetry: onRetry
                )
                .equatable()
            }

            if let liveReasoning,
               !liveReasoning.chunks.isEmpty,
               !stableItems.contains(where: { $0.id == liveReasoning.itemID })
            {
                LiveAgentReasoningCard(
                    streamID: liveReasoning.itemID,
                    chunks: liveReasoning.chunks
                )
            }

            if let liveText,
               !liveText.chunks.isEmpty,
               !stableItems.contains(where: { $0.id == liveText.itemID })
            {
                StreamingAgentTextView(
                    streamID: liveText.itemID,
                    chunks: liveText.chunks
                )
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
                .accessibilityIdentifier("coach-live-agent-text")
                .accessibilityLabel("Soma 正在回复")
                if AppTestRuntime.isRunning {
                    Text("流式回复底部")
                        .font(.system(size: 1))
                        .opacity(0.01)
                        .frame(height: 2)
                        .accessibilityIdentifier("coach-live-agent-bottom")
                }
            } else if liveReasoning == nil,
                      !stableItems.contains(where: { $0.status == .running })
            {
                AgentTurnWaitingCard(message: "已收到，正在准备处理…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 只有这一层读取高频流式 revision。稳定消息、列表投影、输入区和页面 toolbar
/// 都不会因为正文每批增量而重新求值；Tab 隐藏时连这一层也停止观察。
struct CoachLiveAgentTurnTranscript: View {
    let persistedItems: [AgentTurnItem]
    let preparedSegments: [AgentTurnTranscriptSegment]
    let persistedItemsWithoutActivity: [AgentTurnItem]
    let preparedSegmentsWithoutActivity: [AgentTurnTranscriptSegment]
    let sourceMessage: CoachMessage
    let isEditable: Bool
    let canRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        CoachLiveTextObserver { liveReasoning, liveText in
            LiveAgentTurnTranscriptContent(
                persistedItems: persistedItems,
                preparedSegments: preparedSegments,
                persistedItemsWithoutActivity: persistedItemsWithoutActivity,
                preparedSegmentsWithoutActivity: preparedSegmentsWithoutActivity,
                liveReasoning: liveReasoning,
                liveText: liveText,
                sourceMessage: sourceMessage,
                isEditable: isEditable,
                canRetry: canRetry,
                onRetry: onRetry
            )
        }
    }
}

/// 把 Observation 依赖和滚动副作用一起限制在实时回复叶子。Tab 激活态直接读
/// `\.coachTabIsActive` 环境值，不经父链入参传递；隐藏 Tab 不读取 revision，
/// 再次进入时直接取得内存中的最新 snapshot，只补一次当前画面。
private struct CoachLiveTextObserver<Content: View>: View {
    @Environment(ConversationProcessingService.self) private var processor
    @Environment(\.coachTabIsActive) private var observesLiveText

    @ViewBuilder let content: (
        LiveAgentTextRenderSnapshot?,
        LiveAgentTextRenderSnapshot?
    ) -> Content

    var body: some View {
        let snapshots = liveSnapshots
        content(snapshots.reasoning, snapshots.text)
    }

    private var liveSnapshots: (
        reasoning: LiveAgentTextRenderSnapshot?,
        text: LiveAgentTextRenderSnapshot?
    ) {
        guard observesLiveText else { return (nil, nil) }
        _ = processor.liveEventRevision
        return (
            processor.liveReasoningRenderSnapshot,
            processor.liveAssistantRenderSnapshot
        )
    }
}

private struct AgentProcessGroupCard: View {
    let items: [AgentTurnItem]
    @State private var isExpanded = false

    private var isRunning: Bool {
        items.contains { $0.status == .running }
    }

    private var hasFailure: Bool {
        items.contains { $0.status == .failed || $0.status == .cancelled }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    groupStatusIcon
                        .frame(width: 22, height: 22)

                    Text(AgentTurnTranscriptSegments.processSummary(for: items))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.tint)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("执行过程，\(AgentTurnTranscriptSegments.processSummary(for: items))")
            .accessibilityValue(isExpanded ? "已展开" : "已收起")
            .accessibilityHint(isExpanded ? "隐藏逐步结果" : "显示逐步结果")

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        Divider()
                            .padding(.vertical, 6)
                        AgentTurnItemCard(item: item, showsChrome: false)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            AppTheme.insetBackground,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.softTint, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var groupStatusIcon: some View {
        if isRunning {
            ProgressView()
                .controlSize(.small)
                .tint(AppTheme.tint)
        } else if hasFailure {
            Image(systemName: "xmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(AppTheme.success)
        }
    }
}

private struct AgentTurnItemCard: View {
    let item: AgentTurnItem
    var showsChrome = true
    var canRetry = false
    var onRetry: () -> Void = {}
    @State private var isExpanded = false

    var body: some View {
        switch item.kind {
        case .activity:
            AgentTurnWaitingCard(message: item.title)
        case .text:
            textCard
        case .reasoning:
            reasoningCard
        case .skill, .tool:
            operationCard
        case .error:
            errorCard
        }
    }

    private var reasoningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                guard item.status != .running else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(AppTheme.trendAccent)
                        .frame(width: 22, height: 22)
                    Text(item.status == .running ? "正在思考…" : "思考过程")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if item.status != .running {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.trendAccent)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.status == .running ? "正在思考" : "思考过程")
            .accessibilityValue(item.status == .running || isExpanded ? "已展开" : "已收起")

            if item.status == .running || isExpanded {
                Text(item.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            AppTheme.insetBackground,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.trendAccent.opacity(0.15), lineWidth: 1)
        }
        .accessibilityIdentifier("agent-reasoning-\(item.status.rawValue)")
    }

    private var textCard: some View {
        let text = AgentVisibleTextSanitizer.sanitize(item.text)
        return Group {
            if item.status == .running {
                Text(text)
                    .font(.subheadline.weight(.light))
                    .lineSpacing(4)
                    .foregroundStyle(.primary)
            } else {
                CoachResponseView(text)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .accessibilityLabel(item.status == .running ? "Soma 正在回复" : text)
    }

    private var operationCard: some View {
        let expandable = toolPresentation?.disclosureLabel != nil
        return VStack(alignment: .leading, spacing: 8) {
            if expandable {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    processHeader(expandable: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(processAccessibilityLabel)
                .accessibilityValue(isExpanded ? "已展开" : "已收起")
                .accessibilityHint(isExpanded ? "隐藏完整结果" : "显示完整结果")
            } else {
                processHeader(expandable: false)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(processAccessibilityLabel)
            }

            if isExpanded, let toolPresentation, !toolPresentation.details.isEmpty {
                AgentOperationResult(
                    presentation: toolPresentation,
                    tint: kindColor
                )
            }
        }
        .padding(.horizontal, showsChrome ? 12 : 0)
        .padding(.vertical, showsChrome ? 8 : 2)
        .background {
            if showsChrome {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.insetBackground)
            }
        }
        .overlay {
            if showsChrome {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(kindColor.opacity(0.12), lineWidth: 1)
            }
        }
        .accessibilityIdentifier("agent-operation-\(item.phase.rawValue)")
        .accessibilityElement(children: .contain)
    }

    private func processHeader(expandable: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            statusIcon
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if showsCompactSubtitle, let subtitle = compactSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(item.status == .failed ? .red : .secondary)
                        .lineLimit(
                            item.status == .failed || item.status == .cancelled ? nil : 1
                        )
                }
            }

            Spacer(minLength: 8)

            if expandable {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(kindColor)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        .contentShape(Rectangle())
    }

    private var errorCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(AppTheme.vitalAccent)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? "执行失败" : item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.vitalAccent)
                Text(item.errorMessage ?? item.text)
                    .font(.caption)
                    .foregroundStyle(AppTheme.vitalAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if canRetry {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.vitalAccent)
                        .frame(
                            width: AppTheme.minimumTapTarget,
                            height: AppTheme.minimumTapTarget
                        )
                        .background(AppTheme.vitalSoftTint, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重试这条回复")
                .accessibilityHint("复用原始文字、媒体和发送时的位置再次处理")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            AppTheme.vitalSoftTint,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(kindColor)
        case .succeeded:
            Image(systemName: item.kind == .skill ? "sparkles" : "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(item.kind == .skill ? AppTheme.trendAccent : AppTheme.success)
        case .failed, .cancelled:
            Image(systemName: "xmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
        }
    }

    private var kindColor: Color {
        switch item.status {
        case .failed, .cancelled:
            .red
        case .running, .succeeded:
            item.kind == .skill ? AppTheme.trendAccent : AppTheme.trainingAccent
        }
    }

    private var toolPresentation: AgentToolResultPresentation? {
        guard item.kind == .tool, item.status == .succeeded else { return nil }
        return AgentToolResultPresentation.make(for: item)
    }

    private var compactSubtitle: String? {
        if let error = item.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty
        {
            return error
        }
        if let summary = toolPresentation?.summary, !summary.isEmpty {
            return summary
        }
        switch item.phase {
        case .queued:
            return "等待执行"
        case .modelRunning:
            return "正在处理请求"
        case .preparing:
            return item.kind == .skill ? "准备加载" : "准备执行"
        case .running:
            return item.kind == .skill ? "正在加载" : "正在执行"
        case .waitingForDevice:
            return "等待在本机执行"
        case .cancelled:
            return "已取消"
        case .failed:
            return "未完成"
        case .completed:
            return "已完成"
        }
    }

    /// 展开后完整结果已可见，避免状态行再重复第一行摘要。
    private var showsCompactSubtitle: Bool {
        !(isExpanded && toolPresentation?.disclosureLabel != nil)
    }

    private var processAccessibilityLabel: String {
        compactSubtitle.map { "\(item.title)，\($0)" } ?? item.title
    }
}

struct StreamingAgentTextView: View {
    let streamID: UUID
    let chunks: [LiveAgentTextChunk]

    var body: some View {
        IncrementalChatTextView(chunks: chunks, streamID: streamID)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }
}

private struct LiveAgentReasoningCard: View {
    let streamID: UUID
    let chunks: [LiveAgentTextChunk]
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.trendAccent)
                        .frame(width: 22, height: 22)
                    Text("正在思考…")
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("思考过程")
            .accessibilityValue(isExpanded ? "已展开" : "已收起")

            if isExpanded {
                IncrementalChatTextView(chunks: chunks, streamID: streamID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            AppTheme.insetBackground,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.trendAccent.opacity(0.15), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("agent-reasoning-running")
        .accessibilityLabel("正在思考")
    }
}

private struct AgentOperationResult: View {
    let presentation: AgentToolResultPresentation
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(presentation.details.indices, id: \.self) { index in
                if index > presentation.details.startIndex {
                    Divider()
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: presentation.detailSystemImage)
                        .font(.caption)
                        .foregroundStyle(tint)
                        .frame(width: 16, height: 18)
                    Text(presentation.details[index])
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 10)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}

private struct AgentTurnWaitingCard: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: AppTheme.minimumTapTarget)
        .accessibilityIdentifier("agent-activity-item")
        .accessibilityLabel(message)
    }
}

#Preview("友好工具结果") {
    ScrollView {
        AgentTurnTranscript(
            items: [
                AgentTurnItem(
                    kind: .tool,
                    status: .succeeded,
                    title: "读取用户数据",
                    input: #"{"name":"list_workouts","arguments":{"limit":5}}"#,
                    output: AgentTraceText.json(AgentToolResult.success(
                        """
                        [id:00000000-0000-0000-0000-000000000001] 2026年8月3日 引体向上，5组 × 5次 · 0kg，间歇 120 秒
                        [id:00000000-0000-0000-0000-000000000002] 2026年8月1日 杠铃深蹲，4组 × 5次 · 30kg，间歇 60 秒
                        """
                    ))
                ),
                AgentTurnItem(
                    kind: .tool,
                    status: .succeeded,
                    title: "创建训练计划",
                    input: #"{"name":"create_program","arguments":{}}"#,
                    output: AgentTraceText.json(AgentToolResult.success(
                        "已创建训练计划 [id:00000000-0000-0000-0000-000000000003]：基础力量训练。"
                    ))
                )
            ],
            isLive: false
        )
        .padding()
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
