import SwiftUI

struct InputSuggestionItem: Identifiable, Equatable {
    let id: String
    let title: String
    var detail: String?
    var icon: String?

    init(
        id: String,
        title: String,
        detail: String? = nil,
        icon: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.icon = icon
    }
}

/// ADR 0046：「输入历史」式候选。挨着输入框的纵向列表，一次点击写入完整值。
/// LLM 模型建议与聊天动作建议共用这一形态，避免两套心智模型。
struct InputSuggestionList: View {
    let items: [InputSuggestionItem]
    var selectionHint: String?
    /// 候选多于这个条数时列表自身滚动，露出的下一行既是提示也是入口；
    /// `nil` 表示全部平铺（聊天动作建议最多五条，不需要滚动）。
    var scrollAfter: Int?
    let onSelect: (InputSuggestionItem) -> Void

    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 38

    var body: some View {
        if !items.isEmpty {
            content
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }

    @ViewBuilder
    private var content: some View {
        if let scrollAfter, items.count > scrollAfter {
            ScrollView {
                rows
            }
            .frame(height: rowHeight * CGFloat(scrollAfter))
        } else {
            rows
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider().padding(.leading, item.icon == nil ? 12 : 38)
                }
                Button {
                    onSelect(item)
                } label: {
                    row(item)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    [item.title, item.detail]
                        .compactMap { $0 }
                        .joined(separator: "，")
                )
                .accessibilityHint(selectionHint ?? "填入输入框")
            }
        }
    }

    private func row(_ item: InputSuggestionItem) -> some View {
        HStack(spacing: 8) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.tint)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.left")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
