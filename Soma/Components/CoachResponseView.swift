import SwiftUI

private final class CoachResponseDocumentBox: NSObject {
    let value: CoachResponseDocument

    init(_ value: CoachResponseDocument) {
        self.value = value
    }
}

private final class CoachAttributedTextBox: NSObject {
    let value: AttributedString

    init(_ value: AttributedString) {
        self.value = value
    }
}

/// 完成态聊天正文不会随 Tab 切换变化。缓存纯值解析结果，避免重新显示 Coach 时
/// 再次拆整份 Markdown、并为每个段落重建内联 AttributedString。
@MainActor
enum CoachTextRenderCache {
    private static let documents: NSCache<NSString, CoachResponseDocumentBox> = {
        let cache = NSCache<NSString, CoachResponseDocumentBox>()
        cache.countLimit = 256
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()

    private static let attributedTexts: NSCache<NSString, CoachAttributedTextBox> = {
        let cache = NSCache<NSString, CoachAttributedTextBox>()
        cache.countLimit = 512
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()

    static func document(for markdown: String) -> CoachResponseDocument {
        let key = markdown as NSString
        if let cached = documents.object(forKey: key) {
            return cached.value
        }
        let value = CoachResponseDocument.parse(markdown)
        documents.setObject(
            CoachResponseDocumentBox(value),
            forKey: key,
            cost: markdown.utf8.count
        )
        return value
    }

    static func attributedText(for content: String) -> AttributedString {
        let key = content as NSString
        if let cached = attributedTexts.object(forKey: key) {
            return cached.value
        }
        let value = (
            try? AttributedString(
                markdown: content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        ) ?? AttributedString(content)
        attributedTexts.setObject(
            CoachAttributedTextBox(value),
            forKey: key,
            cost: content.utf8.count
        )
        return value
    }

    static func removeAll() {
        documents.removeAllObjects()
        attributedTexts.removeAllObjects()
    }
}

enum CoachResponseBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case divider
}

struct CoachResponseDocument: Equatable, Sendable {
    var blocks: [CoachResponseBlock]

    static func parse(_ markdown: String) -> CoachResponseDocument {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [CoachResponseBlock] = []
        var paragraph: [String] = []
        var listKind: ListKind?
        var listItems: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }

        func flushList() {
            guard let resolvedKind = listKind, !listItems.isEmpty else { return }
            blocks.append(
                resolvedKind == .ordered
                    ? .orderedList(listItems)
                    : .unorderedList(listItems)
            )
            listItems = []
            listKind = nil
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            if Self.isDivider(line) {
                flushParagraph()
                flushList()
                blocks.append(.divider)
                continue
            }

            if let heading = Self.heading(in: line) {
                flushParagraph()
                flushList()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if let item = Self.listItem(in: line) {
                flushParagraph()
                if let listKind, listKind != item.kind {
                    flushList()
                }
                listKind = item.kind
                listItems.append(item.text)
                continue
            }

            if listKind != nil, rawLine.first?.isWhitespace == true,
               !listItems.isEmpty
            {
                listItems[listItems.count - 1] += " " + line
                continue
            }

            flushList()
            paragraph.append(line)
        }

        flushParagraph()
        flushList()
        return CoachResponseDocument(blocks: blocks)
    }

    private enum ListKind {
        case ordered, unordered
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact == "---" || compact == "***" || compact == "___"
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let markerCount = line.prefix { $0 == "#" }.count
        guard (1 ... 3).contains(markerCount) else { return nil }
        let markerEnd = line.index(line.startIndex, offsetBy: markerCount)
        guard markerEnd < line.endIndex, line[markerEnd].isWhitespace else {
            return nil
        }
        let text = line[markerEnd...]
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (markerCount, text)
    }

    private static func listItem(
        in line: String
    ) -> (kind: ListKind, text: String)? {
        for prefix in ["- ", "* ", "+ ", "• "] where line.hasPrefix(prefix) {
            let text = String(line.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : (.unordered, text)
        }

        guard let dot = line.firstIndex(of: ".") else { return nil }
        let number = line[..<dot]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line.index(after: dot)
        guard afterDot < line.endIndex, line[afterDot].isWhitespace else {
            return nil
        }
        let text = line[afterDot...].trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (.ordered, text)
    }
}

/// AI 只输出普通 Markdown；本地把有限的标题、段落、分隔线和列表映射成原生布局。
/// 未识别内容仍按正文显示，模型不能注入任意 SwiftUI 组件。
struct CoachResponseView: View {
    let markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    private var document: CoachResponseDocument {
        CoachTextRenderCache.document(for: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, index: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: CoachResponseBlock, index: Int) -> some View {
        switch block {
        case let .heading(level, text):
            VStack(alignment: .leading, spacing: 12) {
                if index > 0 {
                    Divider()
                        .overlay(AppTheme.separator)
                }
                heading(text, level: level)
            }
        case let .paragraph(text):
            SelectableChatText(
                content: text,
                color: .label,
                enablesSelection: false
            )
        case let .unorderedList(items):
            list(items, ordered: false)
        case let .orderedList(items):
            list(items, ordered: true)
        case .divider:
            Divider()
                .overlay(AppTheme.separator)
        }
    }

    private func heading(_ title: String, level: Int) -> some View {
        let style = CoachResponseSectionStyle.make(for: title)
        return HStack(spacing: 8) {
            if let symbol = style.symbol {
                Image(systemName: symbol)
                    .foregroundStyle(style.tint)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(
                    level == 1
                        ? .title3.weight(.medium)
                        : .headline.weight(.medium)
                )
                .foregroundStyle(.primary)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func list(_ items: [String], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 14, alignment: .trailing)
                        .accessibilityHidden(true)
                    SelectableChatText(
                        content: item,
                        color: .label,
                        enablesSelection: false
                    )
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct CoachResponseSectionStyle {
    var symbol: String?
    var tint: Color

    static func make(for title: String) -> CoachResponseSectionStyle {
        let normalized = title.lowercased()
        if normalized.contains("建议") || normalized.contains("下一步") {
            return CoachResponseSectionStyle(
                symbol: "sparkles",
                tint: AppTheme.warning
            )
        }
        if normalized.contains("分析") || normalized.contains("趋势") {
            return CoachResponseSectionStyle(
                symbol: "chart.line.uptrend.xyaxis",
                tint: AppTheme.trendAccent
            )
        }
        if normalized.contains("注意") || normalized.contains("风险")
            || normalized.contains("安全")
        {
            return CoachResponseSectionStyle(
                symbol: "exclamationmark.triangle.fill",
                tint: AppTheme.warning
            )
        }
        if normalized.contains("训练") || normalized.contains("结论")
            || normalized.contains("总结")
        {
            return CoachResponseSectionStyle(
                symbol: "dumbbell.fill",
                tint: AppTheme.trainingAccent
            )
        }
        return CoachResponseSectionStyle(symbol: nil, tint: AppTheme.tint)
    }
}
