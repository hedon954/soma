import SwiftUI

enum CompactActionVisualPlacement {
    case first
    case following

    fileprivate var alignment: Alignment {
        switch self {
        case .first:
            .center
        case .following:
            .leading
        }
    }
}

/// Keeps every action in an independent 44 pt hit target while placing the
/// visible glyphs 12 pt apart. The following slot intentionally leaves its
/// trailing hit area empty instead of overlapping the previous button.
struct CompactActionLabel<Content: View>: View {
    let placement: CompactActionVisualPlacement
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: 20, height: 20)
            .frame(
                width: AppTheme.minimumTapTarget,
                height: AppTheme.minimumTapTarget,
                alignment: placement.alignment
            )
    }
}
