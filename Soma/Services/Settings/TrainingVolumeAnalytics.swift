import Foundation

struct TrainingVolumePoint: Identifiable, Equatable, Sendable {
    let date: Date
    let volume: Double

    var id: Date {
        date
    }
}

enum TrainingVolumeAnalytics {
    static func dailyPoints(
        from workouts: [WorkoutEntry],
        calendar: Calendar = .current
    ) -> [TrainingVolumePoint] {
        let dailyVolumes = workouts.reduce(into: [Date: Double]()) { result, workout in
            guard let volume = workout.estimatedVolume, volume > 0 else { return }
            result[calendar.startOfDay(for: workout.date), default: 0] += volume
        }

        return dailyVolumes
            .map { TrainingVolumePoint(date: $0.key, volume: $0.value) }
            .sorted { $0.date < $1.date }
    }

    static func dailyPoints(
        from workouts: [WorkoutEntry],
        sessions: [WorkoutSession],
        performances: [ExercisePerformance],
        sets: [WorkoutSet],
        calendar: Calendar = .current
    ) -> [TrainingVolumePoint] {
        var daily = Dictionary(
            uniqueKeysWithValues: dailyPoints(
                from: workouts,
                calendar: calendar
            ).map { ($0.date, $0.volume) }
        )
        let performancesByID = Dictionary(
            uniqueKeysWithValues: performances.map { ($0.id, $0) }
        )
        let sessionsByID = Dictionary(
            uniqueKeysWithValues: sessions.map { ($0.id, $0) }
        )
        let projectedPerformanceIDs = Set(
            workouts.compactMap(\.sourcePerformanceID)
        )
        for set in sets where set.status == .completed {
            guard let volume = set.completedVolume,
                  volume > 0,
                  let performance = performancesByID[set.performanceID],
                  !projectedPerformanceIDs.contains(performance.id),
                  !performance.workoutProjectionSuppressed,
                  let session = sessionsByID[performance.sessionID]
            else {
                continue
            }
            daily[
                calendar.startOfDay(for: session.startedAt),
                default: 0
            ] += volume
        }
        return daily.map {
            TrainingVolumePoint(date: $0.key, volume: $0.value)
        }.sorted { $0.date < $1.date }
    }

    static func total(
        in interval: Range<Date>,
        points: [TrainingVolumePoint]
    ) -> Double {
        var total = 0.0
        for point in points where interval.contains(point.date) {
            total += point.volume
        }
        return total
    }

    static func formatted(_ volume: Double) -> String {
        guard volume >= 1000 else { return String(format: "%.0f", volume) }
        let thousands = volume / 1000
        return thousands >= 10
            ? String(format: "%.0fk", thousands)
            : String(format: "%.1fk", thousands)
    }
}
