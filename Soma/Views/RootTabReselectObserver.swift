import SwiftUI
import UIKit

/// SwiftUI 的 selection 不稳定上报“再次点按已选 Tab”。这个桥只旁听原生 Tab Bar
/// 的触摸，不接管 delegate、不阻断系统手势，业务效果仍由 `AppTabReselect` 决定。
struct RootTabReselectObserver: UIViewRepresentable {
    let onReselect: @MainActor (AppTab) -> Void
    let onDoubleReselect: @MainActor (AppTab) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onReselect: onReselect,
            onDoubleReselect: onDoubleReselect
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onReselect = onReselect
        context.coordinator.onDoubleReselect = onDoubleReselect
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: uiView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onReselect: @MainActor (AppTab) -> Void
        var onDoubleReselect: @MainActor (AppTab) -> Void
        private weak var tabBar: UITabBar?
        private weak var observedWindow: UIWindow?
        private var selectedIndexAtTouchStart: Int?
        private var touchedIndex: Int?
        private lazy var recognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(
                target: self,
                action: #selector(handleTap(_:))
            )
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        private lazy var doubleRecognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(
                target: self,
                action: #selector(handleDoubleTap(_:))
            )
            recognizer.numberOfTapsRequired = 2
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        init(
            onReselect: @escaping @MainActor (AppTab) -> Void,
            onDoubleReselect: @escaping @MainActor (AppTab) -> Void
        ) {
            self.onReselect = onReselect
            self.onDoubleReselect = onDoubleReselect
        }

        func installIfNeeded(from view: UIView) {
            if let tabBar, tabBar.window != nil {
                return
            }
            guard let window = view.window,
                  let foundTabBar = firstTabBar(in: window),
                  foundTabBar !== tabBar
            else { return }

            uninstall()
            tabBar = foundTabBar
            observedWindow = window
            foundTabBar.addGestureRecognizer(recognizer)
            window.addGestureRecognizer(doubleRecognizer)
        }

        func uninstall() {
            tabBar?.removeGestureRecognizer(recognizer)
            observedWindow?.removeGestureRecognizer(doubleRecognizer)
            tabBar = nil
            observedWindow = nil
            selectedIndexAtTouchStart = nil
            touchedIndex = nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let tabBar,
                  let items = tabBar.items,
                  let selectedItem = tabBar.selectedItem,
                  let selectedIndex = items.firstIndex(of: selectedItem),
                  let index = itemIndex(at: touch.location(in: tabBar), in: tabBar)
            else { return false }

            if gestureRecognizer === doubleRecognizer {
                return selectedIndex == 0 && index == 0
            }

            selectedIndexAtTouchStart = selectedIndex
            touchedIndex = index
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            defer {
                selectedIndexAtTouchStart = nil
                touchedIndex = nil
            }
            guard recognizer.state == .ended,
                  let selectedIndexAtTouchStart,
                  selectedIndexAtTouchStart == touchedIndex,
                  let tab = AppTab.rootOrder[safe: selectedIndexAtTouchStart]
            else { return }

            onReselect(tab)
        }

        @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onDoubleReselect(.coach)
        }

        private func itemIndex(at point: CGPoint, in tabBar: UITabBar) -> Int? {
            guard let itemCount = tabBar.items?.count, itemCount > 0 else { return nil }
            let controls = tabBar.subviews
                .compactMap { $0 as? UIControl }
                .filter { !$0.isHidden && $0.bounds.width > 0 }
                .sorted { $0.frame.minX < $1.frame.minX }

            if controls.count == itemCount,
               let index = controls.firstIndex(where: { $0.frame.contains(point) })
            {
                return index
            }

            guard tabBar.bounds.contains(point), tabBar.bounds.width > 0 else { return nil }
            return min(
                Int(point.x / tabBar.bounds.width * CGFloat(itemCount)),
                itemCount - 1
            )
        }

        private func firstTabBar(in view: UIView) -> UITabBar? {
            if let tabBar = view as? UITabBar {
                return tabBar
            }
            for subview in view.subviews {
                if let tabBar = firstTabBar(in: subview) {
                    return tabBar
                }
            }
            return nil
        }
    }
}

private extension AppTab {
    static let rootOrder: [AppTab] = [.coach, .training, .insights, .settings]
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
