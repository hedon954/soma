import SwiftData
import SwiftUI

struct ConversationSessionListView: View {
    let currentSessionID: UUID?

    @Query(sort: \ConversationSession.startedAt, order: .reverse)
    private var sessions: [ConversationSession]
    @Query(sort: \CoachMessage.date) private var messages: [CoachMessage]

    private var visibleSessions: [ConversationSession] {
        sessions.filter { session in
            session.id == currentSessionID
                || messages.contains(where: { $0.sessionID == session.id })
        }
    }

    var body: some View {
        Group {
            if visibleSessions.isEmpty {
                ContentUnavailableView(
                    "暂无历史对话",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("发送第一条消息后，对话会按 Session 保存在本机。")
                )
            } else {
                List(visibleSessions) { session in
                    NavigationLink {
                        ConversationSessionTranscriptView(session: session)
                    } label: {
                        sessionRow(session)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .appPageBackground()
        .navigationTitle("历史对话")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sessionRow(_ session: ConversationSession) -> some View {
        let messageCount = messages.count { $0.sessionID == session.id }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if session.id == currentSessionID {
                    Text("当前")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.tint)
                }
            }
            Text(
                "\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(messageCount) 条消息"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct ConversationSessionTranscriptView: View {
    let session: ConversationSession

    @Query(sort: \CoachMessage.date) private var allMessages: [CoachMessage]

    private var messages: [CoachMessage] {
        allMessages.filter { $0.sessionID == session.id }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if messages.isEmpty {
                    ContentUnavailableView(
                        "这段对话还没有消息",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                    .padding(.top, 80)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(messages) { message in
                            CoachBubble(message: message, isLive: false)
                                .id(message.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("session-bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .appPageBackground()
            .onAppear {
                proxy.scrollTo("session-bottom", anchor: .bottom)
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
