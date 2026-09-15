import SwiftUI

/// 份量和宏量能一行放下就同行；放不下时宏量另起一行，份量只在超过整行宽度时才换行。
/// 单次测量摆放，不复制视图树，避免饮食卡再走 ViewThatFits。
struct MealItemMetricsLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let portion = subviews.first else { return .zero }
        let macros = subviews.dropFirst().first
        let portionIdeal = portion.sizeThatFits(.unspecified)
        let macrosIdeal = macros?.sizeThatFits(.unspecified) ?? .zero

        if macros != nil, let width = proposal.width, Self.fitsInOneLine(
            portionWidth: portionIdeal.width,
            macrosWidth: macrosIdeal.width,
            spacing: spacing,
            availableWidth: width
        ) {
            return CGSize(
                width: min(width, portionIdeal.width + spacing + macrosIdeal.width),
                height: max(portionIdeal.height, macrosIdeal.height)
            )
        }

        let portionWidth = proposal.width ?? portionIdeal.width
        let portionSize = portion.sizeThatFits(ProposedViewSize(width: portionWidth, height: nil))
        guard let macros else {
            return CGSize(
                width: portionWidth.isFinite ? portionWidth : portionSize.width,
                height: portionSize.height
            )
        }
        let macrosSize = macros.sizeThatFits(ProposedViewSize(width: portionWidth, height: nil))
        return CGSize(
            width: portionWidth.isFinite ? portionWidth : max(portionSize.width, macrosSize.width),
            height: portionSize.height + lineSpacing + macrosSize.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let portion = subviews.first else { return }
        let macros = subviews.dropFirst().first
        let portionIdeal = portion.sizeThatFits(.unspecified)
        let macrosIdeal = macros?.sizeThatFits(.unspecified) ?? .zero

        if let macros, Self.fitsInOneLine(
            portionWidth: portionIdeal.width,
            macrosWidth: macrosIdeal.width,
            spacing: spacing,
            availableWidth: bounds.width
        ) {
            let lineHeight = max(portionIdeal.height, macrosIdeal.height)
            portion.place(
                at: CGPoint(
                    x: bounds.minX,
                    y: bounds.minY + (lineHeight - portionIdeal.height) / 2
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(portionIdeal)
            )
            macros.place(
                at: CGPoint(
                    x: bounds.minX + portionIdeal.width + spacing,
                    y: bounds.minY + (lineHeight - macrosIdeal.height) / 2
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(macrosIdeal)
            )
            return
        }

        let portionSize = portion.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        portion.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: portionSize.height)
        )
        if let macros {
            macros.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + portionSize.height + lineSpacing),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
        }
    }

    static func fitsInOneLine(
        portionWidth: CGFloat,
        macrosWidth: CGFloat,
        spacing: CGFloat,
        availableWidth: CGFloat
    ) -> Bool {
        portionWidth + spacing + macrosWidth <= availableWidth + 0.5
    }
}
