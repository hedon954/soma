import Foundation

struct TrainingScheduleCompletion: Equatable, Sendable {
    var programID: UUID
    var day: Date
}

enum TrainingScheduleAttention: Equatable, Sendable {
    case paused
    case restDay
    case settled
    case due(programID: UUID, dueDay: Date, makeup: Bool)
}

struct TrainingScheduleResolution: Equatable, Sendable {
    var attention: TrainingScheduleAttention
    var expiredDueDays: [Date]
    var probeProgramID: UUID?
}

enum TrainingScheduleResolver {
    static func phaseIsStale(
        anchor: Date,
        cycleLength: Int,
        today: Date,
        lastTrainingDay: Date?,
        calendar: Calendar
    ) -> Bool {
        guard cycleLength > 0 else { return false }
        let anchorDay = calendar.startOfDay(for: anchor)
        let todayDay = calendar.startOfDay(for: today)
        let baseline = lastTrainingDay.map { last in
            let day = calendar.startOfDay(for: last)
            return day >= anchorDay ? day : anchorDay
        } ?? anchorDay
        let gap = calendar.dateComponents([.day], from: baseline, to: todayDay).day ?? 0
        return gap >= cycleLength
    }

    static func resolve(
        anchor: Date,
        slots: [TrainingScheduleSlotValue],
        today: Date,
        closures: [TrainingScheduleClosureValue],
        completions: [TrainingScheduleCompletion],
        reanchorRequired: Bool,
        calendar: Calendar
    ) -> TrainingScheduleResolution {
        let probe = preferredCourseID(slots: slots, completions: completions)
        guard !slots.isEmpty else {
            return TrainingScheduleResolution(
                attention: .paused,
                expiredDueDays: [],
                probeProgramID: probe
            )
        }
        if reanchorRequired {
            return TrainingScheduleResolution(
                attention: .paused,
                expiredDueDays: [],
                probeProgramID: probe
            )
        }
        let anchorDay = calendar.startOfDay(for: anchor)
        let todayDay = calendar.startOfDay(for: today)
        var day = anchorDay
        var expired: [Date] = []
        while day <= todayDay {
            let offset = calendar.dateComponents([.day], from: anchorDay, to: day).day ?? 0
            let slot = slots[offset % slots.count]
            if let programID = slot.program {
                let grace = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                let closed = isClosed(
                    dueDay: day,
                    graceDay: grace,
                    programID: programID,
                    closures: closures,
                    completions: completions,
                    calendar: calendar
                )
                if !closed {
                    if todayDay <= grace {
                        return TrainingScheduleResolution(
                            attention: .due(
                                programID: programID,
                                dueDay: day,
                                makeup: todayDay != day
                            ),
                            expiredDueDays: expired,
                            probeProgramID: probe
                        )
                    }
                    expired.append(day)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let todayOffset = calendar.dateComponents(
            [.day], from: anchorDay, to: todayDay
        ).day ?? 0
        let todaySlot = slots[(todayOffset % slots.count + slots.count) % slots.count]
        let attention: TrainingScheduleAttention = todaySlot.program == nil ? .restDay : .settled
        return TrainingScheduleResolution(
            attention: attention,
            expiredDueDays: expired,
            probeProgramID: probe
        )
    }

    static func anchor(
        soToday today: Date,
        matchesFirstCourseIn slots: [TrainingScheduleSlotValue],
        calendar: Calendar
    ) -> Date? {
        guard let index = slots.firstIndex(where: { $0.program != nil }) else { return nil }
        return calendar.date(byAdding: .day, value: -index, to: calendar.startOfDay(for: today))
    }

    static func preferredCourseID(
        slots: [TrainingScheduleSlotValue],
        completions: [TrainingScheduleCompletion]
    ) -> UUID? {
        let courseIDs = slots.compactMap(\.program)
        guard !courseIDs.isEmpty else { return nil }
        var counts: [UUID: Int] = [:]
        for completion in completions where courseIDs.contains(completion.programID) {
            counts[completion.programID, default: 0] += 1
        }
        return courseIDs.max { lhs, rhs in
            let left = counts[lhs] ?? 0
            let right = counts[rhs] ?? 0
            if left != right {
                return left < right
            }
            return courseIDs.firstIndex(of: lhs) ?? 0 > courseIDs.firstIndex(of: rhs) ?? 0
        }
    }

    private static func isClosed(
        dueDay: Date,
        graceDay: Date,
        programID: UUID,
        closures: [TrainingScheduleClosureValue],
        completions: [TrainingScheduleCompletion],
        calendar: Calendar
    ) -> Bool {
        if closures.contains(where: { calendar.isDate($0.dueDay, inSameDayAs: dueDay) }) {
            return true
        }
        return completions.contains { completion in
            completion.programID == programID
                && (
                    calendar.isDate(completion.day, inSameDayAs: dueDay)
                        || calendar.isDate(completion.day, inSameDayAs: graceDay)
                )
        }
    }
}
