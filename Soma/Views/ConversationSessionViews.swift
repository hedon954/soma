import SwiftData
import SwiftUI

struct ConversationSessionDrawer: View {
    let currentSessionID: UUID?
    let isProcessing: Bool
    let onNewSession: () -> Void
    let onSelectSession: (ConversationSession) -> Void

    @Query(sort: \ConversationSession.updatedAt, order: .reverse)
    private var sessions: [ConversationSession]
    @Query(sort: \CoachMessage.date) private var messages: [CoachMessage]

    private var visibleSessions: [ConversationSession] {
        sessions.filter { session in
            session.id == currentSessionID
                || messages.contains(where: { $0.sessionID == session.id })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("对话")
                    .font(.title2.bold())
                Spacer()
                Button(action: onNewSession) {
                    Image(systemName: "square.and.pencil")
                        .font(.title3.weight(.semibold))
                }
                .accessibilityLabel("新建对话")
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            if visibleSessions.isEmpty {
                ContentUnavailableView(
                    "暂无对话",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("点击右上角开始新对话。")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(visibleSessions) { session in
                            Button {
                                onSelectSession(session)
                            } label: {
                                sessionRow(session)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(
                                session.id == currentSessionID
                                    ? "当前对话"
                                    : "切换后可继续对话"
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }

            if isProcessing {
                Label("Agent 正在原对话中处理", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func sessionRow(_ session: ConversationSession) -> some View {
        let messageCount = messages.count { $0.sessionID == session.id }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if session.id == currentSessionID {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.tint)
                        .accessibilityHidden(true)
                }
            }
            Text(
                "\(session.updatedAt.formatted(date: .abbreviated, time: .shortened)) · \(messageCount) 条"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            session.id == currentSessionID
                ? AppTheme.softTint
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}
