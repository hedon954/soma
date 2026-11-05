import Foundation
import SwiftData

struct CoachTimelineMessage: Equatable, Sendable {
    var id: UUID
    var date: Date
}

struct CoachTimelineRecord: Equatable, Sendable {
    var businessID: Int64
    var recordType: String
    var occurredAt: Date
    var sourceTurnID: UUID?
    var sourceWorkoutSessionID: UUID?
}

struct CoachTimelineItem: Equatable, Identifiable, Sendable {
    enum Payload: Equatable, Sendable {
        case message(UUID)
        case records([AgentRecordReference])
    }

    var id: String
    var occurredAt: Date
    var scrollID: UUID
    var payload: Payload
}

enum CoachTimelineBuilder {
    /// 消息保持原样。没有聊天来源的记录按发生时间插进同一条序列。
    /// 同一次带练的多条训练记录合成一个事件，避免同一事实出现两遍。
    static func build(
        messages: [CoachTimelineMessage],
        records: [CoachTimelineRecord],
        hasEarlierMessages: Bool
    ) -> [CoachTimelineItem] {
        let oldestLoaded = messages.map(\.date).min()
        let external = records.filter { record in
            guard record.sourceTurnID == nil else { return false }
            guard hasEarlierMessages, let oldestLoaded else { return true }
            return record.occurredAt >= oldestLoaded
        }

        var items = messages.map { message in
            CoachTimelineItem(
                id: "message:\(message.id.uuidString)",
                occurredAt: message.date,
                scrollID: message.id,
                payload: .message(message.id)
            )
        }
        items.append(contentsOf: grouped(external))
        return items.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt < rhs.occurredAt
            }
            return lhs.id < rhs.id
        }
    }

    private static func grouped(
        _ records: [CoachTimelineRecord]
    ) -> [CoachTimelineItem] {
        var sessions: [UUID: [CoachTimelineRecord]] = [:]
        var loose: [CoachTimelineRecord] = []
        for record in records {
            if let sessionID = record.sourceWorkoutSessionID {
                sessions[sessionID, default: []].append(record)
            } else {
                loose.append(record)
            }
        }

        var items: [CoachTimelineItem] = []
        for (sessionID, grouped) in sessions {
            let ordered = grouped.sorted(by: recordOrder)
            items.append(
                CoachTimelineItem(
                    id: "workout-session:\(sessionID.uuidString)",
                    occurredAt: ordered.map(\.occurredAt).min() ?? .distantPast,
                    scrollID: sessionID,
                    payload: .records(ordered.map(reference))
                )
            )
        }
        for record in loose {
            items.append(
                CoachTimelineItem(
                    id: "\(record.recordType):\(record.businessID)",
                    occurredAt: record.occurredAt,
                    scrollID: loneScrollID(
                        type: record.recordType,
                        businessID: record.businessID
                    ),
                    payload: .records([reference(record)])
                )
            )
        }
        return items
    }

    private static func reference(
        _ record: CoachTimelineRecord
    ) -> AgentRecordReference {
        AgentRecordReference(
            recordType: record.recordType,
            recordID: record.businessID,
            title: nil
        )
    }

    private static func recordOrder(
        _ lhs: CoachTimelineRecord,
        _ rhs: CoachTimelineRecord
    ) -> Bool {
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt < rhs.occurredAt
        }
        return lhs.businessID < rhs.businessID
    }

    private static func loneScrollID(type: String, businessID: Int64) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in type.utf8.prefix(4).enumerated() {
            bytes[index] = byte
        }
        var value = businessID.bigEndian
        withUnsafeBytes(of: &value) { raw in
            for (index, byte) in raw.enumerated() where index < 8 {
                bytes[8 + index] = byte
            }
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

@MainActor
enum CoachTimelineLoader {
    static func records(
        on day: Date,
        timeZone: TimeZone,
        in context: ModelContext
    ) -> [CoachTimelineRecord] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return []
        }
        var workouts = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        workouts.fetchLimit = 240
        var meals = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        meals.fetchLimit = 50
        var bodies = FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        bodies.fetchLimit = 20

        let workoutRecords = ((try? context.fetch(workouts)) ?? []).filter { !$0.isDailyActivity }
        let mealRecords = (try? context.fetch(meals)) ?? []
        let bodyRecords = (try? context.fetch(bodies)) ?? []
        return workoutRecords.compactMap { entry in
            guard let businessID = entry.businessID else { return nil }
            return CoachTimelineRecord(
                businessID: businessID,
                recordType: ConversationIntent.workout.rawValue,
                occurredAt: entry.date,
                sourceTurnID: entry.sourceTurnID,
                sourceWorkoutSessionID: entry.sourceWorkoutSessionID
            )
        } + mealRecords.compactMap { entry in
            guard let businessID = entry.businessID else { return nil }
            return CoachTimelineRecord(
                businessID: businessID,
                recordType: ConversationIntent.meal.rawValue,
                occurredAt: entry.date,
                sourceTurnID: entry.sourceTurnID,
                sourceWorkoutSessionID: nil
            )
        } + bodyRecords.compactMap { entry in
            guard let businessID = entry.businessID else { return nil }
            return CoachTimelineRecord(
                businessID: businessID,
                recordType: ConversationIntent.body.rawValue,
                occurredAt: entry.date,
                sourceTurnID: entry.sourceTurnID,
                sourceWorkoutSessionID: nil
            )
        }
    }
}
