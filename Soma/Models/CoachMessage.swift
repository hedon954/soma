import Foundation
import SwiftData

@Model
final class CoachMessage {
    var id: UUID
    var date: Date
    var sessionID: UUID?
    var isFromCoach: Bool
    var text: String
    var mediaKindRaw: String = MediaKind.none.rawValue
    var mediaPath: String?
    var mediaAttachmentsData: Data = Data()
    var recordTypeRaw: String?
    var agentTraceID: UUID?
    var agentStatusRaw: String?
    var agentEventsData: Data = Data()
    var agentTurnItemsData: Data = Data()
    var turnID: UUID?
    var attemptNumber: Int = 0
    var locationData: Data = Data()
    var effectiveGymID: UUID?
    /// 最新回复卡片内的用户修订摘要；下一轮作为结构化纠错块注入历史。
    var manualCorrectionSummary: String?

    init(
        date: Date = .now,
        sessionID: UUID? = nil,
        isFromCoach: Bool,
        text: String,
        mediaKind: MediaKind = .none,
        mediaPath: String? = nil,
        mediaAttachments: [MediaAttachmentReference] = [],
        recordType: ConversationIntent? = nil,
        agentTraceID: UUID? = nil,
        agentStatus: AgentTraceStatus? = nil,
        agentEvents: [AgentTraceSpan] = [],
        agentTurnItems: [AgentTurnItem] = [],
        turnID: UUID? = nil,
        attemptNumber: Int = 0,
        location: LocationSnapshot? = nil,
        effectiveGymID: UUID? = nil
    ) {
        id = UUID()
        self.date = date
        self.sessionID = sessionID
        self.isFromCoach = isFromCoach
        self.text = text
        mediaKindRaw = mediaKind.rawValue
        self.mediaPath = mediaPath
        mediaAttachmentsData = MediaAttachmentStorage.encode(mediaAttachments)
        recordTypeRaw = recordType?.rawValue
        self.agentTraceID = agentTraceID
        agentStatusRaw = agentStatus?.rawValue
        agentEventsData = (try? JSONEncoder().encode(agentEvents)) ?? Data()
        agentTurnItemsData = (try? JSONEncoder().encode(agentTurnItems)) ?? Data()
        self.turnID = turnID
        self.attemptNumber = attemptNumber
        locationData = (try? location.map { try JSONEncoder().encode($0) }) ?? Data()
        self.effectiveGymID = effectiveGymID
    }

    func recordManualCorrection(_ summary: String) {
        let line = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        let prior = manualCorrectionSummary?
            .split(separator: "\n")
            .map(String.init) ?? []
        manualCorrectionSummary = (prior + ["- \(line)"])
            .suffix(8)
            .joined(separator: "\n")
    }

    var mediaKind: MediaKind {
        MediaKind(rawValue: mediaKindRaw) ?? .none
    }

    var recordType: ConversationIntent? {
        get { recordTypeRaw.flatMap(ConversationIntent.init(rawValue:)) }
        set { recordTypeRaw = newValue?.rawValue }
    }

    var location: LocationSnapshot? {
        get {
            guard !locationData.isEmpty else { return nil }
            return try? JSONDecoder().decode(LocationSnapshot.self, from: locationData)
        }
        set {
            locationData = (try? newValue.map { try JSONEncoder().encode($0) }) ?? Data()
        }
    }

    var mediaAttachments: [MediaAttachmentReference] {
        get {
            MediaAttachmentStorage.decode(
                mediaAttachmentsData,
                legacyKind: mediaKind,
                legacyPath: mediaPath
            )
        }
        set {
            mediaAttachmentsData = MediaAttachmentStorage.encode(newValue)
            mediaKindRaw = (newValue.first?.kind ?? .none).rawValue
            mediaPath = newValue.first?.path
        }
    }

    var agentStatus: AgentTraceStatus? {
        get { agentStatusRaw.flatMap(AgentTraceStatus.init(rawValue:)) }
        set { agentStatusRaw = newValue?.rawValue }
    }

    var agentEvents: [AgentTraceSpan] {
        (try? JSONDecoder().decode([AgentTraceSpan].self, from: agentEventsData)) ?? []
    }

    var agentTurnItems: [AgentTurnItem] {
        (
            try? JSONDecoder().decode(
                [AgentTurnItem].self,
                from: agentTurnItemsData
            )
        ) ?? []
    }

    func applyAgentEvent(_ event: AgentTraceEvent) {
        var items = agentTurnItems

        switch event {
        case let .reasoningDelta(itemID, delta):
            items.removeAll { $0.kind == .activity }
            if let index = items.firstIndex(where: { $0.id == itemID }) {
                items[index].appendTextDelta(delta)
            } else {
                items.append(AgentTurnItem(
                    id: itemID,
                    sequence: items.count + 1,
                    kind: .reasoning,
                    status: .running,
                    title: "思考过程",
                    text: delta
                ))
            }
        case let .reasoningCompleted(itemID, text, date):
            if let index = items.firstIndex(where: { $0.id == itemID }) {
                items[index].text = text
                items[index].finishText(at: date)
            } else if !text.isEmpty {
                items.append(AgentTurnItem(
                    id: itemID,
                    sequence: items.count + 1,
                    kind: .reasoning,
                    status: .succeeded,
                    title: "思考过程",
                    text: text,
                    startedAt: date,
                    endedAt: date
                ))
            }
        case let .assistantTextDelta(itemID, delta):
            items.removeAll { $0.kind == .activity }
            if let index = items.firstIndex(where: { $0.id == itemID }) {
                items[index].appendTextDelta(delta)
            } else {
                items.append(AgentTurnItem(
                    id: itemID,
                    sequence: items.count + 1,
                    kind: .text,
                    status: .running,
                    text: delta
                ))
            }
        case let .assistantTextCompleted(itemID, date):
            if let index = items.firstIndex(where: { $0.id == itemID }) {
                items[index].finishText(at: date)
            }
        case let .assistantTextDiscarded(itemID, _):
            items.removeAll { $0.id == itemID }
        case let .span(span):
            if span.kind == .model, span.status == .running {
                setAgentActivity(
                    phase: .modelRunning,
                    message: "正在处理请求…",
                    at: span.startedAt,
                    items: &items
                )
                break
            }
            guard span.kind == .skill || span.kind == .tool else { break }
            items.removeAll { $0.kind == .activity }
            if let index = items.firstIndex(where: {
                if let operationID = span.operationID {
                    return $0.operationID == operationID
                }
                return $0.id == span.id
            }) {
                let existingID = items[index].id
                items[index] = AgentTurnItem(
                    span: span,
                    sequence: items[index].sequence
                )
                items[index].id = existingID
            } else {
                items.append(AgentTurnItem(span: span, sequence: items.count + 1))
            }
            applyLegacyAgentEvent(span)
        case let .completed(_, date):
            items.removeAll { $0.kind == .activity || $0.kind == .error }
            for index in items.indices
                where (items[index].kind == .text || items[index].kind == .reasoning)
                && items[index].status == .running
            {
                items[index].finishText(at: date)
            }
        case let .failed(message, _, date):
            items.removeAll { $0.kind == .activity }
            items.removeAll { $0.kind == .error }
            for index in items.indices where items[index].status == .running {
                items[index].fail(message: message, at: date)
            }
            if !items.contains(where: {
                $0.kind == .error && $0.errorMessage == message
            }) {
                items.append(AgentTurnItem(
                    sequence: items.count + 1,
                    kind: .error,
                    status: .failed,
                    title: "执行失败",
                    text: message,
                    startedAt: date,
                    endedAt: date,
                    errorMessage: message
                ))
            }
        }

        agentTurnItemsData = (try? JSONEncoder().encode(items)) ?? agentTurnItemsData
    }

    func setAgentActivity(
        phase: AgentTurnPhase,
        message: String,
        at date: Date = .now
    ) {
        var items = agentTurnItems
        setAgentActivity(
            phase: phase,
            message: message,
            at: date,
            items: &items
        )
        agentTurnItemsData = (try? JSONEncoder().encode(items)) ?? agentTurnItemsData
    }

    func clearAgentActivity() {
        var items = agentTurnItems
        items.removeAll { $0.kind == .activity }
        agentTurnItemsData = (try? JSONEncoder().encode(items)) ?? agentTurnItemsData
    }

    private func setAgentActivity(
        phase: AgentTurnPhase,
        message: String,
        at date: Date,
        items: inout [AgentTurnItem]
    ) {
        if let index = items.firstIndex(where: { $0.kind == .activity }) {
            items[index].phaseRaw = phase.rawValue
            items[index].statusRaw = AgentTraceStatus.running.rawValue
            items[index].title = message
            items[index].text = message
            items[index].endedAt = nil
        } else {
            items.append(AgentTurnItem(
                sequence: items.count + 1,
                kind: .activity,
                status: .running,
                phase: phase,
                title: message,
                text: message,
                startedAt: date
            ))
        }
    }

    func applyAgentEvent(_ span: AgentTraceSpan) {
        applyAgentEvent(.span(span))
    }

    private func applyLegacyAgentEvent(_ incomingSpan: AgentTraceSpan) {
        var span = incomingSpan
        var current = agentEvents
        if let index = current.firstIndex(where: {
            if let operationID = span.operationID {
                return $0.operationID == operationID
            }
            return $0.id == span.id
        }) {
            span.id = current[index].id
            current[index] = span
        } else {
            current.append(span)
        }
        agentEventsData = (try? JSONEncoder().encode(current)) ?? agentEventsData
    }

    func replaceAgentEvents(_ events: [AgentTraceSpan]) {
        agentEventsData = (try? JSONEncoder().encode(events)) ?? agentEventsData
    }

    func replaceAgentTurnItems(_ items: [AgentTurnItem]) {
        var normalized = items
        for index in normalized.indices {
            normalized[index].sequence = index + 1
        }
        agentTurnItemsData = (try? JSONEncoder().encode(normalized)) ?? agentTurnItemsData
    }
}
