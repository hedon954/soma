import Foundation
import SwiftData

@MainActor
enum ProgressHistoryTestFixture {
    static func seedIfRequested(in context: ModelContext) {
        guard AppTestRuntime.isRunning,
              ProcessInfo.processInfo.environment["SOMA_UI_PROGRESS_FIXTURE"] == "1"
        else { return }
        do {
            var existing = FetchDescriptor<MealEntry>(predicate: #Predicate { $0.title == "进展夹具餐食 0" })
            existing.fetchLimit = 1
            guard try context.fetch(existing).isEmpty else { return }
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            let first = calendar.date(byAdding: .day, value: -90, to: today)!
            let profile = UserProfile(
                updatedAt: first, displayName: "虚构进展用户", biologicalSex: .male,
                birthDate: calendar.date(from: DateComponents(year: 1996, month: 1, day: 1)), height: 170
            )
            if ProcessInfo.processInfo.environment["SOMA_UI_PROGRESS_NO_BASELINE"] != "1" {
                profile.energyBaselinesData = try JSONEncoder().encode([
                    EnergyLifestyleBaseline(effectiveFrom: first, factor: 1.45, label: "虚构生活方式参考")
                ])
            }
            context.insert(profile)
            for offset in -90 ... 0 {
                let day = calendar.date(byAdding: .day, value: offset, to: today)!
                context.insert(MealEntry(
                    date: day, mealType: .lunch, title: "进展夹具餐食 \(offset)",
                    calories: 1900 + abs(offset % 5) * 100, protein: 110, carbs: 240, fat: 60
                ))
                let confirmation = EnergyContextEntry(key: EnergyEvidenceStore.contextKey(for: day, calendar: calendar),
                                                      date: day, timeZoneIdentifier: calendar.timeZone.identifier)
                confirmation.confirmationData = try EnergyInputCoding.encode(EnergyDayConfirmation(
                    foodComplete: true, mealEvidenceFingerprint: EnergyFoodEvidence.fingerprint(on: day, in: context, calendar: calendar)
                ))
                context.insert(confirmation)
                if offset.isMultiple(of: 3) {
                    context.insert(WorkoutEntry(date: day, exercise: "虚构深蹲", sets: 5, reps: 5, weight: 40, restSeconds: 60))
                }
                if offset.isMultiple(of: 7) || offset == -90 {
                    context.insert(BodyEntry(date: day, weight: 70 + Double(abs(offset)) / 100, bodyFat: 18, waist: 80))
                }
            }
            if ProcessInfo.processInfo.environment["SOMA_UI_DAILY_ACTIVITY_FIXTURE"] == "1" {
                try DailyActivityRecordStore.replace([DailyActivitySyncCoordinator.demo(key: .init(date: today, calendar: calendar))], in: context)
            }
            LibraryAndMealTestFixture.seedIfRequested(in: context)
            try context.save()
            try EnergyUITestFixture.seedIfRequested(in: context)
        } catch {
            context.rollback()
            assertionFailure("Progress UI fixture could not be prepared")
        }
    }
}
