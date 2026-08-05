import Foundation
import SwiftData

enum AgentMutationReceiptStatus: String, Codable, Sendable {
    case pending
    case committed
    case failed
}

@Model
final class AgentMutationReceipt {
    @Attribute(.unique) var key: String
    var turnID: UUID
    var signature: String
    var resultData: Data
    var createdAt: Date
    /// ADR 0049：pending → committed / failed；失败不阻挡同键重试。
    var statusRaw: String = AgentMutationReceiptStatus.committed.rawValue

    init(
        turnID: UUID,
        signature: String,
        result: AgentToolResult? = nil,
        status: AgentMutationReceiptStatus = .pending,
        createdAt: Date = .now
    ) {
        key = Self.key(turnID: turnID, signature: signature)
        self.turnID = turnID
        self.signature = signature
        if let result {
            resultData = (try? JSONEncoder().encode(result)) ?? Data()
        } else {
            resultData = Data()
        }
        self.createdAt = createdAt
        statusRaw = status.rawValue
    }

    var status: AgentMutationReceiptStatus {
        get { AgentMutationReceiptStatus(rawValue: statusRaw) ?? .committed }
        set { statusRaw = newValue.rawValue }
    }

    var result: AgentToolResult? {
        get { try? JSONDecoder().decode(AgentToolResult.self, from: resultData) }
        set {
            resultData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    static func key(turnID: UUID, signature: String) -> String {
        "\(turnID.uuidString)|\(signature)"
    }
}

@MainActor
enum AgentMutationStore {
    static func execute(
        _ call: AgentToolCall,
        turnID: UUID,
        in context: ModelContext,
        operation: () -> AgentToolResult
    ) -> AgentToolResult {
        guard call.name.isMutation else { return operation() }
        let key = AgentMutationReceipt.key(
            turnID: turnID,
            signature: call.signature
        )
        let descriptor = FetchDescriptor<AgentMutationReceipt>(
            predicate: #Predicate { $0.key == key }
        )
        if let existing = try? context.fetch(descriptor).first {
            switch existing.status {
            case .committed:
                if let result = existing.result {
                    return result
                }
            case .failed, .pending:
                context.delete(existing)
                try? context.save()
            }
        }

        let receipt = AgentMutationReceipt(
            turnID: turnID,
            signature: call.signature,
            status: .pending
        )
        context.insert(receipt)
        try? context.save()

        let result = operation()
        if result.ok {
            receipt.status = .committed
            receipt.result = result
        } else {
            receipt.status = .failed
            receipt.result = result
            // 失败不挡同键重试：删掉回执，留给下一次 Attempt。
            context.delete(receipt)
        }
        try? context.save()
        return result
    }
}

enum ConversationTurnProjection {
    static func successfulTurnIDs(in messages: [CoachMessage]) -> Set<UUID> {
        Set(messages.compactMap { message in
            guard message.isFromCoach, message.agentStatus == .succeeded else {
                return nil
            }
            return message.turnID
        })
    }

    static func userMessage(
        for turnID: UUID,
        in messages: [CoachMessage]
    ) -> CoachMessage? {
        messages.first { !$0.isFromCoach && $0.turnID == turnID }
    }

    static func latestAttempt(
        for turnID: UUID,
        in messages: [CoachMessage]
    ) -> CoachMessage? {
        messages
            .filter { $0.isFromCoach && $0.turnID == turnID }
            .max {
                if $0.attemptNumber == $1.attemptNumber {
                    return $0.date < $1.date
                }
                return $0.attemptNumber < $1.attemptNumber
            }
    }

    static func canRetry(
        _ message: CoachMessage,
        in messages: [CoachMessage]
    ) -> Bool {
        guard message.isFromCoach,
              [.failed, .cancelled].contains(message.agentStatus),
              let turnID = message.turnID,
              latestAttempt(for: turnID, in: messages)?.id == message.id
        else {
            return false
        }
        return !successfulTurnIDs(in: messages).contains(turnID)
    }
}

extension DataIntegrityRepair {
    static func backfillConversationTurns(in context: ModelContext) {
        let messages = (
            try? context.fetch(
                FetchDescriptor<CoachMessage>(
                    sortBy: [SortDescriptor(\.date)]
                )
            )
        ) ?? []
        guard messages.contains(where: { $0.turnID == nil }) else { return }
        let traces = (try? context.fetch(FetchDescriptor<AgentTrace>())) ?? []
        let traceByID = Dictionary(uniqueKeysWithValues: traces.map { ($0.id, $0) })
        let grouped = Dictionary(grouping: messages) {
            $0.sessionID?.uuidString ?? "legacy-without-session"
        }
        var changed = false

        for sessionMessages in grouped.values {
            var activeTurnID: UUID?
            var attemptNumber = 0
            for message in sessionMessages.sorted(by: { $0.date < $1.date }) {
                if !message.isFromCoach {
                    activeTurnID = message.turnID ?? UUID()
                    attemptNumber = 0
                    if message.turnID == nil {
                        message.turnID = activeTurnID
                        changed = true
                    }
                    continue
                }

                guard let turnID = message.turnID ?? activeTurnID else { continue }
                attemptNumber += 1
                if message.turnID == nil {
                    message.turnID = turnID
                    changed = true
                }
                if message.attemptNumber == 0 {
                    message.attemptNumber = attemptNumber
                    changed = true
                }
                if message.agentStatus == nil {
                    if let traceID = message.agentTraceID,
                       let trace = traceByID[traceID]
                    {
                        message.agentStatus = trace.status
                    } else {
                        message.agentStatus = legacyStatus(for: message)
                    }
                    changed = true
                }
                if let traceID = message.agentTraceID,
                   let trace = traceByID[traceID]
                {
                    if trace.turnID == nil {
                        trace.turnID = turnID
                        changed = true
                    }
                    if trace.attemptNumber == 1, attemptNumber > 1 {
                        trace.attemptNumber = attemptNumber
                        changed = true
                    }
                }
            }
        }

        if changed {
            try? context.save()
        }
    }

    private static func legacyStatus(for message: CoachMessage) -> AgentTraceStatus {
        let normalized = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("这次没有处理成功")
            || message.agentTurnItems.contains(where: { $0.kind == .error })
        {
            return .failed
        }
        return .succeeded
    }
}
