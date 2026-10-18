import Foundation
import SwiftData

struct TrainingScheduleDraftSlotArgument: Codable, Equatable, Sendable {
    var kind: String
    var contents: [TrainingContentArgument]? = nil
}

struct TrainingScheduleDraftSlotPayload: Codable, Equatable, Sendable {
    var title: String
    var value: TrainingScheduleSlotValue
}

struct TrainingScheduleDraftPayload: Codable, Equatable, Sendable {
    var name: String
    var anchorDate: String?
    var slots: [TrainingScheduleDraftSlotPayload]
    var dayTitles: [String]

    enum CodingKeys: String, CodingKey {
        case name, slots, dayTitles
        case anchorDate = "anchor_date"
    }

    static func from(_ result: AgentToolResult) -> Self? {
        guard result.ok, result.code == code, let data = result.data,
              let encoded = try? JSONEncoder().encode(data)
        else { return nil }
        return try? JSONDecoder().decode(Self.self, from: encoded)
    }

    static func from(items: [AgentTurnItem]) -> Self? {
        for item in items.reversed() where item.kind == .tool && item.status == .succeeded {
            guard let output = item.output,
                  let result = try? JSONDecoder().decode(AgentToolResult.self, from: Data(output.utf8)),
                  let payload = Self.from(result)
            else { continue }
            return payload
        }
        return nil
    }

    func editorDraft(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TrainingScheduleEditorDraft {
        let anchor = anchorDate.flatMap {
            TrainingScheduleDraftDates.parse($0, calendar: calendar)
        } ?? TrainingScheduleDraftDates.startOfDay(now, calendar: calendar)
        let resolved = slots.map(\.value)
        return TrainingScheduleEditorDraft(
            name: name,
            anchor: anchor,
            slots: resolved.isEmpty ? [.rest()] : resolved
        )
    }

    static let code = "training_schedule_draft"
}

struct TrainingScheduleEditorDraft: Equatable, Sendable {
    var name: String
    var anchor: Date
    var slots: [TrainingScheduleSlotValue]
}

enum TrainingScheduleDraftDates {
    static func parse(_ value: String, calendar: Calendar = .current) -> Date? {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1 ... 12).contains(month),
              (1 ... 31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day
        else { return nil }
        return calendar.startOfDay(for: date)
    }

    static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func label(_ value: String?) -> String {
        value ?? "今天"
    }
}

@MainActor
enum TrainingScheduleDraftTool {
    static func propose(
        name: String?,
        anchorDate: String?,
        slots: [TrainingScheduleDraftSlotArgument]?,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> AgentToolResult {
        let before = scheduleCount(in: context)
        let result = makePayload(
            name: name,
            anchorDate: anchorDate,
            slots: slots,
            in: context,
            calendar: calendar
        )
        guard scheduleCount(in: context) == before else {
            return .failure("计划草稿不能写入训练计划。", code: "invalid_tool_arguments")
        }
        return result
    }

    private static func makePayload(
        name: String?,
        anchorDate: String?,
        slots: [TrainingScheduleDraftSlotArgument]?,
        in context: ModelContext,
        calendar: Calendar
    ) -> AgentToolResult {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return .failure("计划草稿需要名称。", code: "invalid_tool_arguments", field: "name")
        }
        guard let slots, (1 ... 14).contains(slots.count) else {
            return .failure("计划草稿需要 1 到 14 天。", code: "invalid_tool_arguments", field: "slots")
        }
        if let anchorDate, TrainingScheduleDraftDates.parse(anchorDate, calendar: calendar) == nil {
            return .failure(
                "开始日要写成 YYYY-MM-DD；用户没说就开始日省略。",
                code: "invalid_tool_arguments",
                field: "anchor_date"
            )
        }
        var payloadSlots: [TrainingScheduleDraftSlotPayload] = []
        var dayTitles: [String] = []
        do {
            var values: [TrainingScheduleSlotValue] = []
            for slot in slots {
                if slot.kind == "rest", slot.contents == nil {
                    values.append(.rest())
                } else if slot.kind == "training", let contents = slot.contents, !contents.isEmpty {
                    try values.append(.training(contents.map { try $0.resolve(in: context) }))
                } else {
                    throw TrainingContentError.invalid
                }
            }
            let days = try TrainingContentCompiler.days(scheduleID: UUID(), slots: values, in: context)
            dayTitles = days.map(\.title)
            // Preserve references for the editor.
            for (index, value) in values.enumerated() {
                let title = value.kindRaw == "rest" ? "休息" : "训练内容 \(index + 1)"
                payloadSlots.append(.init(title: title, value: value))
            }
            if values.count == days.count {
                for index in days.indices {
                    payloadSlots[index].title = days[index].title
                }
            }
        } catch {
            return .failure(error.localizedDescription, code: "invalid_tool_arguments", field: "slots")
        }
        let payload = TrainingScheduleDraftPayload(
            name: trimmed,
            anchorDate: anchorDate,
            slots: payloadSlots,
            dayTitles: dayTitles
        )
        guard let data = try? JSONEncoder().encode(payload),
              let value = try? JSONDecoder().decode(AgentJSONValue.self, from: data)
        else {
            return .failure("计划草稿无法编码。", code: "internal_error")
        }
        let lines = dayTitles.enumerated().map { index, title in
            "第 \(index + 1) 天 \(title)"
        }
        let summary = "训练计划草稿「\(trimmed)」尚未保存。开始日 \(TrainingScheduleDraftDates.label(anchorDate))。\n"
            + lines.joined(separator: "\n")
        return .success(summary, code: TrainingScheduleDraftPayload.code, data: value)
    }

    private static func scheduleCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<TrainingSchedule>())) ?? -1
    }
}
