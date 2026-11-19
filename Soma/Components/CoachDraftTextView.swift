import SwiftUI
import UIKit

/// One editor keeps keyboard, selection and height stable as dictation updates arrive.
/// Only UITextViewDelegate user edits flow back into the draft, never render updates.
struct CoachDraftTextView: UIViewRepresentable {
    let text: String
    @Binding var isFocused: Bool
    let onTextChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange, isFocused: $isFocused)
    }

    func makeUIView(context: Context) -> CoachDraftEditor {
        let view = CoachDraftEditor()
        view.delegate = context.coordinator
        context.coordinator.render(text, in: view)
        return view
    }

    func updateUIView(_ view: CoachDraftEditor, context: Context) {
        context.coordinator.onTextChange = onTextChange
        context.coordinator.isFocused = $isFocused
        let font = UIFont.preferredFont(forTextStyle: .body)
        if view.font != font {
            view.font = font
        }
        context.coordinator.render(text, in: view)
        context.coordinator.updateFocus(in: view)
    }

    static func dismantleUIView(_ view: CoachDraftEditor, coordinator: Coordinator) {
        coordinator.cancelFocusUpdate()
        view.delegate = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CoachDraftEditor, context _: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: uiView.measuredHeight(width: width))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onTextChange: (String) -> Void
        var isFocused: Binding<Bool>
        private var focusUpdate: Task<Void, Never>?

        init(onTextChange: @escaping (String) -> Void, isFocused: Binding<Bool>) {
            self.onTextChange = onTextChange
            self.isFocused = isFocused
        }

        func updateFocus(in view: UITextView) {
            cancelFocusUpdate()
            guard isFocused.wrappedValue != view.isFirstResponder else { return }
            // 键盘会改变 SwiftUI 安全区。让本次 representable 更新先结束。
            focusUpdate = Task { @MainActor [weak self, weak view] in
                guard !Task.isCancelled, let self, let view, view.window != nil else { return }
                focusUpdate = nil
                if isFocused.wrappedValue {
                    view.becomeFirstResponder()
                } else {
                    view.resignFirstResponder()
                }
            }
        }

        func cancelFocusUpdate() {
            focusUpdate?.cancel()
            focusUpdate = nil
        }

        func render(_ value: String, in view: UITextView) {
            guard view.markedTextRange == nil, view.text != value else { return }
            let selection = view.selectedRange
            let wasAtEnd = NSMaxRange(selection) == view.textStorage.length && selection.length == 0
            view.text = value
            let length = view.textStorage.length
            let start = wasAtEnd ? length : min(selection.location, length)
            view.selectedRange = NSRange(location: start, length: min(selection.length, length - start))
            view.invalidateIntrinsicContentSize()
            if wasAtEnd {
                view.scrollRangeToVisible(view.selectedRange)
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            onTextChange(textView.text)
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_: UITextView) {
            if !isFocused.wrappedValue {
                isFocused.wrappedValue = true
            }
        }

        func textViewDidEndEditing(_: UITextView) {
            if isFocused.wrappedValue {
                isFocused.wrappedValue = false
            }
        }
    }
}

final class CoachDraftEditor: UITextView {
    static let horizontalInset: CGFloat = 13
    static let verticalInset: CGFloat = 11
    static let maximumLines: CGFloat = 5

    init() {
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = .clear
        textColor = UIColor(AppTheme.accent)
        tintColor = UIColor(AppTheme.accent)
        font = .preferredFont(forTextStyle: .body)
        adjustsFontForContentSizeCategory = true
        textContainerInset = UIEdgeInsets(
            top: 0, left: Self.horizontalInset,
            bottom: 0, right: Self.horizontalInset
        )
        textContainer.lineFragmentPadding = 0
        isScrollEnabled = false
        returnKeyType = .default
        accessibilityIdentifier = "coach-message-input"
        accessibilityLabel = "消息输入框"
        accessibilityHint = "可输入或修改听写文字，完成后点发送"
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        max(AppTheme.minimumTapTarget - 2 * Self.verticalInset, min(naturalHeight(width: width), heightLimit))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        // 只有实际布局宽度决定滚动状态。SwiftUI 的候选宽度只用于测量。
        let needsScrolling = naturalHeight(width: bounds.width) > heightLimit
        if isScrollEnabled != needsScrolling {
            isScrollEnabled = needsScrolling
        }
    }

    private var heightLimit: CGFloat {
        let lineHeight = font?.lineHeight ?? 21
        let insets = textContainerInset.top + textContainerInset.bottom
        return ceil(Self.maximumLines * lineHeight + insets)
    }

    private func naturalHeight(width: CGFloat) -> CGFloat {
        ceil(sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }
}
