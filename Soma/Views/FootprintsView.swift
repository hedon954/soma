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
                    LazyVStack(spacing: 0) {
                        ForEach(footprints) { message in
                            footprintDestination(for: message)
                            if message.id != footprints.last?.id {
                                Divider()
                                    .padding(.leading, 54)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
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

private struct FootprintRow: View {
    let message: CoachMessage
    let resultLabel: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.softTint)
                Image(systemName: "person.fill")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("我")
                        .font(.headline)
                    Spacer()
                    Text(message.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                if !message.mediaAttachments.isEmpty {
                    StoredMediaStrip(attachments: message.mediaAttachments)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    if let location = message.location {
                        Label(location.displayName, systemImage: "location.fill")
                            .lineLimit(1)
                    }
                    if let resultLabel {
                        Label(resultLabel, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.tint)
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }
}
