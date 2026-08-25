import Foundation
import SwiftData

enum AgentTraceStatus: String, Codable, CaseIterable, Sendable {
    case running
    case succeeded
    case failed
    case cancelled

    var title: String {
        switch self {
        case .running: "执行中"
        case .succeeded: "成功"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
    }
}

enum AgentTraceSpanKind: String, Codable, Hashable, Sendable {
    case model
    case skill
    case tool
    case output

    var title: String {
        switch self {
        case .model: "模型"
        case .skill: "Skill"
        case .tool: "工具"
        case .output: "结果"
        }
    }
}

struct AgentTraceSpan: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var sequence: Int
    var step: Int?
    var kindRaw: String
    var title: String
    var statusRaw: String
    var startedAt: Date
    var endedAt: Date
    var input: String?
    var output: String?
    var metadata: String?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        sequence: Int = 0,
        step: Int? = nil,
        kind: AgentTraceSpanKind,
        title: String,
        status: AgentTraceStatus,
        startedAt: Date,
        endedAt: Date,
        input: String? = nil,
        output: String? = nil,
        metadata: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.step = step
        kindRaw = kind.rawValue
        self.title = title
        statusRaw = status.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.input = input
        self.output = output
        self.metadata = metadata
        self.errorMessage = errorMessage
    }

    var kind: AgentTraceSpanKind {
        AgentTraceSpanKind(rawValue: kindRaw) ?? .output
    }

    var status: AgentTraceStatus {
        AgentTraceStatus(rawValue: statusRaw) ?? .failed
    }

    var durationMilliseconds: Double {
        max(0, endedAt.timeIntervalSince(startedAt) * 1000)
    }
}

enum AgentTraceEvent: Equatable, Sendable {
    case span(AgentTraceSpan)
    case assistantTextDelta(itemID: UUID, delta: String)
    case assistantTextCompleted(itemID: UUID, at: Date)
    case completed(answer: String, at: Date)
    case failed(message: String, cancelled: Bool, at: Date)
}

@Model
final class AgentTrace {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var statusRaw: String
    var provider: String
    var model: String
    var endpoint: String
    var dataSpaceRaw: String
    var userInput: String
    var contextSnapshot: String
    var mediaKindRaw: String
    var imageCount: Int
    var imageAttachmentCount: Int = 0
    var videoAttachmentCount: Int = 0
    var finalAnswer: String?
    var errorMessage: String?
    var spansData: Data
    var turnID: UUID?
    var attemptNumber: Int = 1

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        provider: String,
        model: String,
        endpoint: String,
        dataSpaceRaw: String,
        userInput: String,
        contextSnapshot: String,
        mediaKind: MediaKind,
        imageCount: Int,
        imageAttachmentCount: Int? = nil,
        videoAttachmentCount: Int? = nil,
        turnID: UUID? = nil,
        attemptNumber: Int = 1
    ) {
        self.id = id
        self.startedAt = startedAt
        statusRaw = AgentTraceStatus.running.rawValue
        self.provider = provider
        self.model = model
        self.endpoint = endpoint
        self.dataSpaceRaw = dataSpaceRaw
        self.userInput = userInput
        self.contextSnapshot = contextSnapshot
        mediaKindRaw = mediaKind.rawValue
        self.imageCount = imageCount
        self.imageAttachmentCount = imageAttachmentCount
            ?? (mediaKind == .image ? 1 : 0)
        self.videoAttachmentCount = videoAttachmentCount
            ?? (mediaKind == .video ? 1 : 0)
        self.turnID = turnID
        self.attemptNumber = attemptNumber
        spansData = (try? JSONEncoder().encode([AgentTraceSpan]())) ?? Data()
    }

    var status: AgentTraceStatus {
        get { AgentTraceStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var mediaKind: MediaKind {
        MediaKind(rawValue: mediaKindRaw) ?? .none
    }

    var spans: [AgentTraceSpan] {
        (try? JSONDecoder().decode([AgentTraceSpan].self, from: spansData)) ?? []
    }

    var durationMilliseconds: Double? {
        endedAt.map { max(0, $0.timeIntervalSince(startedAt) * 1000) }
    }

    func apply(_ event: AgentTraceEvent) {
        switch event {
        case var .span(span):
            var current = spans
            if let index = current.firstIndex(where: { $0.id == span.id }) {
                span.sequence = current[index].sequence
                current[index] = span
            } else {
                span.sequence = current.count + 1
                current.append(span)
            }
            spansData = (try? JSONEncoder().encode(current)) ?? spansData
        case .assistantTextDelta, .assistantTextCompleted:
            break
        case let .completed(answer, date):
            status = .succeeded
            endedAt = date
            finalAnswer = answer
            errorMessage = nil
        case let .failed(message, cancelled, date):
            status = cancelled ? .cancelled : .failed
            endedAt = date
            errorMessage = message
        }
    }

    func replaceSpans(_ newSpans: [AgentTraceSpan]) {
        var normalized = newSpans
        for index in normalized.indices {
            normalized[index].sequence = index + 1
        }
        spansData = (try? JSONEncoder().encode(normalized)) ?? spansData
    }
}
