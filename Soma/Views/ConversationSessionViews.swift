import SwiftData
import SwiftUI

struct ConversationSessionDrawer: View {
    @Environment(ConversationSessionHistory.self) private var history

    @Environment(\.modelContext) private var modelContext
    let currentSessionID: UUID?
    let isProcessing: Bool
    let onNewSession: () -> Void
    let onSelectSession: (ConversationSession) -> Void
    let onRenameSession: (ConversationSession, String) -> Bool
    let onRestoreAutomaticTitle: (ConversationSession) -> Bool
    let onDeleteSession: (ConversationSession) -> Void

    private var sessions: [ConversationSession] {
        history.sessions
    }

    @State private var renamingSessionID: UUID?
    @State private var renameDraft = ""
    @State private var showsRenameAlert = false
    @State private var showsRenameFailureAlert = false

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

            if let errorMessage = history.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage).font(.callout)
                    Button("重试") { history.loadNextPage(in: modelContext) }
                }
                .padding(.horizontal, 18)
            }
            if sessions.isEmpty, history.errorMessage == nil {
                ContentUnavailableView(
                    "暂无对话",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("点击右上角开始新对话。")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(sessions) { session in
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
                    if history.hasMore, history.errorMessage == nil {
                        Button("加载更早对话") {
                            history.loadNextPage(in: modelContext)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                    }
                }
                .accessibilityIdentifier("coach-session-history")
                .accessibilityValue(AppTestRuntime.isRunning
                    ? "count=\(sessions.count),fetches=\(history.pageFetchCount)"
                    : "已加载 \(sessions.count) 个对话")
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
        .task {
            history.loadIfNeeded(in: modelContext)
        }
        .alert("重命名对话", isPresented: $showsRenameAlert) {
            TextField("对话标题", text: $renameDraft)
            Button("取消", role: .cancel) {
                renamingSessionID = nil
            }
            if renamingSession?.isUsingDateTitle == false {
                Button("恢复日期标题") {
                    restoreAutomaticTitle()
                }
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

    private var renamingSession: ConversationSession? {
        guard let renamingSessionID else { return nil }
        return sessions.first { $0.id == renamingSessionID }
    }

    private func sessionListRow(
        _ session: ConversationSession
    ) -> some View {
        Button {
            onSelectSession(session)
        } label: {
            sessionRowContent(session)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in beginRename(session) }
        )
        .accessibilityHint(
            session.id == currentSessionID
                ? "当前对话，长按标题可重命名"
                : "切换后可继续对话，长按标题可重命名"
        )
        .accessibilityValue(session.id == currentSessionID ? "当前对话" : "")
        .accessibilityAction(named: "重命名对话") {
            beginRename(session)
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

    private func sessionRowContent(
        _ session: ConversationSession
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
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
            Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
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

    private func restoreAutomaticTitle() {
        guard let session = renamingSession else { return }
        if !onRestoreAutomaticTitle(session) {
            showsRenameFailureAlert = true
        }
        renamingSessionID = nil
    }
}
