import SwiftData
import WidgetKit

@MainActor
enum SomaWidgetSnapshotProjector {
    static let widgetKind = "SomaQuickCaptureWidget"

    static func refresh(
        in context: ModelContext,
        dataSpace: DataSpace,
        now: Date = .now
    ) {
        let preferences = SomaWidgetSharedStore.loadPreferences()
        let snapshot = makeSnapshot(
            in: context,
            dataSpace: dataSpace,
            preferences: preferences,
            now: now
        )
        SomaWidgetSharedStore.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func clear() {
        SomaWidgetSharedStore.clearSnapshot()
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func makeSnapshot(
        in context: ModelContext,
        dataSpace: DataSpace,
        preferences: SomaWidgetPreferences,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SomaWidgetSnapshot {
        let sessions = (try? context.fetch(
            FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)])
        )) ?? []
        let programs = (try? context.fetch(
            FetchDescriptor<TrainingProgram>()
        )) ?? []
        let versions = (try? context.fetch(
            FetchDescriptor<WorkoutTemplateVersion>()
        )) ?? []
        let performances = (try? context.fetch(
            FetchDescriptor<ExercisePerformance>()
        )) ?? []
        let sets = (try? context.fetch(FetchDescriptor<WorkoutSet>())) ?? []
        let workouts = (try? context.fetch(FetchDescriptor<WorkoutEntry>())) ?? []

        let active = sessions.first {
            $0.status == .active || $0.status == .paused
        }
        let activeSession = active.map { session in
            let performanceIDs = Set(
                performances.filter { $0.sessionID == session.id }.map(\.id)
            )
            let sessionSets = sets.filter { performanceIDs.contains($0.performanceID) }
            let planName = preferences.privacyLevel == .trainingDetail
                ? programName(for: session, programs: programs, versions: versions)
                : nil
            return SomaWidgetSnapshot.Session(
                id: session.id,
                completedSetCount: sessionSets.filter { $0.status == .completed }.count,
                totalSetCount: sessionSets.count,
                planName: planName
            )
        }

        let fixedProgram = programs.first {
            $0.id == preferences.fixedProgramID && $0.status == .active
        }.map { program in
            SomaWidgetSnapshot.Program(
                id: program.id,
                name: preferences.privacyLevel == .trainingDetail ? program.name : nil
            )
        }

        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        let trainingDates = workouts.map(\.date)
            + sessions.compactMap { session in
                session.status == .completed ? session.endedAt : nil
            }
        let weekWorkoutCount = Set<Date>(trainingDates.compactMap { date in
            guard let weekInterval, weekInterval.contains(date) else { return nil }
            return calendar.startOfDay(for: date)
        }).count
        let latestDate = trainingDates.max()
        let daysSinceLastWorkout = latestDate.map {
            max(0, calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: $0),
                to: calendar.startOfDay(for: now)
            ).day ?? 0)
        }

        return SomaWidgetSnapshot(
            dataSpaceRaw: dataSpace.rawValue,
            generatedAt: now,
            activeSession: activeSession,
            fixedProgram: fixedProgram,
            weekWorkoutCount: weekWorkoutCount,
            daysSinceLastWorkout: daysSinceLastWorkout
        )
    }

    private static func programName(
        for session: WorkoutSession,
        programs: [TrainingProgram],
        versions: [WorkoutTemplateVersion]
    ) -> String? {
        guard let familyID = session.sourceTemplateFamilyID else { return nil }
        let programIDs = Set(versions.filter { $0.familyID == familyID }.map(\.programID))
        return programs.first {
            $0.status == .active && programIDs.contains($0.id)
        }?.name
    }
}
