import Foundation
import SwiftData

@Model
final class ConversationCompactionSummary {
    @Attribute(.unique) var sessionKey: String
    var id: UUID
    var sessionID: UUID
    var summary: String
    var coveredTurnIDsData: Data
    var strategyRaw: String
    var updatedAt: Date

    init(
        sessionID: UUID,
        summary: String,
        coveredTurnIDs: [UUID],
        strategy: ConversationCompactionStrategy,
        updatedAt: Date = .now
    ) {
        id = UUID()
        self.sessionID = sessionID
        sessionKey = sessionID.uuidString.lowercased()
        self.summary = summary
        coveredTurnIDsData = (try? JSONEncoder().encode(coveredTurnIDs)) ?? Data()
        strategyRaw = strategy.rawValue
        self.updatedAt = updatedAt
    }

    var coveredTurnIDs: [UUID] {
        get {
            (try? JSONDecoder().decode([UUID].self, from: coveredTurnIDsData)) ?? []
        }
        set {
            coveredTurnIDsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var strategy: ConversationCompactionStrategy {
        get { ConversationCompactionStrategy(rawValue: strategyRaw) ?? .deterministic }
        set { strategyRaw = newValue.rawValue }
    }
}

enum ConversationCompactionStrategy: String, Codable, Sendable {
    case smallModel = "small_model"
    case standardModel = "standard_model"
    case deterministic
}
