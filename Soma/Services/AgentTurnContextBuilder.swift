import Foundation
import SwiftData

@MainActor
enum AgentTurnContextBuilder {
    static func build(
        turnID: UUID,
        userText: String,
        hasCurrentMedia: Bool,
        turnSentAt: Date,
        businessSummary: String,
        sessionID: UUID,
        in context: ModelContext,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> AgentTurnContextEnvelope {
        let messages = (
            try? context.fetch(
                FetchDescriptor<CoachMessage>(
                    sortBy: [SortDescriptor(\.date)]
                )
            )
        ) ?? []
        let projection = ConversationContextProjection.make(
            messages: messages,
            sessionID: sessionID,
            excludingTurnID: turnID
        )
        let selectedTurnIDs = HistoricalMediaSelectionPolicy.selectedTurnIDs(
            currentText: userText,
            hasCurrentMedia: hasCurrentMedia,
            exchanges: projection.exchanges
        )
        return AgentTurnContextEnvelope(
            trustedTime: TrustedTurnContext.make(
                turnSentAt: turnSentAt,
                attemptStartedAt: turnSentAt,
                timeZone: timeZone,
                calendar: calendar
            ),
            businessSummary: businessSummary,
            recentExchanges: projection.exchanges.map {
                AgentTurnContextExchange(
                    turnID: $0.turnID,
                    date: $0.date,
                    userText: $0.userText,
                    assistantText: $0.assistantText,
                    mediaAttachments: $0.mediaAttachments
                )
            },
            factSummary: AgentCrossTurnFactSummary.recentMutationFacts(
                sessionID: sessionID,
                excludingTurnID: turnID,
                in: context
            ),
            olderDigest: AgentCrossTurnFactSummary.olderTurnDigest(
                messages: messages,
                sessionID: sessionID,
                excludingTurnID: turnID
            ),
            selectedHistoricalTurnIDs: selectedTurnIDs
        )
    }
}
