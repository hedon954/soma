import SwiftData
import SwiftUI

struct FootprintsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataSpaceController.self) private var dataSpace
    @Environment(ConversationSessionController.self) private var conversationSessions
    @Query(sort: \CoachMessage.date, order: .reverse)
    private var messages: [CoachMessage]
    @Query(sort: \ConversationSession.startedAt, order: .reverse)
    private var sessions: [ConversationSession]

    private var footprints: [CoachMessage] {
        let successful = ConversationTurnProjection.successfulTurnIDs(
            in: messages
        )
        return messages.filter {
            !$0.isFromCoach
                && $0.turnID.map(successful.contains) == true
        }
    }

    var body: some View {
        Group {
            if footprints.isEmpty {
                ContentUnavailableView(
                    "还没有足迹",
                    systemImage: "shoeprints.fill",
                    description: Text("Agent 成功处理的文字、照片和视频会按原样出现在这里。")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(footprints) { message in
                            footprintDestination(for: message)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                }
            }
        }
        .appPageBackground()
        .navigationTitle("足迹")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func footprintDestination(
        for message: CoachMessage
    ) -> some View {
        if let session = message.sessionID.flatMap({ id in
            sessions.first { $0.id == id }
        }) {
            Button {
                conversationSessions.select(
                    session,
                    dataSpace: dataSpace.activeSpace
                )
                NotificationCenter.default.post(
                    name: .openCoachConversation,
                    object: nil
                )
            } label: {
                FootprintRow(
                    message: message,
                    resultLabel: resultLabel(for: message)
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                removeLocationButton(for: message)
            }
        } else {
            FootprintRow(
                message: message,
                resultLabel: resultLabel(for: message)
            )
            .contextMenu {
                removeLocationButton(for: message)
            }
        }
    }

    @ViewBuilder
    private func removeLocationButton(
        for message: CoachMessage
    ) -> some View {
        if message.location != nil {
            Button("移除位置", systemImage: "location.slash", role: .destructive) {
                message.location = nil
                try? modelContext.save()
            }
        }
    }

    private func resultLabel(for message: CoachMessage) -> String? {
        guard let turnID = message.turnID else { return nil }
        return messages
            .filter {
                $0.isFromCoach
                    && $0.turnID == turnID
                    && $0.agentStatus == .succeeded
            }
            .max(by: { $0.attemptNumber < $1.attemptNumber })?
            .recordType?
            .recordedLabel
    }
}

extension Notification.Name {
    static let openCoachConversation = Notification.Name(
        "Soma.openCoachConversation"
    )
    static let prefillCoachDraft = Notification.Name(
        "Soma.prefillCoachDraft"
    )
}

/// 朋友圈式 feed 卡片：头像 + 昵称在左上，正文、九宫格媒体、
/// 位置与时间沿内容列对齐。
private struct FootprintRow: View {
    let message: CoachMessage
    let resultLabel: String?
    @State private var isTextExpanded = false

    private static let collapsedLineLimit = 5
    /// Heuristic for "long" content that deserves a collapse affordance.
    private var isLongText: Bool {
        let text = message.text
        return text.count > 160
            || text.filter { $0 == "\n" }.count >= Self.collapsedLineLimit
    }

    var body: some View {
        AppCard {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppTheme.softTint)
                    Image(systemName: "person.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.tint)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 8) {
                    Text("我")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.tint)

                    if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(message.text)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineSpacing(3)
                            .lineLimit(isTextExpanded ? nil : Self.collapsedLineLimit)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        if isLongText {
                            Button(isTextExpanded ? "收起" : "全文") {
                                withAnimation(.snappy) {
                                    isTextExpanded.toggle()
                                }
                            }
                            .font(.subheadline.weight(.medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(AppTheme.tint)
                        }
                    }

                    if !message.mediaAttachments.isEmpty {
                        FootprintMediaGrid(attachments: message.mediaAttachments)
                    }

                    if let location = message.location {
                        Label(location.displayName, systemImage: "location.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.tint)
                            .lineLimit(1)
                    }

                    HStack(spacing: 10) {
                        Text(relativeDateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let resultLabel {
                            Label(resultLabel, systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.tint)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private var relativeDateText: String {
        if Calendar.current.isDateInToday(message.date) {
            return message.date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(message.date) {
            return "昨天 " + message.date.formatted(date: .omitted, time: .shortened)
        }
        return message.date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// 朋友圈式媒体宫格：单图放大、双图/四图两列、其余三列方格。
private struct FootprintMediaGrid: View {
    let attachments: [MediaAttachmentReference]

    @Namespace private var mediaZoomNamespace
    @State private var presentedAttachment: MediaAttachmentReference?

    private var columnCount: Int {
        switch attachments.count {
        case 1: 1
        case 2, 4: 2
        default: 3
        }
    }

    private var tileSize: CGFloat {
        attachments.count == 1 ? 184 : 88
    }

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(tileSize), spacing: 5),
                count: columnCount
            ),
            alignment: .leading,
            spacing: 5
        ) {
            ForEach(attachments) { attachment in
                Button {
                    presentedAttachment = attachment
                } label: {
                    tile(attachment)
                        .frame(width: tileSize, height: tileSize)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .mediaZoomSource(id: attachment.id, in: mediaZoomNamespace)
                .accessibilityLabel(
                    attachment.kind == .video ? "播放视频" : "查看照片"
                )
            }
        }
        .mediaViewerCover(
            item: $presentedAttachment,
            attachments: attachments,
            namespace: mediaZoomNamespace
        )
    }

    @ViewBuilder
    private func tile(_ attachment: MediaAttachmentReference) -> some View {
        if attachment.kind == .video {
            VideoPosterView(path: attachment.path)
        } else {
            LocalImageView(path: attachment.path)
        }
    }
}
