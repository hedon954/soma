import Foundation
import SwiftData

/// ADR 0047：确定性上下文包，替代两行 structuredContext。
enum AgentContextPackBuilder {
    static let maximumCharacters = 2800

    static func build(
        gyms: [GymProfile],
        equipment: [GymEquipment],
        in context: ModelContext,
        sessionID: UUID? = nil,
        businessDate: Date = .now,
        timeZone: TimeZone = .current
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day7 = calendar.date(byAdding: .day, value: -7, to: businessDate)
            ?? businessDate
        let day28 = calendar.date(byAdding: .day, value: -28, to: businessDate)
            ?? businessDate

        let workouts = fetchRecent(
            WorkoutEntry.self,
            sort: \WorkoutEntry.date,
            limit: 80,
            in: context
        )
        let meals = fetchRecent(
            MealEntry.self,
            sort: \MealEntry.date,
            limit: 40,
            in: context
        )
        let bodies = fetchRecent(
            BodyEntry.self,
            sort: \BodyEntry.date,
            limit: 14,
            in: context
        )
        let profiles = fetchRecent(
            UserProfile.self,
            sort: \UserProfile.updatedAt,
            limit: 1,
            in: context
        )
        let programs = ((try? context.fetch(FetchDescriptor<TrainingProgram>())) ?? [])
            .filter { $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
        let sessions = fetchRecent(
            WorkoutSession.self,
            sort: \WorkoutSession.startedAt,
            limit: 8,
            in: context
        )

        var sections: [String] = []
        sections.append(profileLine(profiles.first))
        sections.append(gymLine(gyms: gyms, equipment: equipment))
        sections.append(dayWorkoutLine(
            workouts: workouts,
            businessDate: businessDate,
            calendar: calendar,
            in: context
        ))
        sections.append(dayMealLine(
            meals: meals,
            businessDate: businessDate,
            calendar: calendar
        ))
        sections.append(trainingFrequencyLine(workouts: workouts, since: day7, label: "近7天"))
        sections.append(trainingFrequencyLine(workouts: workouts, since: day28, label: "近28天"))
        if let muscle = muscleDistribution(workouts: workouts, since: day28, in: context) {
            sections.append(muscle)
        }
        if let recentDays = recentTrainingDays(workouts: workouts, limit: 3) {
            sections.append(recentDays)
        }
        if let plan = activePlanLine(programs: programs, sessions: sessions, in: context) {
            sections.append(plan)
        }
        if let guided = activeGuidedLine(sessions: sessions) {
            sections.append(guided)
        }
        if let weight = weightTrendLine(bodies: bodies) {
            sections.append(weight)
        }
        if let sessionID,
           let writes = recentSessionWrites(
               sessionID: sessionID,
               workouts: workouts,
               meals: meals,
               bodies: bodies
           )
        {
            sections.append(writes)
        }

        return truncate(sections.filter { !$0.isEmpty }.joined(separator: "\n"))
    }

    private static func profileLine(_ profile: UserProfile?) -> String {
        guard let profile else { return "" }
        var parts: [String] = []
        if !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(profile.displayName)
        }
        if let height = profile.height {
            parts.append(String(format: "身高 %.0fcm", height))
        }
        if !profile.fitnessGoal.isEmpty {
            parts.append("目标 \(profile.fitnessGoal)")
        }
        if !profile.healthNotes.isEmpty {
            parts.append("限制 \(profile.healthNotes)")
        }
        guard !parts.isEmpty else { return "" }
        return "身体信息：\(parts.joined(separator: "；"))"
    }

    private static func gymLine(gyms: [GymProfile], equipment: [GymEquipment]) -> String {
        guard let current = GymSelection.current(in: gyms) else { return "" }
        let gear = equipment
            .filter { $0.gymID == current.id }
            .map(\.name)
        let gearText = gear.isEmpty ? "" : "；器械：\(gear.prefix(8).joined(separator: "、"))"
        return "当前健身房：\(current.name)\(gearText)"
    }

    private static func trainingFrequencyLine(
        workouts: [WorkoutEntry],
        since: Date,
        label: String
    ) -> String {
        let days = Set(
            workouts
                .filter { $0.date >= since && $0.externalSource == nil }
                .map { Calendar.current.startOfDay(for: $0.date) }
        )
        return days.isEmpty ? "" : "\(label)训练：\(days.count) 天"
    }

    private static func dayWorkoutLine(
        workouts: [WorkoutEntry],
        businessDate: Date,
        calendar: Calendar,
        in context: ModelContext
    ) -> String {
        let values = workouts.filter {
            calendar.isDate($0.date, inSameDayAs: businessDate)
        }
        guard !values.isEmpty else { return "" }
        let definitions = (
            try? context.fetch(FetchDescriptor<ExerciseDefinition>())
        ) ?? []
        let exerciseBusinessIDs = Dictionary(
            uniqueKeysWithValues: definitions.compactMap { definition in
                definition.businessID.map { (definition.id, $0) }
            }
        )
        let rows = values.prefix(12).map { workout in
            let detail = workout.setEvidenceSummary
                ?? workout.durationMinutes.map { "\($0)分钟" }
                ?? "仅动作"
            let exerciseID = workout.exerciseID
                .flatMap { exerciseBusinessIDs[$0] }
                .map(String.init) ?? "待确认"
            return "\(workout.exercise)（\(detail)，exercise_id: \(exerciseID)）"
        }
        return "Session 业务日训练：\(rows.joined(separator: "；"))"
    }

    private static func dayMealLine(
        meals: [MealEntry],
        businessDate: Date,
        calendar: Calendar
    ) -> String {
        let values = meals.filter {
            calendar.isDate($0.date, inSameDayAs: businessDate)
        }
        guard !values.isEmpty else { return "" }
        let rows = values.prefix(12).map { meal in
            let calories = meal.calories.map { "，\($0)kcal" } ?? ""
            return "\(meal.mealType) \(meal.title)\(calories)"
        }
        return "Session 业务日饮食：\(rows.joined(separator: "；"))"
    }

    private static func muscleDistribution(
        workouts: [WorkoutEntry],
        since: Date,
        in context: ModelContext
    ) -> String? {
        let definitions = (try? context.fetch(FetchDescriptor<ExerciseDefinition>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        var counts: [String: Int] = [:]
        for workout in workouts where workout.date >= since && workout.externalSource == nil {
            let sets = workout.setCount ?? 0
            guard sets > 0 else { continue }
            let muscles = workout.exerciseID.flatMap { byID[$0]?.primaryMuscles } ?? []
            for group in MuscleGroupMapping.resolve(muscles) {
                counts[group.displayName, default: 0] += sets
            }
        }
        guard !counts.isEmpty else { return nil }
        let top = counts.sorted { $0.value > $1.value }.prefix(5)
            .map { "\($0.key)\($0.value)组" }
            .joined(separator: "、")
        return "近28天肌群组数：\(top)"
    }

    private static func recentTrainingDays(workouts: [WorkoutEntry], limit: Int) -> String? {
        let local = workouts.filter { $0.externalSource == nil }
        let grouped = Dictionary(grouping: local) {
            Calendar.current.startOfDay(for: $0.date)
        }
        let days = grouped.keys.sorted(by: >).prefix(limit)
        guard !days.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        let lines = days.map { day -> String in
            let items = (grouped[day] ?? []).prefix(4).map { workout in
                let weight = workout.representativeWeight
                    .map { " \($0.formatted(.number.precision(.fractionLength(0 ... 1))))kg" }
                    ?? ""
                return "\(workout.exercise)\(weight)"
            }
            return "\(formatter.string(from: day)) \(items.joined(separator: "、"))"
        }
        return "最近训练日：\(lines.joined(separator: "；"))"
    }

    private static func activePlanLine(
        programs: [TrainingProgram],
        sessions: [WorkoutSession],
        in context: ModelContext
    ) -> String? {
        guard let program = programs.first else { return nil }
        let versions = (try? context.fetch(FetchDescriptor<WorkoutTemplateVersion>())) ?? []
        let version = versions.first { $0.id == program.currentTemplateVersionID }
        let last = sessions.first {
            $0.programID == program.id && $0.status == .completed
        }
        var parts = ["当前计划：\(program.name)"]
        if let version {
            parts.append("模板 \(version.name) v\(version.version)")
        }
        if let last {
            let done = last.prescriptionSnapshot.count
            parts.append("上次完成 \(done) 个动作快照")
        }
        return parts.joined(separator: "；")
    }

    private static func activeGuidedLine(sessions: [WorkoutSession]) -> String? {
        guard let active = sessions.first(where: {
            [.draft, .active, .paused].contains($0.status)
        }) else {
            return nil
        }
        let name = active.programNameSnapshot ?? "未命名计划"
        return "进行中带练：\(name) [session_id:\(active.id.uuidString)]"
    }

    private static func weightTrendLine(bodies: [BodyEntry]) -> String? {
        let weights = bodies.compactMap(\.weight).prefix(5)
        guard let latest = weights.first else { return nil }
        if weights.count >= 2, let oldest = weights.last {
            let delta = latest - oldest
            let sign = delta >= 0 ? "+" : ""
            return "体重：\(latest.formatted(.number.precision(.fractionLength(0 ... 1))))kg（近测 \(sign)\(delta.formatted(.number.precision(.fractionLength(0 ... 1))))kg）"
        }
        return "体重：\(latest.formatted(.number.precision(.fractionLength(0 ... 1))))kg"
    }

    private static func recentSessionWrites(
        sessionID: UUID,
        workouts: [WorkoutEntry],
        meals: [MealEntry],
        bodies: [BodyEntry]
    ) -> String? {
        var items: [String] = []
        for workout in workouts where workout.sourceSessionID == sessionID {
            items.append("训练 \(workout.exercise) [id:\(workout.id.uuidString)]")
            if items.count >= 5 {
                break
            }
        }
        for meal in meals where meal.sourceSessionID == sessionID {
            items.append("饮食 \(meal.title) [id:\(meal.id.uuidString)]")
            if items.count >= 5 {
                break
            }
        }
        for body in bodies where body.sourceSessionID == sessionID {
            items.append("身体 [id:\(body.id.uuidString)]")
            if items.count >= 5 {
                break
            }
        }
        guard !items.isEmpty else { return nil }
        return "本会话近期写入：\(items.joined(separator: "；"))"
    }

    private static func truncate(_ text: String) -> String {
        guard text.count > maximumCharacters else { return text }
        let end = text.index(text.startIndex, offsetBy: maximumCharacters)
        return String(text[..<end]) + "…"
    }

    private static func fetchRecent<T: PersistentModel>(
        _ type: T.Type,
        sort: KeyPath<T, Date>,
        limit: Int,
        in context: ModelContext
    ) -> [T] {
        var descriptor = FetchDescriptor<T>(
            sortBy: [SortDescriptor(sort, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }
}
