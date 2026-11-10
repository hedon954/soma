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
                // 健康导入按自然日一条：当天最后体重 72.4、最后体脂 18.6 合为今日日记录；同日手动保留。
                let keepPaired = calendar.date(byAdding: .hour, value: 12, to: today)!
                let manualDay = calendar.date(byAdding: .day, value: -1, to: today)!
                let unknownDay = calendar.date(byAdding: .day, value: -5, to: today)!
                let rangeProbe = calendar.date(byAdding: .day, value: -80, to: today)!
                let todayKey = BodyMassDayKey.dayKey(for: keepPaired, calendar: calendar)
                let todayEntry = BodyEntry(
                    date: keepPaired,
                    weight: 72.4,
                    bodyFat: 18.6,
                    waist: nil,
                    notes: "",
                    analysis: "",
                    externalSource: BodyMassImportIdentity.externalSource,
                    externalID: BodyMassImportIdentity.bodyDayExternalID(dayKey: todayKey),
                    sourceName: "Keep",
                    sourceBundleIdentifier: "com.gotokeep.keep"
                )
                todayEntry.healthDayEvidence = BodyHealthDayEvidence(
                    dayKey: todayKey,
                    timeZoneIdentifier: calendar.timeZone.identifier,
                    weight: .init(
                        sampleUUID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                        date: keepPaired,
                        value: 72.4,
                        sourceName: "Keep",
                        sourceBundleIdentifier: "com.gotokeep.keep"
                    ),
                    bodyFat: .init(
                        sampleUUID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                        date: keepPaired,
                        value: 18.6,
                        sourceName: "Keep",
                        sourceBundleIdentifier: "com.gotokeep.keep"
                    )
                )
                context.insert(todayEntry)
                let unknownKey = BodyMassDayKey.dayKey(for: unknownDay, calendar: calendar)
                let unknownName = "超长厂商名称 Acme Smart Body Composition Scale Pro Max"
                let unknownEntry = BodyEntry(
                    date: unknownDay,
                    weight: 72.1,
                    notes: "",
                    analysis: "",
                    externalSource: BodyMassImportIdentity.externalSource,
                    externalID: BodyMassImportIdentity.bodyDayExternalID(dayKey: unknownKey),
                    sourceName: unknownName,
                    sourceBundleIdentifier: "com.acme.scale"
                )
                unknownEntry.healthDayEvidence = BodyHealthDayEvidence(
                    dayKey: unknownKey,
                    timeZoneIdentifier: calendar.timeZone.identifier,
                    weight: .init(
                        sampleUUID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                        date: unknownDay,
                        value: 72.1,
                        sourceName: unknownName,
                        sourceBundleIdentifier: "com.acme.scale"
                    ),
                    bodyFat: nil
                )
                context.insert(unknownEntry)
                // 含腰围字段：本页 UI 不展示，但历史数据保留。
                context.insert(BodyEntry(
                    date: manualDay,
                    weight: 71.8,
                    bodyFat: 17.5,
                    waist: 79,
                    notes: "手动夹具"
                ))
                context.insert(BodyEntry(
                    date: rangeProbe,
                    weight: 66.6,
                    notes: "区间夹具"
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
