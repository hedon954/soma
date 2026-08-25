import SwiftUI

final class CoachCompletedTextRender: NSObject {
    struct LayoutKey: Hashable {
        let widthInPixels: Int
        let contentSizeCategory: String
    }

    let attributedText: NSAttributedString
    private var measuredHeights: [LayoutKey: CGFloat] = [:]

    init(_ value: NSAttributedString) {
        attributedText = value
    }

    func measuredHeight(
        width: CGFloat,
        scale: CGFloat,
        contentSizeCategory: UIContentSizeCategory
    ) -> CGFloat? {
        measuredHeights[layoutKey(
            width: width,
            scale: scale,
            contentSizeCategory: contentSizeCategory
        )]
    }

    func storeMeasuredHeight(
        _ height: CGFloat,
        width: CGFloat,
        scale: CGFloat,
        contentSizeCategory: UIContentSizeCategory
    ) {
        measuredHeights[layoutKey(
            width: width,
            scale: scale,
            contentSizeCategory: contentSizeCategory
        )] = height
    }

    private func layoutKey(
        width: CGFloat,
        scale: CGFloat,
        contentSizeCategory: UIContentSizeCategory
    ) -> LayoutKey {
        LayoutKey(
            widthInPixels: Int((width * scale).rounded()),
            contentSizeCategory: contentSizeCategory.rawValue
        )
    }
}

private final class CoachAttributedTextBox: NSObject {
    let value: AttributedString

    init(_ value: AttributedString) {
        self.value = value
    }
}

struct CoachTextRenderPreparation: Sendable {
    let document: CoachResponseDocument
    let attributedTexts: [String: AttributedString]

    static func make(for markdown: String) throws -> CoachTextRenderPreparation {
        let document = CoachResponseDocument.parse(markdown)
        var attributedTexts: [String: AttributedString] = [:]
        for content in document.inlineMarkdownContents {
            try Task.checkCancellation()
            attributedTexts[content] = (
                try? AttributedString(
                    markdown: content,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                )
            ) ?? AttributedString(content)
        }
        return CoachTextRenderPreparation(
            document: document,
            attributedTexts: attributedTexts
        )
    }
}

/// 完成态聊天正文不会随 Tab 切换变化。缓存纯值解析结果，避免重新显示 Coach 时
/// 再次拆整份 Markdown、并为每个段落重建内联 AttributedString。
@MainActor
enum CoachTextRenderCache {
    private static let completedTexts: NSCache<NSString, CoachCompletedTextRender> = {
        let cache = NSCache<NSString, CoachCompletedTextRender>()
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

    static func completedText(for markdown: String) -> CoachCompletedTextRender? {
        let key = markdown as NSString
        return completedTexts.object(forKey: key)
    }

    @discardableResult
    static func store(
        _ preparation: CoachTextRenderPreparation,
        for markdown: String
    ) -> CoachCompletedTextRender {
        let key = markdown as NSString
        for (content, value) in preparation.attributedTexts {
            attributedTexts.setObject(
                CoachAttributedTextBox(value),
                forKey: content as NSString,
                cost: content.utf8.count
            )
        }
        let completedText = CoachCompletedTextRender(
            CoachCompletedResponseTextBuilder.make(from: preparation)
        )
        completedTexts.setObject(
            completedText,
            forKey: key,
            cost: markdown.utf8.count
        )
        return completedText
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
        completedTexts.removeAllObjects()
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

    var inlineMarkdownContents: [String] {
        var seen: Set<String> = []
        return blocks.flatMap { block -> [String] in
            switch block {
            case let .paragraph(text):
                [text]
            case let .unorderedList(items), let .orderedList(items):
                items
            case .heading, .divider:
                []
            }
        }.filter { seen.insert($0).inserted }
    }

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
    @State private var completedText: CoachCompletedTextRender?

    init(_ markdown: String) {
        self.markdown = markdown
    }

    var body: some View {
        Group {
            if let completedText {
                CompletedChatTextView(render: completedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coach-completed-agent-markdown")
                    .onAppear {
                        AppPerformance.event(
                            .agentCompletedRender,
                            detail: "phase=single-semantic-text-visible"
                        )
                    }
            } else {
                IncrementalChatTextView(chunks: [
                    LiveAgentTextChunk(id: 0, text: markdown)
                ])
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(markdown)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .accessibilityIdentifier("coach-completed-agent-text")
        .accessibilityValue(completedText == nil ? "正文准备中" : "Markdown 已就绪")
        .task(id: markdown) {
            await prepareText()
        }
    }

    @MainActor
    private func prepareText() async {
        if let cached = CoachTextRenderCache.completedText(for: markdown) {
            completedText = cached
            return
        }
        let interval = AppPerformance.begin(
            .agentMarkdownParse,
            detail: "phase=background-parse,bytes=\(markdown.utf8.count)"
        )
        let source = markdown
        let worker = Task.detached(priority: .userInitiated) {
            try CoachTextRenderPreparation.make(for: source)
        }
        do {
            let preparation = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { throw CancellationError() }
            completedText = CoachTextRenderCache.store(
                preparation,
                for: markdown
            )
            AppPerformance.end(interval, detail: "phase=background-parse,result=ready")
        } catch {
            worker.cancel()
            AppPerformance.end(interval, detail: "phase=background-parse,result=cancelled")
        }
    }
}

@MainActor
enum CoachCompletedResponseTextBuilder {
    static func make(
        from preparation: CoachTextRenderPreparation
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()

        for (index, block) in preparation.document.blocks.enumerated() {
            if index > 0 {
                output.append(spacer())
            }
            switch block {
            case let .heading(level, text):
                if index > 0 {
                    output.append(divider())
                    output.append(NSAttributedString(string: "\n"))
                }
                output.append(heading(text, level: level))
            case let .paragraph(text):
                output.append(inline(text, from: preparation))
            case let .unorderedList(items):
                appendList(items, ordered: false, preparation: preparation, to: output)
            case let .orderedList(items):
                appendList(items, ordered: true, preparation: preparation, to: output)
            case .divider:
                output.append(divider())
            }
        }

        return output
    }

    private static func inline(
        _ content: String,
        from preparation: CoachTextRenderPreparation
    ) -> NSAttributedString {
        let parsed = preparation.attributedTexts[content] ?? AttributedString(content)
        let result = NSMutableAttributedString(
            attributedString: MarkdownAttributedStringBuilder.attributedString(
                fromInline: parsed,
                textStyle: .subheadline,
                weight: .light
            )
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        result.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    private static func heading(_ text: String, level: Int) -> NSAttributedString {
        let style: UIFont.TextStyle = level == 1 ? .title3 : .headline
        let preferred = UIFont.preferredFont(forTextStyle: style)
        let font = UIFont.systemFont(ofSize: preferred.pointSize, weight: .medium)
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: UIColor.label
        ])
    }

    private static func appendList(
        _ items: [String],
        ordered: Bool,
        preparation: CoachTextRenderPreparation,
        to output: NSMutableAttributedString
    ) {
        let listStart = output.length
        for (index, item) in items.enumerated() {
            if index > 0 {
                output.append(NSAttributedString(string: "\n"))
            }
            let prefix = ordered ? "\(index + 1).\t" : "•\t"
            let preferred = UIFont.preferredFont(forTextStyle: .subheadline)
            let font = UIFont.systemFont(ofSize: preferred.pointSize, weight: .regular)
            output.append(NSAttributedString(string: prefix, attributes: [
                .font: font,
                .foregroundColor: UIColor.secondaryLabel
            ]))
            output.append(inline(item, from: preparation))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 22)]
        paragraph.defaultTabInterval = 22
        paragraph.headIndent = 22
        paragraph.firstLineHeadIndent = 0
        output.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(
                location: listStart,
                length: output.length - listStart
            )
        )
    }

    private static func spacer() -> NSAttributedString {
        NSAttributedString(string: "\n\n", attributes: [
            .font: UIFont.preferredFont(forTextStyle: .subheadline)
        ])
    }

    private static func divider() -> NSAttributedString {
        NSAttributedString(string: "────────────────────────", attributes: [
            .font: UIFont.preferredFont(forTextStyle: .caption1),
            .foregroundColor: UIColor.separator
        ])
    }
}
