import Foundation

struct EnergyProjectionFacts: Sendable {
    var contexts: [EnergyContextFacts] = []
    var activity: [HealthActivityDayEvidence] = []
    var references: [EnergyReferenceDay] = []
    var reviews: [EnergyCalibrationReview] = []
    var associations: [EnergyTrainingAssociations] = []
    var plannedDays: [EnergyPlannedTrainingDay] = []
}

enum EnergyHistoryUpdate: Sendable {
    case reference(EnergyReferenceDay), daily(EnergyDayCalculation), calibration(EnergyCalibrationReview)
}

struct EnergyRuntimeOutput: Sendable {
    var outcomes: [Date: AdaptiveEnergyOutcome] = [:]
    var calculations: [Date: EnergyDayCalculation] = [:]
    var updates: [EnergyHistoryUpdate] = []
    var completeFoodDays: Set<Date> = []
}

enum EnergyRuntimeProjection {
    static func build(
        window: ProgressPeriodWindow, records: [ProgressHistoryRecord], profile: ProgressProfileFacts?,
        now: Date, calendar: Calendar
    ) -> EnergyRuntimeOutput {
        var output = EnergyRuntimeOutput()
        guard let profile else { return output }
        let facts = profile.energyFacts
        let today = calendar.startOfDay(for: now)
        let start = min(window.start, calendar.date(byAdding: .day, value: -56, to: min(today, window.start)) ?? window.start)
        let end = min(window.end, calendar.date(byAdding: .day, value: 1, to: today) ?? now)
        let grouped = Dictionary(grouping: records.filter { $0.activity.date <= now }, by: { calendar.startOfDay(for: $0.activity.date) })
        let weights = records.filter { ($0.weight ?? 0) > 0 && ($0.weight?.isFinite ?? false) && $0.activity.date <= now }.sorted(by: recordOrder)
        let contexts = facts.contexts.sorted { $0.date < $1.date }
        let confirmations = Dictionary(contexts.filter { $0.timeZoneIdentifier == calendar.timeZone.identifier }.map {
            ($0.date, $0.confirmation ?? .init())
        }, uniquingKeysWith: { _, last in last })
        let lifestyles = contexts.compactMap(\.lifestyle)
            .sorted { $0.effectiveFrom < $1.effectiveFrom }
        let matchingActivity = facts.activity.filter { $0.day.timeZoneIdentifier == calendar.timeZone.identifier }
        let activities = Dictionary(matchingActivity.map { ($0.day.start, $0) }, uniquingKeysWith: { _, last in last })
        var references = facts.references.sorted { $0.effectiveFrom < $1.effectiveFrom }
        var samples: [EnergyWalkingReferenceSample] = []
        var calibrationDays: [EnergyCalibrationDay] = []
        var cursor = start
        while cursor < end, let next = calendar.date(byAdding: .day, value: 1, to: cursor) {
            let entries = (grouped[cursor] ?? []).sorted(by: recordOrder)
            let confirmation = confirmations[cursor] ?? .init()
            let activity = activities[cursor]
            let weightRecord = weights.last { $0.activity.date < next }
            let weight = weightRecord?.weight
            let age = profile.birthDate.flatMap { calendar.dateComponents([.year], from: $0, to: cursor).year }
            let resting = RestingEnergyCalculator.dailyKilocalories(weightKG: weight, heightCM: profile.height,
                                                                    age: age, biologicalSex: profile.biologicalSex)
            let local = localTraining(entries)
            let events = local + (activity?.training ?? [])
            let links = facts.associations.last { $0.date == cursor && $0.timeZoneIdentifier == calendar.timeZone.identifier }
            let training = links?.applying(to: events) ?? events
            let preferred = EnergyDayCalculator.preferredEvents(training, resting: resting ?? 0)
            let intervalsResolved = preferred.allSatisfy { event in
                guard let start = event.start, let end = event.end else { return false }
                return start < end && event.scope != .unknown
            }
            let coverage = confirmation.walkingCoverageComplete == true && activity?.hasAmbiguousBoundarySamples == false
                && confirmation.trainingComplete == true && intervalsResolved && preferred.filter { $0.id.hasPrefix("soma") }.allSatisfy { event in
                    guard let start = event.start, let end = event.end else { return false }
                    return activity?.excludedIntervals.contains { $0.start <= start && $0.end >= end } == true
                }
            let sample = EnergyWalkingReferenceSample(date: cursor, kilometers: activity?.nonTrainingKilometers,
                                                      steps: activity?.nonTrainingSteps, coverageConfirmed: coverage,
                                                      trainingExcluded: intervalsResolved, basisID: activity?.basisID ?? "")
            let meals = entries.filter { $0.activity.kind == .meal }
            let intake = ProgressRecordedTotal(meals.map(\.calories), additionalIncompleteCount: meals.count { $0.caloriesArePartial })
            let foodComplete = confirmation.foodComplete == true && confirmation.mealEvidenceFingerprint == EnergyFoodEvidence.fingerprint(records: meals)
            if foodComplete {
                output.completeFoodDays.insert(cursor)
            }
            var calculation: EnergyDayCalculation?
            if let resting, let weight {
                do {
                    var reference = try referenceDay(on: cursor, profile: profile, lifestyles: lifestyles, references: references)
                    if reference.walkingKilometers == nil,
                       let distance = EnergyReferenceBuilder.walkingDistance(samples, before: cursor, basisID: HealthActivityDayEvidence.statisticsBasis, calendar: calendar)
                    {
                        reference = .init(id: reference.id, effectiveFrom: cursor, factor: reference.factor, walkingKilometers: distance,
                                          thermicShare: reference.thermicShare, allocationHours: reference.allocationHours,
                                          reason: "根据已确认覆盖、排除训练的近期步行绑定参考日；生活系数仍是估算",
                                          sourceFactsFingerprint: reference.sourceFactsFingerprint)
                        references.append(reference)
                        output.updates.append(.reference(reference))
                    }
                    let stride = EnergyReferenceBuilder.stepLengthMeters(samples, basisID: HealthActivityDayEvidence.statisticsBasis, calendar: calendar)
                    let distance = activity?.nonTrainingKilometers ?? activity?.nonTrainingSteps.flatMap { steps in stride.map { steps * $0 / 1000 } }
                    let correction = facts.reviews.filter { $0.date <= cursor }.max { $0.date < $1.date }?.nextCorrection ?? 0
                    calculation = try EnergyDayCalculator.calculate(.init(
                        date: cursor, resting: resting, weightKG: weight, reference: reference,
                        nonTrainingKilometers: distance, walkingCoverageConfirmed: coverage, isEndedDay: next <= today,
                        training: training, correction: correction,
                        observedNonTrainingSteps: activity?.nonTrainingSteps, stepLengthMeters: activity?.nonTrainingKilometers == nil ? stride : nil,
                        restingFormula: profile.height.flatMap { height in age.map { age in
                            .init(weightKG: weight, heightCM: height, age: age, biologicalSex: profile.biologicalSex, dailyKilocalories: resting)
                        } }, weightRecordID: weightRecord?.activity.id, weightRecordDate: weightRecord?.activity.date
                    ))
                } catch {
                    calculation = nil
                }
            }
            present(resting: resting, entries: entries, training: training, calculation: &calculation,
                    on: cursor, output: &output)
            if let calculation {
                output.calculations[cursor] = calculation
                if cursor >= window.start {
                    output.updates.append(.daily(calculation))
                }
            }
            calibrationDays.append(.init(
                date: cursor, intake: intake.recordCount > 0 ? intake.value : nil,
                uncalibratedTotal: calculation?.uncalibratedTotal,
                foodComplete: foodComplete && intake.recordCount > 0 && intake.missingCount == 0,
                activityComplete: calculation?.canCalibrate == true && confirmation.trainingComplete == true,
                weights: entries.compactMap(\.weight), fluidChangeConcern: confirmation.fluidChangeConcern == true,
                calculation: calculation, sourceMealIDs: meals.map(\.activity.id)
            ))
            if next <= today {
                samples.append(sample)
            }
            cursor = next
        }
        if window.end > today, let calculation = output.calculations[today] {
            review(on: today, days: calibrationDays, calculation: calculation, contexts: contexts,
                   facts: facts, output: &output, calendar: calendar)
        }
        return output
    }

    /// 当前总消耗。参考日差额失败时仍保留这份结果，因为总量不再依赖步行差额。
    private static func present(
        resting: Double?, entries: [ProgressHistoryRecord], training _: [EnergyTrainingEvent],
        calculation: inout EnergyDayCalculation?, on date: Date, output: inout EnergyRuntimeOutput
    ) {
        guard let resting else { return }
        let selection = DailyEnergyTotal.selectedDailyActive(in: entries)
        guard let components = DailyEnergyTotal.compose(
            restingKilocalories: resting,
            coefficient: ResidualEnergyCoefficient.current(),
            selectedActiveKilocalories: selection.kilocalories,
            trainingKilocalories: DailyEnergyTotal.listTrainingKilocalories(in: entries)
        ) else {
            output.outcomes[date] = .init(estimate: nil, missingReason: "活动能量读数无效")
            return
        }
        if var updated = calculation {
            updated.presentedTotal = components
            updated.presentedSelectedActiveKilocalories = selection.kilocalories
            calculation = updated
        }
        output.outcomes[date] = .init(
            estimate: .presented(
                components, selectedActiveKilocalories: selection.kilocalories,
                calculation: calculation, effectiveFrom: date
            ),
            missingReason: nil
        )
    }

    private static func recordOrder(_ left: ProgressHistoryRecord, _ right: ProgressHistoryRecord) -> Bool {
        left.activity.date == right.activity.date ? left.activity.id.uuidString < right.activity.id.uuidString : left.activity.date < right.activity.date
    }

    private static func referenceDay(
        on date: Date, profile: ProgressProfileFacts, lifestyles: [EnergyLifestyleFacts], references: [EnergyReferenceDay]
    ) throws -> EnergyReferenceDay {
        let lifestyle = lifestyles.last { $0.effectiveFrom <= date }
        let seed: EnergyReferenceDay
        if let lifestyle {
            seed = try EnergyReferenceBuilder.initial(lifestyle)
            return references.filter { $0.id == seed.id && $0.effectiveFrom <= date && $0.sourceFactsFingerprint == seed.sourceFactsFingerprint }
                .max { $0.effectiveFrom < $1.effectiveFrom } ?? seed
        }
        if let legacy = profile.baselines.filter({ $0.effectiveFrom <= date }).max(by: { $0.effectiveFrom < $1.effectiveFrom }) {
            seed = .init(id: legacy.id, effectiveFrom: legacy.effectiveFrom, factor: legacy.factor,
                         reason: "既有生活参考，尚未通过完整记录校准：" + legacy.label)
        } else {
            seed = .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!, effectiveFrom: .distantPast,
                         factor: 1.4, reason: "生活资料不足，暂用未校准参考 1.4")
        }
        return references.filter { $0.id == seed.id && $0.effectiveFrom <= date }.max { $0.effectiveFrom < $1.effectiveFrom } ?? seed
    }

    /// 非日常活动的训练都保留。已有活动能量时用活动口径，不再用同一条记录的毛热量。
    /// 日常活动整包不进这里，避免和所选日活动能量重复。
    private static func localTraining(_ entries: [ProgressHistoryRecord]) -> [EnergyTrainingEvent] {
        EnergyTrainingGrouping.sessions(entries.filter { $0.activity.kind == .workout && !$0.isDailyActivity }.map { record in
            let evidence = record.trainingEvidence
            if let active = record.activeEnergyKilocalories, DailyEnergyTotal.isUsableActive(active) {
                return EnergyTrainingEvent(
                    id: evidence?.id ?? "soma:" + record.activity.id.uuidString,
                    source: evidence?.source ?? "Soma",
                    scope: .active,
                    kilocalories: active,
                    met: nil,
                    durationHours: evidence?.durationHours ?? record.durationSeconds.map { $0 / 3600 },
                    start: evidence?.start,
                    end: evidence?.end
                )
            }
            return evidence ?? .init(
                id: "soma:" + record.activity.id.uuidString, source: "Soma", scope: record.calorieMET == nil ? .unknown : .metGross,
                kilocalories: record.calories, met: record.calorieMET, durationHours: record.durationSeconds.map { $0 / 3600 }, start: nil, end: nil
            )
        })
    }

    private static func review(
        on today: Date, days: [EnergyCalibrationDay], calculation: EnergyDayCalculation,
        contexts: [EnergyContextFacts], facts: EnergyProjectionFacts, output: inout EnergyRuntimeOutput, calendar: Calendar
    ) {
        guard contexts.last(where: { $0.date <= today && $0.learningPaused != nil })?.learningPaused != true else { return }
        let previous = facts.reviews.filter { $0.date <= today }.max { $0.date < $1.date }
        if let previous, (calendar.dateComponents([.day], from: previous.date, to: today).day ?? 0) < 7 {
            return
        }
        guard let start = calendar.date(byAdding: .day, value: -28, to: today) else { return }
        let window = days.filter { $0.date >= start && $0.date < today }
        guard let encoded = try? EnergyInputCoding.encode(window) else { return }
        let evaluation = EnergyCalibration.evaluate(
            days: window, on: today, correction: calculation.input.correction, resting: calculation.input.resting,
            fingerprint: EnergyInputCoding.digest(encoded), previous: previous,
            lastApplied: facts.reviews.filter { $0.delta != 0 && $0.date <= today }.max { $0.date < $1.date }, calendar: calendar
        )
        output.updates.append(.calibration(evaluation))
        if evaluation.delta != 0 {
            let old = calculation.input
            let input = EnergyDayInput(date: old.date, resting: old.resting, weightKG: old.weightKG, reference: old.reference,
                                       nonTrainingKilometers: old.nonTrainingKilometers, walkingCoverageConfirmed: old.walkingCoverageConfirmed,
                                       isEndedDay: old.isEndedDay, training: old.training, correction: evaluation.nextCorrection,
                                       observedNonTrainingSteps: old.observedNonTrainingSteps, stepLengthMeters: old.stepLengthMeters,
                                       restingFormula: old.restingFormula, weightRecordID: old.weightRecordID, weightRecordDate: old.weightRecordDate)
            if var updated = try? EnergyDayCalculator.calculate(input) {
                updated.presentedTotal = calculation.presentedTotal
                updated.presentedSelectedActiveKilocalories = calculation.presentedSelectedActiveKilocalories
                output.calculations[today] = updated
                output.outcomes[today] = .init(estimate: .from(updated), missingReason: nil)
                output.updates.removeAll {
                    if case let .daily(day) = $0 {
                        return day.input.date == today
                    }; return false
                }
                output.updates.append(.daily(updated))
            }
        }
    }
}
