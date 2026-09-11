import SwiftUI

/// Each parameter group keeps its own surface. Long left/right summaries wrap in
/// their card; additional cards wrap to the next row and increase the paper height.
struct WorkoutShareGroupLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? WorkoutShareCanvas.contentWidth
        let frames = frames(subviews: subviews, width: width)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let frames = frames(subviews: subviews, width: bounds.width)
        for (index, frame) in frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func frames(subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var originX: CGFloat = 0
        var originY: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let idealWidth = subview.sizeThatFits(.unspecified).width
            let cardWidth = min(max(width, 1), idealWidth)
            let size = subview.sizeThatFits(ProposedViewSize(width: cardWidth, height: nil))
            if originX > 0, originX + size.width > width {
                originY += rowHeight + spacing
                originX = 0
                rowHeight = 0
            }
            frames.append(CGRect(x: originX, y: originY, width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            originX += size.width + spacing
        }
        return frames
    }
}
