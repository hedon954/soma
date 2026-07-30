import SwiftUI

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
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(item.status == .failed ? Color.red : Color.secondary)
                        .lineLimit(4)
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
        .accessibilityElement(children: .combine)
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
