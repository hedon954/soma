import SwiftUI

enum AgentToolResultDisclosure {
    static let collapsedLineLimit = 4
    private static let collapsedCharacterThreshold = 80

    static func shouldCollapse(_ text: String) -> Bool {
        text.count > collapsedCharacterThreshold
            || text.components(separatedBy: .newlines).count
            > collapsedLineLimit
    }
}

struct AgentTurnTranscript: View {
    let items: [AgentTurnItem]
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                AgentTurnItemCard(item: item)
            }

            if isLive, !items.contains(where: { $0.status == .running }) {
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
        MarkdownText(item.text)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .accessibilityLabel(item.text)
    }

    private var operationCard: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(item.kind == .skill ? "Skill" : "工具")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(kindColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(kindColor.opacity(0.1), in: Capsule())

                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                if let detail {
                    AgentOperationDetail(
                        text: detail,
                        color: item.status == .failed ? .red : .secondary,
                        allowsExpansion: item.kind == .tool
                            && item.status == .succeeded
                            && AgentToolResultDisclosure.shouldCollapse(detail),
                        accessibilityContext: item.title
                    )
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

    private var detail: String? {
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
                return "已加载"
            }
            guard
                let output = item.output,
                let data = output.data(using: .utf8),
                let result = try? JSONDecoder().decode(AgentToolResult.self, from: data)
            else {
                return "已完成"
            }
            return result.observation
        }
    }
}

private struct AgentOperationDetail: View {
    let text: String
    let color: Color
    let allowsExpansion: Bool
    let accessibilityContext: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
                .lineLimit(
                    allowsExpansion && !isExpanded
                        ? AgentToolResultDisclosure.collapsedLineLimit
                        : nil
                )
                .fixedSize(horizontal: false, vertical: true)

            if allowsExpansion {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "收起" : "展开")
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.tint)
                .accessibilityLabel(
                    "\(isExpanded ? "收起" : "展开")\(accessibilityContext)工具结果"
                )
                .accessibilityValue(isExpanded ? "已展开" : "已收起")
                .accessibilityHint(isExpanded ? "隐藏部分工具结果" : "显示完整工具结果")
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

#Preview("长工具结果") {
    ScrollView {
        AgentTurnTranscript(
            items: [
                AgentTurnItem(
                    kind: .tool,
                    status: .succeeded,
                    title: "查询训练记录",
                    output: AgentTraceText.json(AgentToolResult.success(
                        "已找到最近十二次训练记录。这里保留完整的工具观察结果，默认只展示摘要，"
                            + "用户可以主动展开查看全部内容，也可以再次收起，后续 Agent 回复不受影响。"
                    ))
                )
            ],
            isLive: false
        )
        .padding()
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
