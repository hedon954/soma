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
        effectiveBusinessDate: Date? = nil,
        sessionID: UUID,
        in context: ModelContext,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> AgentTurnContextEnvelope {
        let messages = ConversationContextHistory.messages(sessionID: sessionID, in: context)
        var sessionDescriptor = FetchDescriptor<ConversationSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        sessionDescriptor.fetchLimit = 1
        let session = try? context.fetch(sessionDescriptor).first
        let effectiveTimeZone = session?.businessTimeZone ?? timeZone
        let turnBusinessDate = effectiveBusinessDate ?? BusinessDateResolver.turnBusinessDate(
            in: userText,
            sessionBusinessDate: session?.effectiveBusinessDate ?? turnSentAt,
            turnSentAt: turnSentAt,
            timeZone: effectiveTimeZone
        )
        let projection = ConversationContextProjection.make(
            messages: messages,
            sessionID: sessionID,
            excludingTurnID: turnID,
            turnContexts: ConversationContextHistory.trustedTimes(sessionID: sessionID, in: context),
            canonicalTurns: ConversationContextHistory.canonicalTurns(sessionID: sessionID, in: context)
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
                businessDate: turnBusinessDate,
                timeZone: effectiveTimeZone,
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
            olderDigest: nil,
            selectedHistoricalTurnIDs: selectedTurnIDs
        )
    }
}
