import Foundation
import SwiftData

@MainActor
enum ConversationProcessingContextFactory {
    static func make(
        sessionID: UUID,
        dataSpace: DataSpace,
        ai: AIService,
        in context: ModelContext
    ) -> ConversationProcessingContext? {
        var descriptor = FetchDescriptor<ConversationSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        descriptor.fetchLimit = 1
        guard let session = try? context.fetch(descriptor).first else {
            return nil
        }
        let gyms = (
            try? context.fetch(
                FetchDescriptor<GymProfile>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        let equipment = (
            try? context.fetch(
                FetchDescriptor<GymEquipment>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        return ConversationProcessingContext(
            structuredContext: structuredContext(
                gyms: gyms,
                equipment: equipment,
                sessionID: session.id,
                businessDate: session.effectiveBusinessDate,
                timeZone: session.businessTimeZone,
                in: context
            ),
            session: session,
            dataSpace: dataSpace,
            gyms: gyms,
            equipment: equipment,
            ai: ai,
            modelContext: context
        )
    }

    static func structuredContext(in context: ModelContext) -> String {
        let gyms = (
            try? context.fetch(
                FetchDescriptor<GymProfile>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        let equipment = (
            try? context.fetch(
                FetchDescriptor<GymEquipment>(
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
        ) ?? []
        return structuredContext(
            gyms: gyms,
            equipment: equipment,
            sessionID: nil,
            businessDate: .now,
            timeZone: .current,
            in: context
        )
    }

    private static func structuredContext(
        gyms: [GymProfile],
        equipment: [GymEquipment],
        sessionID: UUID?,
        businessDate: Date,
        timeZone: TimeZone,
        in context: ModelContext
    ) -> String {
        AgentContextPackBuilder.build(
            gyms: gyms,
            equipment: equipment,
            in: context,
            sessionID: sessionID,
            businessDate: businessDate,
            timeZone: timeZone
        )
    }
}
