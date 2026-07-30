import Foundation

struct ConversationContextProjection {
    static let defaultMaximumExchangeCount = 10

    struct Exchange {
        var turnID: UUID
        var userText: String
        var assistantText: String?
        var mediaAttachments: [MediaAttachmentReference]

        var imageAttachmentCount: Int {
            mediaAttachments.count { $0.kind == .image }
        }

        var videoAttachmentCount: Int {
            mediaAttachments.count { $0.kind == .video }
        }
    }

    var exchanges: [Exchange]

    static func make(
        messages: [CoachMessage],
        sessionID: UUID,
        excludingTurnID: UUID?,
        maximumExchangeCount: Int = defaultMaximumExchangeCount
    ) -> ConversationContextProjection {
        guard maximumExchangeCount > 0 else {
            return ConversationContextProjection(exchanges: [])
        }

        let sessionMessages = messages
            .filter { $0.sessionID == sessionID }
            .sorted { $0.date < $1.date }
        let userMessages = sessionMessages
            .filter { message in
                !message.isFromCoach && message.turnID != excludingTurnID
            }
            .suffix(maximumExchangeCount)

        let exchanges = userMessages.map { userMessage in
            let assistantMessage = userMessage.turnID.flatMap { turnID in
                sessionMessages
                    .filter { $0.isFromCoach && $0.turnID == turnID }
                    .max { lhs, rhs in
                        if lhs.attemptNumber == rhs.attemptNumber {
                            return lhs.date < rhs.date
                        }
                        return lhs.attemptNumber < rhs.attemptNumber
                    }
            }
            let assistantText = assistantMessage?.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Exchange(
                turnID: userMessage.turnID ?? userMessage.id,
                userText: userMessage.text,
                assistantText: assistantText?.isEmpty == false ? assistantText : nil,
                mediaAttachments: userMessage.mediaAttachments
            )
        }
        return ConversationContextProjection(exchanges: exchanges)
    }
}
