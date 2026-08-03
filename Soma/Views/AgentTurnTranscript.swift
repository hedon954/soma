import SwiftUI

struct AgentTurnTranscript: View {
    let items: [AgentTurnItem]
    let isLive: Bool

    private var visibleItems: [AgentTurnItem] {
        items.filter {
            $0.kind != .text
                || !AgentVisibleTextSanitizer.sanitize($0.text).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleItems) { item in
                AgentTurnItemCard(item: item)
            }

            if isLive, !visibleItems.contains(where: { $0.status == .running }) {
                AgentTurnWaitingCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentTurnItemCard: View {
    let item: AgentTurnItem

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
        return MarkdownText(text)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .accessibilityLabel(text)
    }

    private var operationCard: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if item.kind == .skill {
                        Text("教练方法")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(kindColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(kindColor.opacity(0.1), in: Capsule())
                    }
                }

                if let toolPresentation {
                    AgentOperationResult(
                        presentation: toolPresentation,
                        tint: kindColor,
                        accessibilityContext: item.title
                    )
                } else if let statusDetail {
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(item.status == .failed ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(kindColor.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var errorCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? "执行失败" : item.title)
                    .font(.subheadline.weight(.semibold))
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
                .foregroundStyle(AppTheme.tint)
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
            item.kind == .skill ? .purple : AppTheme.tint
        }
    }

    private var toolPresentation: AgentToolResultPresentation? {
        guard item.kind == .tool, item.status == .succeeded else { return nil }
        return AgentToolResultPresentation.make(for: item)
    }

    private var statusDetail: String? {
        if let error = item.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty
        {
            return error
        }

        switch item.status {
        case .running:
            return item.kind == .skill ? "正在加载" : "正在执行"
        case .cancelled:
            return "已取消"
        case .failed:
            return "未完成"
        case .succeeded:
            if item.kind == .skill {
                return "已采用这项教练方法"
            }
            return "已完成"
        }
    }
}

private struct AgentOperationResult: View {
    let presentation: AgentToolResultPresentation
    let tint: Color
    let accessibilityContext: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if isExpanded, !presentation.details.isEmpty {
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

            if let disclosureLabel = presentation.disclosureLabel {
                Divider()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(isExpanded ? "收起结果" : disclosureLabel)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint)
                .accessibilityLabel(
                    "\(isExpanded ? "收起" : "查看")\(accessibilityContext)结果"
                )
                .accessibilityValue(isExpanded ? "已展开" : "已收起")
                .accessibilityHint(isExpanded ? "隐藏详细结果" : "显示详细结果")
            }
        }
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
                    input: #"{"name":"query_user_data","arguments":{"scope":"workouts"}}"#,
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
                    input: #"{"name":"create_training_program","arguments":{}}"#,
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
