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
            if ProcessInfo.processInfo.environment["SOMA_UI_BODY_MASS_FIXTURE"] == "1" {
                // 同源同一秒的体重+体脂应展示为一条同次测量；同日不同秒保持单指标。
                let keepPaired = calendar.date(byAdding: .hour, value: 12, to: today)!
                let keepSplit = calendar.date(byAdding: .hour, value: 10, to: today)!
                let manualDay = calendar.date(byAdding: .day, value: -1, to: today)!
                let unknownDay = calendar.date(byAdding: .day, value: -5, to: today)!
                context.insert(BodyEntry(
                    date: keepPaired,
                    weight: 72.4,
                    bodyFat: nil,
                    waist: nil,
                    notes: "",
                    analysis: "",
                    externalSource: BodyMassImportIdentity.externalSource,
                    externalID: BodyMassImportIdentity.bodyMassExternalID(sampleUUID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!),
                    sourceName: "Keep",
                    sourceBundleIdentifier: "com.gotokeep.keep"
                ))
                context.insert(BodyEntry(
                    date: keepPaired,
                    weight: nil,
                    bodyFat: 18.6,
                    waist: nil,
                    notes: "",
                    analysis: "",
                    externalSource: BodyMassImportIdentity.externalSource,
                    externalID: BodyMassImportIdentity.bodyFatExternalID(sampleUUID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!),
                    sourceName: "Keep",
                    sourceBundleIdentifier: "com.gotokeep.keep"
                ))
                context.insert(BodyEntry(
                    date: keepSplit,
                    weight: 70.9,
                    bodyFat: nil,
                    waist: nil,
                    notes: "",
                    analysis: "",
                    externalSource: BodyMassImportIdentity.externalSource,
                    externalID: BodyMassImportIdentity.bodyMassExternalID(sampleUUID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!),
                    sourceName: "Keep",
                    sourceBundleIdentifier: "com.gotokeep.keep"
                ))
                context.insert(BodyEntry(
                    date: unknownDay,
                    weight: 72.1,
                    notes: "",
                    analysis: "",
                    externalSource: BodyMassImportIdentity.externalSource,
                    externalID: BodyMassImportIdentity.bodyMassExternalID(sampleUUID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!),
                    sourceName: "超长厂商名称 Acme Smart Body Composition Scale Pro Max",
                    sourceBundleIdentifier: "com.acme.scale"
                ))
                // 含腰围字段：本页 UI 不展示，但历史数据保留。
                context.insert(BodyEntry(
                    date: manualDay,
                    weight: 71.8,
                    bodyFat: 17.5,
                    waist: 79,
                    notes: "手动夹具"
                ))
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
