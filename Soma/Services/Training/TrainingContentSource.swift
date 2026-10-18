import CryptoKit
import Foundation
import SwiftData

struct TrainingContentDay: Equatable, Sendable {
    var id: UUID
    var title: String
    var prescriptions: [TemplateExercisePrescription]

    var slot: TrainingScheduleSlotValue {
        prescriptions.isEmpty ? .rest() : .training(prescriptions.map(TrainingContentSource.exercise), id: id)
    }
}

enum TrainingContentError: LocalizedError {
    case cycle, missing, tooLong, empty, invalid

    var errorDescription: String? {
        switch self {
        case .cycle: "计划不能循环包含，请移除重复引用。"
        case .missing: "引用的动作、课程或计划已不存在，请重新选择。"
        case .tooLong: "展开后最多 14 天，请缩短周期。"
        case .empty: "至少添加一个训练动作。"
        case .invalid: "训练内容无效，请重新选择。"
        }
    }
}

@MainActor
enum TrainingContentCompiler {
    static func days(
        scheduleID: UUID,
        slots: [TrainingScheduleSlotValue],
        in context: ModelContext,
        validating: Bool = true
    ) throws -> [TrainingContentDay] {
        var path: Set<UUID> = [scheduleID]
        let result = try expand(slots, root: scheduleID.uuidString, path: &path, in: context)
        guard result.count <= 14 else { throw TrainingContentError.tooLong }
        if validating {
            guard result.contains(where: { !$0.prescriptions.isEmpty }) else { throw TrainingContentError.empty }
            for day in result where !day.prescriptions.isEmpty {
                try TrainingPlanStore.validate(day.prescriptions, in: context)
            }
        }
        return result
    }

    private static func expand(
        _ slots: [TrainingScheduleSlotValue],
        root: String,
        path: inout Set<UUID>,
        in context: ModelContext
    ) throws -> [TrainingContentDay] {
        guard !slots.isEmpty, slots.count <= 14, path.count <= 14 else {
            throw TrainingContentError.tooLong
        }
        var result: [TrainingContentDay] = []
        for (index, slot) in slots.enumerated() {
            let key = root + "/" + (slot.id?.uuidString ?? String(index))
            if slot.kindRaw == "rest" {
                result.append(TrainingContentDay(id: stableID(key), title: "休息", prescriptions: []))
                continue
            }
            let contents = try contents(for: slot)
            var days = [TrainingContentDay(id: stableID(key), title: "", prescriptions: [])]
            var endedWithPlan = false
            for content in contents {
                if endedWithPlan, content.kind != .plan {
                    days.append(TrainingContentDay(id: stableID(key + "/after/" + content.id.uuidString), title: "", prescriptions: []))
                    endedWithPlan = false
                }
                switch content.kind {
                case .exercise:
                    guard let value = content.prescription else { throw TrainingContentError.invalid }
                    days[days.count - 1].prescriptions.append(value)
                    appendTitle(value.exerciseName, to: &days[days.count - 1])
                case .course:
                    guard let id = content.referenceID else { throw TrainingContentError.invalid }
                    let descriptor = FetchDescriptor<TrainingProgram>(predicate: #Predicate { $0.id == id })
                    guard let program = try context.fetch(descriptor).first else { throw TrainingContentError.missing }
                    let values = TrainingPlanStore.prescriptions(for: program, in: context)
                    guard !values.isEmpty else { throw TrainingContentError.empty }
                    days[days.count - 1].prescriptions += values
                    appendTitle(program.name, to: &days[days.count - 1])
                case .plan:
                    guard let id = content.referenceID else { throw TrainingContentError.invalid }
                    guard !path.contains(id) else { throw TrainingContentError.cycle }
                    let descriptor = FetchDescriptor<TrainingSchedule>(predicate: #Predicate { $0.id == id })
                    guard let plan = try context.fetch(descriptor).first else { throw TrainingContentError.missing }
                    path.insert(id)
                    let nested = try expand(plan.slots, root: key + "/" + content.id.uuidString, path: &path, in: context)
                    path.remove(id)
                    if days.count == 1, days[0].prescriptions.isEmpty, !endedWithPlan {
                        days = nested
                    } else {
                        days += nested
                    }
                    endedWithPlan = true
                }
                guard days.allSatisfy({ $0.prescriptions.count <= 100 }) else { throw TrainingContentError.invalid }
                guard days.count + result.count <= 14 else { throw TrainingContentError.tooLong }
            }
            // Existing single-course plans still recognize their historical course completions.
            if slot.kindRaw == "course", let id = slot.programID {
                days[0].id = id
            }
            normalize(&days)
            result += days
        }
        return result
    }

    private static func normalize(_ days: inout [TrainingContentDay]) {
        for index in days.indices {
            days[index].prescriptions = days[index].prescriptions.enumerated().map { offset, value in
                var value = value
                value.order = offset + 1
                value.id = stableID(days[index].id.uuidString + "/exercise/" + String(offset))
                return value
            }
            if days[index].title.isEmpty {
                days[index].title = "休息"
            }
        }
    }

    private static func contents(for slot: TrainingScheduleSlotValue) throws -> [TrainingContentSource] {
        if slot.kindRaw == "course", let id = slot.programID {
            return [.course(id)]
        }
        guard slot.kindRaw == "training", let values = slot.contents,
              !values.isEmpty, values.count <= 100 else { throw TrainingContentError.invalid }
        return values
    }

    private static func appendTitle(_ title: String, to day: inout TrainingContentDay) {
        guard !title.isEmpty else { return }
        day.title = day.title.isEmpty ? title : day.title + " · " + title
    }

    private static func stableID(_ value: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
