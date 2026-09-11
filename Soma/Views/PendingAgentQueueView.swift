import SwiftUI

struct PendingAgentQueueView: View {
    @Environment(\.dismiss) private var dismiss

    let jobs: [AgentJob]
    let isBusy: Bool
    let onRetryAll: () -> Bool
    let onDelete: (AgentJob) async throws -> Void
    let onClear: () async throws -> Void
    let onOpenLLMConfiguration: () -> Void

    @State private var deletionID: UUID?
    @State private var showsClearConfirmation = false
    @State private var actionError: String?
    @State private var isDeleting = false

    private var orderedJobs: [AgentJob] {
        jobs.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if jobs.isEmpty {
                    ContentUnavailableView(
                        "没有暂存信息",
                        systemImage: "tray",
                        description: Text("等待处理的消息会按发送顺序出现在这里。")
                    )
                } else {
                    Section {
                        ForEach(orderedJobs) { job in
                            HStack(alignment: .top, spacing: 12) {
                                PendingAgentQueueRow(job: job)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button(role: .destructive) { deletionID = job.id } label: {
                                    Image(systemName: "trash")
                                        .frame(width: AppTheme.minimumTapTarget, height: AppTheme.minimumTapTarget)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("删除这条暂存消息")
                                .accessibilityIdentifier("pending-delete-\(job.id.uuidString)")
                                .disabled(isBusy || isDeleting)
                            }
                            .swipeActions(allowsFullSwipe: false) {
                                Button("删除", role: .destructive) {
                                    deletionID = job.id
                                }
                                .disabled(isBusy || isDeleting)
                            }
                            .accessibilityAction(named: "删除这条暂存信息") {
                                deletionID = job.id
                            }
                        }
                    } header: {
                        Text("按发送顺序")
                    } footer: {
                        Text("可删除卡住的消息，让后面的消息继续。已保存的训练等记录及其附件会保留。")
                    }
                }

                Section("队列操作") {
                    Button {
                        guard onRetryAll() else {
                            actionError = "暂存队列当前无法重试，请稍后再试。"
                            return
                        }
                        dismiss()
                    } label: {
                        Label("按顺序重试全部", systemImage: "arrow.clockwise")
                    }
                    .disabled(jobs.isEmpty || isBusy || isDeleting)

                    Button {
                        dismiss()
                        onOpenLLMConfiguration()
                    } label: {
                        Label("LLM 配置", systemImage: "sparkles")
                    }

                    Button(role: .destructive) {
                        showsClearConfirmation = true
                    } label: {
                        Label("清空全部暂存", systemImage: "trash")
                    }
                    .disabled(jobs.isEmpty || isBusy || isDeleting)
                }
            }
            .navigationTitle("暂存管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .disabled(isDeleting)
                }
            }
        }
        .confirmationDialog(
            "删除这条暂存信息？",
            isPresented: Binding(
                get: { deletionID != nil },
                set: {
                    if !$0 {
                        deletionID = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let deletionID,
                      let job = jobs.first(where: { $0.id == deletionID })
                else {
                    actionError = "这条暂存信息当前无法删除，请稍后再试。"
                    return
                }
                Task {
                    isDeleting = true
                    defer { isDeleting = false }
                    do {
                        try await onDelete(job)
                        self.deletionID = nil
                    } catch {
                        actionError = AppErrorMessage.message(for: error, operation: .delete)
                    }
                }
            }
            Button("取消", role: .cancel) {
                deletionID = nil
            }
        } message: {
            Text("这条消息会从对话中移除，已保存的记录会保留。后台任务需要先停止；删除后其余消息继续按顺序处理。")
        }
        .confirmationDialog(
            "清空全部暂存信息？",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空全部", role: .destructive) {
                Task {
                    isDeleting = true
                    defer { isDeleting = false }
                    do {
                        try await onClear()
                        dismiss()
                    } catch {
                        actionError = AppErrorMessage.message(for: error, operation: .delete)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有暂存消息都会从对话中移除，且不可撤销。已保存的训练等记录及其附件会保留。")
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { actionError != nil },
                set: {
                    if !$0 {
                        actionError = nil
                    }
                }
            )
        ) {
            Button("知道了", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "请稍后再试。")
        }
        .overlay {
            if isDeleting {
                ProgressView("正在删除…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .interactiveDismissDisabled(isDeleting)
    }
}

private struct PendingAgentQueueRow: View {
    let job: AgentJob

    private var summary: String {
        let text = job.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
        let count = job.mediaAttachments.count
        return count == 0 ? "未填写文字" : "包含 \(count) 项照片或视频"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(summary)
                .font(.body)
                .lineLimit(3)
            HStack(spacing: 8) {
                Label(job.state.pendingDisplayTitle, systemImage: job.state.pendingDisplayIcon)
                Text(job.createdAt.formatted(date: .abbreviated, time: .shortened))
                if !job.mediaAttachments.isEmpty {
                    Label("\(job.mediaAttachments.count)", systemImage: "paperclip")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private extension AgentJobState {
    var pendingDisplayTitle: String {
        switch self {
        case .waitingForUser: "等待你恢复"
        case .waitingForNetwork: "等待网络"
        case .queued: "等待前一条"
        default: "已暂存"
        }
    }

    var pendingDisplayIcon: String {
        switch self {
        case .waitingForUser: "person.crop.circle.badge.exclamationmark"
        case .waitingForNetwork: "wifi.exclamationmark"
        case .queued: "clock"
        default: "tray.full"
        }
    }
}
