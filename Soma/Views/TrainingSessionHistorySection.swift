import SwiftUI

struct TrainingSessionHistorySection: View {
    let sessions: [WorkoutSession]
    let hasMore: Bool
    let errorMessage: String?
    let namesByID: [UUID: String]
    let onOpen: (UUID) -> Void
    let onDelete: (WorkoutSession) -> Void
    let onLoadMore: () -> Void

    var body: some View {
        SectionHeading(title: "最近训练")
        AppCard {
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    TrainingSessionHomeSwipeRow(
                        session: session,
                        fallbackProgramName: session.programID.flatMap { namesByID[$0] },
                        onOpen: { onOpen(session.id) },
                        onDelete: { onDelete(session) }
                    )
                    if index < sessions.count - 1 {
                        Divider().overlay(AppTheme.separator)
                    }
                }
                if hasMore || errorMessage != nil {
                    if !sessions.isEmpty {
                        Divider().overlay(AppTheme.separator)
                    }
                    Button(errorMessage == nil ? "更早的训练" : "重试") {
                        onLoadMore()
                    }
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.minimumTapTarget)
                    .accessibilityHint(errorMessage ?? "再查询更早的 14 次训练")
                }
            }
        }
    }
}
