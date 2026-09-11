import SwiftUI

enum WorkoutShareCanvas {
    /// iPhone 17 Pro Max logical canvas (1320 × 2868 px @3x).
    static let width: CGFloat = 440
    static let height: CGFloat = 956
    static let horizontalPadding: CGFloat = 16
    static let fillThroughExerciseCount = 7

    static var contentWidth: CGFloat {
        width - horizontalPadding * 2
    }
}

enum WorkoutSharePosterSlot {
    case header
    case overview
    case details
    case footer
}

private struct WorkoutSharePosterSlotKey: LayoutValueKey {
    static let defaultValue = WorkoutSharePosterSlot.details
}

extension View {
    func sharePosterSlot(_ slot: WorkoutSharePosterSlot) -> some View {
        layoutValue(key: WorkoutSharePosterSlotKey.self, value: slot)
    }
}

enum WorkoutSharePosterLayout {
    struct Metrics: Equatable {
        var outerTop: CGFloat
        var outerBottom: CGFloat
        var sectionSpacing: CGFloat
        var headerSpacing: CGFloat
        var titleSize: CGFloat
        var overviewSpacing: CGFloat
        var muscleMapHeight: CGFloat
        var volumeSize: CGFloat
        var detailSpacing: CGFloat
        var rowSpacing: CGFloat
        var rowVerticalPadding: CGFloat
        var rowNameSize: CGFloat
        var rowMetaSize: CGFloat
        var rowCornerRadius: CGFloat

        var minBodyHeight: CGFloat {
            WorkoutShareCanvas.height - outerTop - outerBottom
        }
    }

    static func metrics(exerciseCount: Int) -> Metrics {
        interpolated(tightness: tightness(for: max(exerciseCount, 0)))
    }

    private static func tightness(for count: Int) -> CGFloat {
        if count <= 1 {
            return 0
        }
        if count >= WorkoutShareCanvas.fillThroughExerciseCount {
            return 1
        }
        return CGFloat(count - 1) / CGFloat(WorkoutShareCanvas.fillThroughExerciseCount - 1)
    }

    private static func interpolated(tightness: CGFloat) -> Metrics {
        Metrics(
            outerTop: lerp(24, 20, tightness),
            outerBottom: lerp(22, 18, tightness),
            sectionSpacing: lerp(16, 8, tightness),
            headerSpacing: lerp(8, 4, tightness),
            titleSize: lerp(32, 28, tightness),
            overviewSpacing: lerp(14, 10, tightness),
            muscleMapHeight: lerp(168, 124, tightness),
            volumeSize: lerp(84, 68, tightness),
            detailSpacing: lerp(12, 6, tightness),
            rowSpacing: lerp(12, 6, tightness),
            rowVerticalPadding: lerp(20, 8, tightness),
            rowNameSize: lerp(16, 13, tightness),
            rowMetaSize: lerp(14, 12, tightness),
            rowCornerRadius: lerp(14, 10, tightness)
        )
    }

    private static func lerp(_ loose: CGFloat, _ tight: CGFloat, _ tightness: CGFloat) -> CGFloat {
        loose + (tight - loose) * tightness
    }
}

/// Fills the Pro Max paper when the session is short; grows only after compact content no longer fits.
struct WorkoutSharePosterPageLayout: Layout {
    var spacing: CGFloat
    var minHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? WorkoutShareCanvas.contentWidth
        return CGSize(width: width, height: max(minHeight, stackedHeight(subviews: subviews, width: width)))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let width = bounds.width
        let ideals = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let extra = max(0, bounds.height - stackedHeight(ideals: ideals))
        var originY = bounds.minY
        for index in subviews.indices {
            var height = ideals[index]
            if subviews[index][WorkoutSharePosterSlotKey.self] == .details {
                height += extra
            }
            subviews[index].place(
                at: CGPoint(x: bounds.minX, y: originY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: height)
            )
            originY += height + spacing
        }
    }

    private func stackedHeight(subviews: Subviews, width: CGFloat) -> CGFloat {
        stackedHeight(
            ideals: subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        )
    }

    private func stackedHeight(ideals: [CGFloat]) -> CGFloat {
        let spacingTotal = spacing * CGFloat(max(ideals.count - 1, 0))
        return ideals.reduce(0, +) + spacingTotal
    }
}
