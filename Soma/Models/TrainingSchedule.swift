import Foundation
import SwiftData

enum TrainingScheduleStatus: String, Codable, Sendable {
    case active
    case archived
}

struct TrainingScheduleSlotValue: Codable, Equatable, Sendable {
    var kindRaw: String
    var programID: UUID?
    var id: UUID?
    var contents: [TrainingContentSource]?

    static func rest() -> Self {
        Self(kindRaw: "rest", programID: nil)
    }

    static func course(_ programID: UUID) -> Self {
        Self(kindRaw: "course", programID: programID)
    }

    static func training(_ contents: [TrainingContentSource], id: UUID = UUID()) -> Self {
        Self(kindRaw: "training", programID: nil, id: id, contents: contents)
    }

    var program: UUID? {
        if kindRaw == "course" {
            return programID
        }
        return contents?.isEmpty == false ? id : nil
    }
}

struct TrainingScheduleClosureValue: Codable, Equatable, Sendable {
    var dueDay: Date
    var kindRaw: String

    static func rest(on day: Date) -> Self {
        Self(dueDay: day, kindRaw: "rest")
    }

    static func skipped(on day: Date) -> Self {
        Self(dueDay: day, kindRaw: "skipped")
    }
}

@Model
final class TrainingSchedule: BusinessIdentifiedModel {
    var id: UUID
    var businessID: Int64?
    var name: String
    var statusRaw: String
    var anchorDate: Date
    var reanchorRequired: Bool
    var slotsData: Data
    var closuresData: Data
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        status: TrainingScheduleStatus = .active,
        anchorDate: Date,
        reanchorRequired: Bool = false,
        slots: [TrainingScheduleSlotValue],
        closures: [TrainingScheduleClosureValue] = [],
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        statusRaw = status.rawValue
        self.anchorDate = anchorDate
        self.reanchorRequired = reanchorRequired
        slotsData = TrainingScheduleCoding.encode(slots)
        closuresData = TrainingScheduleCoding.encode(closures)
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    var status: TrainingScheduleStatus {
        get { TrainingScheduleStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var slots: [TrainingScheduleSlotValue] {
        get { TrainingScheduleCoding.decode(slotsData) ?? [] }
        set { slotsData = TrainingScheduleCoding.encode(newValue) }
    }

    var closures: [TrainingScheduleClosureValue] {
        get { TrainingScheduleCoding.decode(closuresData) ?? [] }
        set { closuresData = TrainingScheduleCoding.encode(newValue) }
    }
}

enum TrainingScheduleCoding {
    static func encode(_ value: some Encodable) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
