import SwiftUI
import UIKit

enum ChatTextSelectionStyle {
    static let tintColor = UIColor.label
}

/// 聊天正文使用原生 SwiftUI Text：保留系统选择和内联 Markdown，同时避免
/// 每个段落各自创建不可滚动 UITextView 并在 Tab 切换时反复执行 TextKit2 全量测量。
struct SelectableChatText: View {
    let content: String
    let color: UIColor
    var enablesSelection = true

    var body: some View {
        let text = Text(attributedContent)
            .font(.subheadline.weight(.light))
            .lineSpacing(4)
            .foregroundStyle(Color(uiColor: color))
            .tint(Color(uiColor: ChatTextSelectionStyle.tintColor))
            .accessibilityLabel(content)
        if enablesSelection {
            text.textSelection(.enabled)
        } else {
            text
        }
    }

    private var attributedContent: AttributedString {
        CoachTextRenderCache.attributedText(for: content)
    }
}
