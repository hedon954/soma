import SwiftUI

@MainActor
final class AssistantFeedbackScroller {
    private var focusedTarget: AssistantFeedbackScrollTarget?
    private var composerTop: CGFloat?

    func handle(
        _ event: AssistantFeedbackScrollEvent,
        target: AssistantFeedbackScrollTarget,
        using proxy: ScrollViewProxy
    ) {
        switch event {
        case .expanded:
            Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            }
        case .focusChanged(true):
            focusedTarget = target
            proxy.scrollTo(target, anchor: .bottom)
        case .focusChanged(false):
            if focusedTarget == target {
                focusedTarget = nil
            }
        case .editorHeightChanged:
            if focusedTarget == target {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }

    func composerTopChanged(to top: CGFloat, using proxy: ScrollViewProxy) {
        let previousTop = composerTop
        composerTop = top
        // Follow the actual inset, including changes in keyboard height and composer content.
        // When the keyboard is being dismissed interactively, let the user drive the scroll.
        if let focusedTarget, let previousTop, top < previousTop {
            proxy.scrollTo(focusedTarget, anchor: .bottom)
        }
    }
}
