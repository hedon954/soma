import Foundation
import SwiftData

enum TrainingScheduleStore {
    @MainActor
    static func facts(
        for schedule: TrainingSchedule,
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws -> (completions: [TrainingScheduleCompletion], lastTrainingDay: Date?) {
        let anchor = calendar.startOfDay(for: schedule.anchorDate)
        let completed = WorkoutSessionStatus.completed.rawValue
        var sessions = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate {
                $0.startedAt >= anchor && $0.statusRaw == completed
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        sessions.fetchLimit = 400
        let completions = try context.fetch(sessions).compactMap { session -> TrainingScheduleCompletion? in
            guard let programID = session.programID else { return nil }
            return TrainingScheduleCompletion(
                programID: programID,
                day: calendar.startOfDay(for: session.startedAt)
            )
        }
        var entries = FetchDescriptor<WorkoutEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        entries.fetchLimit = 1
        let entryDay = try context.fetch(entries).first.map {
            calendar.startOfDay(for: $0.date)
        }
        let sessionDay = completions.map(\.day).max()
        let last = [entryDay, sessionDay].compactMap { $0 }.max()
        return (completions, last)
    }

    @MainActor
    static func sync(
        _ schedule: TrainingSchedule,
        today: Date = .now,
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws -> TrainingScheduleResolution {
        let facts = try facts(for: schedule, in: context, calendar: calendar)
        let stale = TrainingScheduleResolver.phaseIsStale(
            anchor: schedule.anchorDate,
            cycleLength: schedule.slots.count,
            today: today,
            lastTrainingDay: facts.lastTrainingDay,
            calendar: calendar
        )
        if stale, !schedule.reanchorRequired {
            schedule.reanchorRequired = true
            schedule.updatedAt = .now
        }
        let resolution = TrainingScheduleResolver.resolve(
            anchor: schedule.anchorDate,
            slots: schedule.slots,
            today: today,
            closures: schedule.closures,
            completions: facts.completions,
            reanchorRequired: schedule.reanchorRequired,
            calendar: calendar
        )
        var closures = schedule.closures
        var changed = false
        for day in resolution.expiredDueDays {
            let exists = closures.contains {
                calendar.isDate($0.dueDay, inSameDayAs: day)
            }
            if !exists {
                closures.append(.skipped(on: calendar.startOfDay(for: day)))
                changed = true
            }
        }
        if changed {
            schedule.closures = closures
            schedule.updatedAt = .now
        }
        if context.hasChanges {
            try context.save()
        }
        return resolution
    }

    @MainActor
    static func recordRest(
        _ schedule: TrainingSchedule,
        dueDay: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws {
        let day = calendar.startOfDay(for: dueDay)
        var closures = schedule.closures
        guard !closures.contains(where: { calendar.isDate($0.dueDay, inSameDayAs: day) }) else {
            return
        }
        closures.append(.rest(on: day))
        schedule.closures = closures
        schedule.updatedAt = .now
        try context.save()
    }

    @MainActor
    static func reanchor(
        _ schedule: TrainingSchedule,
        today: Date = .now,
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws {
        guard let anchor = TrainingScheduleResolver.anchor(
            soToday: today,
            matchesFirstCourseIn: schedule.slots,
            calendar: calendar
        ) else { return }
        schedule.anchorDate = anchor
        schedule.reanchorRequired = false
        schedule.updatedAt = .now
        try context.save()
    }

    @MainActor
    static func save(
        _ schedule: TrainingSchedule,
        in context: ModelContext
    ) throws {
        if schedule.modelContext == nil {
            context.insert(schedule)
        }
        let active = TrainingScheduleStatus.active.rawValue
        if schedule.status == .active {
            let others = try context.fetch(
                FetchDescriptor<TrainingSchedule>(
                    predicate: #Predicate { $0.statusRaw == active }
                )
            )
            for other in others where other.id != schedule.id {
                other.status = .archived
                other.updatedAt = .now
            }
        }
        try BusinessIDAllocator.assignMissingIDs(in: context)
        try context.save()
    }
}
