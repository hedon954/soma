import Foundation
import SwiftData

@MainActor
enum EnergyPlanForecastLoader {
    static func load(in container: ModelContainer, now: Date = .now, calendar: Calendar = .current) throws -> [EnergyPlannedTrainingDay] {
        guard container.schema.entities.contains(where: { $0.name == "TrainingSchedule" }) else { return [] }
        let context = ModelContext(container)
        var query = FetchDescriptor<TrainingSchedule>(predicate: #Predicate { $0.statusRaw == "active" },
                                                      sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        query.fetchLimit = 1
        guard let schedule = try context.fetch(query).first else { return [] }
        let today = calendar.startOfDay(for: now)
        let days: [TrainingContentDay]
        do {
            days = try TrainingContentCompiler.days(scheduleID: schedule.id, slots: schedule.slots, in: context, validating: false)
        } catch is TrainingContentError { return unavailable(schedule.name, today: today, calendar: calendar) }
        guard !schedule.reanchorRequired, !days.isEmpty else { return unavailable(schedule.name, today: today, calendar: calendar) }
        let anchor = calendar.startOfDay(for: schedule.anchorDate)
        var latest = FetchDescriptor<WorkoutEntry>(predicate: #Predicate { $0.dailyActivityData == nil && $0.date <= now },
                                                   sortBy: [SortDescriptor(\.date, order: .reverse)])
        latest.fetchLimit = 1
        let last = try context.fetch(latest).first?.date
        guard !TrainingScheduleResolver.phaseIsStale(anchor: anchor, cycleLength: days.count, today: today,
                                                     lastTrainingDay: last, calendar: calendar)
        else {
            return unavailable(schedule.name, today: today, calendar: calendar)
        }
        return (1 ... 7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today), date >= anchor,
                  let difference = calendar.dateComponents([.day], from: anchor, to: date).day else { return nil }
            let slot = days[difference % days.count]
            let events = slot.prescriptions.compactMap(estimate)
            return .init(date: date, source: "已确认计划 · " + schedule.name,
                         eventsPerKilogram: events.count == slot.prescriptions.count ? events : nil)
        }
    }

    private static func unavailable(_ name: String, today: Date, calendar: Calendar) -> [EnergyPlannedTrainingDay] {
        (1 ... 7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map {
                .init(date: $0, source: "计划需检查或重新锚定 · " + name, eventsPerKilogram: nil)
            }
        }
    }

    private static func estimate(_ prescription: TemplateExercisePrescription) -> EnergyTrainingEvent? {
        guard prescription.laterality != .both || prescription.restBetweenSidesSeconds != nil else { return nil }
        let evidence = prescription.plannedSets.sorted { $0.order < $1.order }.flatMap { set -> [WorkoutSetEvidence] in
            let sides: [WorkoutEffortSide] = switch prescription.laterality {
            case .none: [.none]
            case .both: [.left, .right]
            case .left: [.left]
            case .right: [.right]
            }
            return sides.enumerated().map { index, side in
                .init(logicalSetIndex: set.order, side: side, kind: set.kind, targetKind: set.targetKind,
                      reps: set.targetReps, durationSeconds: set.targetDurationSeconds,
                      restSeconds: index < sides.count - 1 ? prescription.restBetweenSidesSeconds : nil)
            }
        }
        guard let value = WorkoutCalorieCalculator.estimateWorkout(exercise: prescription.exerciseName, intensity: nil,
                                                                   actualDurationMinutes: nil, evidence: evidence,
                                                                   fallbackRestSeconds: prescription.targetRestSeconds, weightKG: 1) else { return nil }
        return .init(id: "plan:" + prescription.id.uuidString, source: "训练计划预测", activityType: prescription.exerciseName,
                     scope: .metGross, kilocalories: value.met * value.durationMinutes / 60, met: value.met,
                     durationHours: value.durationMinutes / 60, start: nil, end: nil)
    }
}
