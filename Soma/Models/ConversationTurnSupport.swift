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

    static func executeAsync(
        _ call: AgentToolCall,
        turnID: UUID,
        in context: ModelContext,
        operation: () async throws -> AgentToolResult
    ) async throws -> AgentToolResult {
        guard call.name.isMutation else { return try await operation() }
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

        do {
            let result = try await operation()
            if result.ok {
                receipt.status = .committed
                receipt.result = result
            } else {
                context.delete(receipt)
            }
            try? context.save()
            return result
        } catch {
            context.delete(receipt)
            try? context.save()
            throw error
        }
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
        in messages: [CoachMessage],
        job: AgentJob? = nil
    ) -> Bool {
        retryableAssistantMessageIDs(
            in: messages,
            jobByResponseMessageID: job.map { [message.id: $0] } ?? [:]
        ).contains(message.id)
    }

    /// 一次线性扫描生成整页可重试集合，供聊天气泡按 ID O(1) 读取。
    static func retryableAssistantMessageIDs(
        in messages: [CoachMessage],
        jobByResponseMessageID: [UUID: AgentJob]
    ) -> Set<UUID> {
        let successful = successfulTurnIDs(in: messages)
        var latestByTurnID: [UUID: CoachMessage] = [:]
        for message in messages where message.isFromCoach {
            guard let turnID = message.turnID else { continue }
            guard let existing = latestByTurnID[turnID] else {
                latestByTurnID[turnID] = message
                continue
            }
            if message.attemptNumber > existing.attemptNumber
                || (message.attemptNumber == existing.attemptNumber
                    && message.date > existing.date)
            {
                latestByTurnID[turnID] = message
            }
        }

        return Set(latestByTurnID.values.compactMap { message in
            guard let turnID = message.turnID,
                  !successful.contains(turnID),
                  [.failed, .cancelled].contains(message.agentStatus)
            else {
                return nil
            }
            if let job = jobByResponseMessageID[message.id] {
                return job.state.awaitsAutomaticRecovery ? nil : message.id
            }
            // 没有 Job 时，取消态表示系统仍会续跑；只有失败态才交给用户手动重试。
            return message.agentStatus == .failed ? message.id : nil
        })
    }
}
