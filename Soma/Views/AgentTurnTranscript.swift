import SwiftData
import SwiftUI

struct AgentTurnTranscript: View {
    let items: [AgentTurnItem]
    let isLive: Bool
    var sourceMessage: CoachMessage?
    var isEditable = false

    private var visibleItems: [AgentTurnItem] {
        AgentTurnVisibleItems.make(from: items)
    }

    private var segments: [AgentTurnTranscriptSegment] {
        AgentTurnTranscriptSegments.make(from: items)
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
                    AgentTurnItemCard(item: item)
                case let .record(reference):
                    ChatRecordEditorCard(
                        reference: reference,
                        sourceMessage: sourceMessage,
                        isEditable: isEditable
                    )
                }
            }

            if isLive, !visibleItems.contains(where: { $0.status == .running }) {
                AgentTurnWaitingCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentProcessGroupCard: View {
    let items: [AgentTurnItem]
    @State private var isExpanded = false

    private var isRunning: Bool {
        items.contains { $0.status == .running }
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
    @State private var isExpanded = false

    var body: some View {
        switch item.kind {
        case .text:
            textCard
        case .skill, .tool:
            operationCard
        case .error:
            errorCard
        }
    }

    private var textCard: some View {
        let text = AgentVisibleTextSanitizer.sanitize(item.text)
        return CoachResponseView(text)
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
            .accessibilityLabel(text)
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
                .foregroundStyle(.red)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? "执行失败" : item.title)
                    .font(.subheadline.weight(.medium))
                Text(item.errorMessage ?? item.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color.red.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
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
        switch item.status {
        case .running:
            return item.kind == .skill ? "正在加载" : "正在执行"
        case .cancelled:
            return "已取消"
        case .failed:
            return "未完成"
        case .succeeded:
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
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在继续处理…")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: Capsule()
        )
        .accessibilityLabel("Agent 正在继续处理")
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
