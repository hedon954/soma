import SwiftUI
import UIKit

enum JSONAutoIndenter {
    static let indentWidth = 2

    struct NewlineEdit: Equatable {
        let replacement: String
        let cursorOffset: Int
    }

    static func indentLevel(in text: String) -> Int {
        var level = 0
        var inString = false
        var escaped = false
        for character in text {
            if inString {
                if escaped {
                    escaped = false; continue
                }
                if character == "\\" {
                    escaped = true; continue
                }
                if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" || character == "[" {
                level += 1
            } else if character == "}" || character == "]" {
                level = max(0, level - 1)
            }
        }
        return level
    }

    static func newlineEdit(before: String, after: String) -> NewlineEdit {
        let level = indentLevel(in: before)
        let inner = String(repeating: " ", count: level * indentWidth)
        let trimmedAfter = after.drop(while: { $0 == " " || $0 == "\t" })
        if let first = trimmedAfter.first, first == "}" || first == "]" {
            let outer = String(repeating: " ", count: max(0, level - 1) * indentWidth)
            let replacement = "\n\(inner)\n\(outer)"
            return NewlineEdit(replacement: replacement, cursorOffset: 1 + inner.count)
        }
        let replacement = "\n\(inner)"
        return NewlineEdit(replacement: replacement, cursorOffset: replacement.count)
    }
}

enum JSONSyntaxTokenKind: Equatable {
    case key, string, number, keyword, punctuation, plain
}

struct JSONSyntaxToken: Equatable {
    let range: NSRange
    let kind: JSONSyntaxTokenKind
}

enum JSONSyntaxHighlighter {
    static func tokens(in text: String) -> [JSONSyntaxToken] {
        let expression = try? NSRegularExpression(
            pattern: #"\"(?:\\.|[^\"\\])*\"(?=\s*:)|\"(?:\\.|[^\"\\])*\"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|\b(?:true|false|null)\b|[{}\[\]:,]"#
        )
        let full = NSRange(location: 0, length: (text as NSString).length)
        return expression?.matches(in: text, range: full).map { match in
            let token = (text as NSString).substring(with: match.range)
            let kind: JSONSyntaxTokenKind
            if token.first == "\"" {
                let tail = (text as NSString).substring(from: NSMaxRange(match.range))
                kind = tail.first(where: { !$0.isWhitespace }) == ":" ? .key : .string
            } else if "{}[]:,".contains(token) {
                kind = .punctuation
            } else if ["true", "false", "null"].contains(token) {
                kind = .keyword
            } else {
                kind = .number
            }
            return JSONSyntaxToken(range: match.range, kind: kind)
        } ?? []
    }

    static func apply(to storage: NSTextStorage, font: UIFont) {
        let full = NSRange(location: 0, length: storage.length)
        storage.setAttributes([.font: font, .foregroundColor: UIColor.label], range: full)
        for token in tokens(in: storage.string) {
            let color: UIColor = switch token.kind {
            case .key: .systemPurple
            case .string: .systemOrange
            case .number: .systemBlue
            case .keyword: .systemPink
            case .punctuation: .secondaryLabel
            case .plain: .label
            }
            storage.addAttribute(.foregroundColor, value: color, range: token.range)
        }
    }
}

struct JSONEditorView: View {
    @Binding var text: String
    var minHeight: CGFloat = 180
    @StateObject private var session = JSONEditorSession()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                toolbarButton("arrow.uturn.backward", label: "撤销") { session.undo() }
                toolbarButton("arrow.uturn.forward", label: "重做") { session.redo() }
                toolbarButton("paintbrush", label: "格式化") { session.format() }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(AppTheme.insetBackground)
            Divider()
            JSONEditorTextView(text: $text, session: session)
                .frame(minHeight: minHeight)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.primary.opacity(0.14), lineWidth: 1)
        }
        .accessibilityIdentifier("llm-extra-config-editor")
    }

    private func toolbarButton(
        _ image: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: image).frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

@MainActor
private final class JSONEditorSession: ObservableObject {
    weak var textView: UITextView?

    func undo() {
        textView?.undoManager?.undo()
    }

    func redo() {
        textView?.undoManager?.redo()
    }

    func format() {
        guard let textView,
              let data = textView.text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let text = String(data: formatted, encoding: .utf8)
        else { return }
        textView.text = text
        textView.delegate?.textViewDidChange?(textView)
    }
}

private struct JSONEditorTextView: UIViewRepresentable {
    @Binding var text: String
    @ObservedObject var session: JSONEditorSession

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> JSONCodeTextView {
        let view = JSONCodeTextView()
        view.delegate = context.coordinator
        view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        view.backgroundColor = .secondarySystemGroupedBackground
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.keyboardType = .asciiCapable
        view.alwaysBounceVertical = true
        view.textContainerInset = UIEdgeInsets(top: 10, left: 42, bottom: 10, right: 8)
        view.text = text
        session.textView = view
        context.coordinator.highlight(view)
        return view
    }

    func updateUIView(_ view: JSONCodeTextView, context: Context) {
        context.coordinator.text = $text
        session.textView = view
        guard view.text != text, view.markedTextRange == nil else { return }
        view.text = text
        context.coordinator.highlight(view)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        private var highlighting = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !highlighting else { return }
            text.wrappedValue = textView.text
            if textView.markedTextRange == nil {
                highlight(textView)
            }
            textView.setNeedsDisplay()
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard replacement == "\n", textView.markedTextRange == nil else { return true }
            let value = textView.text as NSString
            let before = value.substring(to: range.location)
            let after = value.substring(from: NSMaxRange(range))
            let edit = JSONAutoIndenter.newlineEdit(before: before, after: after)
            textView.textStorage.replaceCharacters(in: range, with: edit.replacement)
            textView.selectedRange = NSRange(
                location: range.location + edit.cursorOffset,
                length: 0
            )
            textViewDidChange(textView)
            return false
        }

        func highlight(_ textView: UITextView) {
            guard let storage = textView.textStorage as NSTextStorage?,
                  textView.markedTextRange == nil
            else { return }
            highlighting = true
            let selection = textView.selectedRange
            storage.beginEditing()
            JSONSyntaxHighlighter.apply(
                to: storage,
                font: textView.font ?? .monospacedSystemFont(ofSize: 14, weight: .regular)
            )
            storage.endEditing()
            textView.selectedRange = selection
            highlighting = false
        }
    }
}

private final class JSONCodeTextView: UITextView {
    override func draw(_ rect: CGRect) {
        let lineRange = (text as NSString).lineRange(for: selectedRange)
        if let start = position(from: beginningOfDocument, offset: lineRange.location),
           let end = position(from: start, offset: max(1, lineRange.length)),
           let textRange = textRange(from: start, to: end)
        {
            let current = firstRect(for: textRange)
            UIColor.systemFill.withAlphaComponent(0.26).setFill()
            UIBezierPath(rect: CGRect(x: 36, y: current.minY, width: bounds.width - 36, height: current.height)).fill()
        }
        super.draw(rect)
        drawLineNumbers()
    }

    private func drawLineNumbers() {
        let font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel
        ]
        var line = 1
        var index = 0
        let nsText = text as NSString
        repeat {
            if let position = position(from: beginningOfDocument, offset: index) {
                let caret = caretRect(for: position)
                if caret.maxY >= contentOffset.y, caret.minY <= contentOffset.y + bounds.height {
                    let label = "\(line)" as NSString
                    let size = label.size(withAttributes: attributes)
                    label.draw(
                        at: CGPoint(x: 31 - size.width, y: caret.minY + 2),
                        withAttributes: attributes
                    )
                }
            }
            let range = nsText.lineRange(for: NSRange(location: index, length: 0))
            let next = NSMaxRange(range)
            guard next > index else { break }
            index = next
            line += 1
        } while index < nsText.length
    }
}
