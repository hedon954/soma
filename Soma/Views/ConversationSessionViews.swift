import SwiftData
import SwiftUI

struct ConversationSessionDrawer: View {
    let currentSessionID: UUID?
    let isProcessing: Bool
    let onNewSession: () -> Void
    let onSelectSession: (ConversationSession) -> Void
    let onRenameSession: (ConversationSession, String) -> Bool
    let onRestoreAutomaticTitle: (ConversationSession) -> Bool
    let onDeleteSession: (ConversationSession) -> Void

    @Query(sort: \ConversationSession.updatedAt, order: .reverse)
    private var sessions: [ConversationSession]
    @Query(sort: \CoachMessage.date) private var messages: [CoachMessage]
    @State private var renamingSessionID: UUID?
    @State private var renameDraft = ""
    @State private var showsRenameAlert = false
    @State private var showsRenameFailureAlert = false

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
                List {
                    ForEach(visibleSessions) { session in
                        sessionListRow(session)
                            .listRowInsets(EdgeInsets(
                                top: 3,
                                leading: 10,
                                bottom: 3,
                                trailing: 10
                            ))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
        .alert("重命名对话", isPresented: $showsRenameAlert) {
            TextField("对话标题", text: $renameDraft)
            Button("取消", role: .cancel) {
                renamingSessionID = nil
            }
            Button("保存") {
                saveRename()
            }
            .disabled(normalizedRenameDraft == nil)
        } message: {
            Text("标题最多 40 个字符。")
        }
        .alert("无法保存标题", isPresented: $showsRenameFailureAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("标题没有保存成功，请稍后重试。")
        }
    }

    private var normalizedRenameDraft: String? {
        ConversationSession.normalizedTitle(
            renameDraft,
            maximumLength: ConversationSession.maximumManualTitleLength
        )
    }

    private func sessionListRow(_ session: ConversationSession) -> some View {
        HStack(spacing: 0) {
            Button {
                onSelectSession(session)
            } label: {
                sessionRowContent(session)
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                session.id == currentSessionID
                    ? "当前对话"
                    : "切换后可继续对话"
            )
            .accessibilityAction(named: "重命名对话") {
                beginRename(session)
            }

            Menu {
                Button {
                    beginRename(session)
                } label: {
                    Label("重命名", systemImage: "pencil")
                }
                if session.titleSource == .manual {
                    Button {
                        if !onRestoreAutomaticTitle(session) {
                            showsRenameFailureAlert = true
                        }
                    } label: {
                        Label("恢复自动标题", systemImage: "sparkles")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    onDeleteSession(session)
                } label: {
                    Label("删除对话", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("对话操作")
        }
        .background(
            session.id == currentSessionID
                ? AppTheme.softTint
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDeleteSession(session)
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("删除对话")
            .tint(.red)
        }
    }

    private func sessionRowContent(_ session: ConversationSession) -> some View {
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
    }

    private func beginRename(_ session: ConversationSession) {
        renamingSessionID = session.id
        renameDraft = session.title
        showsRenameAlert = true
    }

    private func saveRename() {
        guard let renamingSessionID,
              let session = sessions.first(where: { $0.id == renamingSessionID }),
              normalizedRenameDraft != nil
        else {
            renamingSessionID = nil
            return
        }
        if !onRenameSession(session, renameDraft) {
            showsRenameFailureAlert = true
        }
        self.renamingSessionID = nil
    }
}
