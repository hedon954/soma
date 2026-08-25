import SwiftUI
import UIKit

/// 使用同一个 TextKit 文本存储追加流式尾部。SwiftUI 只更新 representable，
/// 不再让不断增长的无换行段落在每个 tick 重建一个完整 `Text`。
struct IncrementalChatTextView: UIViewRepresentable {
    let chunks: [LiveAgentTextChunk]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        // iOS 新版本默认走 TextKit 2。长回复重新显示时，它会为整篇正文重新创建
        // NSTextLayoutFragment，真机采样中这条路径稳定占用约 200 ms。聊天正文只需要
        // 顺序文本与选择能力，显式使用 TextKit 1 可以保留增量 textStorage，并避免
        // Tab 返回时重复生成整篇布局片段。
        let view = UITextView(usingTextLayoutManager: false)
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.replaceText(in: view, with: chunks)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.update(uiView, with: chunks)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context _: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let size = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(size.height))
    }

    final class Coordinator {
        private var renderedChunks: [LiveAgentTextChunk] = []
        private var contentSizeCategory: UIContentSizeCategory?

        func update(_ view: UITextView, with chunks: [LiveAgentTextChunk]) {
            let currentCategory = view.traitCollection.preferredContentSizeCategory
            guard contentSizeCategory == currentCategory,
                  let suffix = Self.appendedSuffix(
                      from: renderedChunks,
                      to: chunks
                  )
            else {
                replaceText(in: view, with: chunks)
                return
            }
            guard !suffix.isEmpty else {
                renderedChunks = chunks
                return
            }
            view.textStorage.append(Self.attributedText(suffix))
            renderedChunks = chunks
            view.invalidateIntrinsicContentSize()
        }

        func replaceText(in view: UITextView, with chunks: [LiveAgentTextChunk]) {
            view.attributedText = Self.attributedText(chunks.map(\.text).joined())
            renderedChunks = chunks
            contentSizeCategory = view.traitCollection.preferredContentSizeCategory
            view.invalidateIntrinsicContentSize()
        }

        private static func appendedSuffix(
            from previous: [LiveAgentTextChunk],
            to current: [LiveAgentTextChunk]
        ) -> String? {
            guard !previous.isEmpty, current.count >= previous.count else {
                return previous.isEmpty ? current.map(\.text).joined() : nil
            }
            let previousTailIndex = previous.index(before: previous.endIndex)
            guard previous[..<previousTailIndex]
                .elementsEqual(current.prefix(previousTailIndex)),
                current[previousTailIndex].id == previous[previousTailIndex].id,
                current[previousTailIndex].text.hasPrefix(previous[previousTailIndex].text)
            else {
                return nil
            }
            var suffix = String(
                current[previousTailIndex].text.dropFirst(
                    previous[previousTailIndex].text.count
                )
            )
            for chunk in current.dropFirst(previous.count) {
                suffix += chunk.text
            }
            return suffix
        }

        private static func attributedText(_ text: String) -> NSAttributedString {
            let preferred = UIFont.preferredFont(forTextStyle: .subheadline)
            let font = UIFont.systemFont(ofSize: preferred.pointSize, weight: .light)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            return NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: paragraph
                ]
            )
        }
    }
}

/// 完成态 Markdown 也保持为单一 TextKit 文本面。标题、列表与分隔线已经由本地受控
/// parser 转成属性文本，不再让一条长回复在每次显示时创建数百个 SwiftUI 子 View。
struct CompletedChatTextView: UIViewRepresentable {
    let render: CoachCompletedTextRender

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        // 与流式文本保持同一 TextKit 1 路径。完成态高度命中缓存后，重新显示只需
        // 复用 NSLayoutManager 的字形布局，不再触发 TextKit 2 的全量 fragment 构造。
        let view = UITextView(usingTextLayoutManager: false)
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.update(view, with: render.attributedText)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.update(uiView, with: render.attributedText)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context _: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let category = uiView.traitCollection.preferredContentSizeCategory
        let scale = uiView.window?.screen.scale ?? uiView.traitCollection.displayScale
        if let height = render.measuredHeight(
            width: width,
            scale: scale,
            contentSizeCategory: category
        ) {
            return CGSize(width: width, height: height)
        }
        let size = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        let height = ceil(size.height)
        render.storeMeasuredHeight(
            height,
            width: width,
            scale: scale,
            contentSizeCategory: category
        )
        return CGSize(width: width, height: height)
    }

    final class Coordinator {
        private var renderedText: NSAttributedString?

        func update(_ view: UITextView, with text: NSAttributedString) {
            guard renderedText !== text else { return }
            view.attributedText = text
            view.accessibilityLabel = text.string
            renderedText = text
            view.invalidateIntrinsicContentSize()
        }
    }
}
