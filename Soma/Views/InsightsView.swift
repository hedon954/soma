import Charts
import SwiftData
import SwiftUI

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var recordCounts = InsightsRecordCounts()
    @State private var snapshot = InsightsScreenSnapshot.empty
    @State private var cacheState = InsightsSnapshotRevisionState()
    @State private var requestedCacheKey: InsightsSnapshotCacheKey?
    @State private var loadPhase = InsightsSnapshotLoadPhase.idle
    @State private var healthEnergy = HealthEnergySnapshot.empty

    var body: some View {
        Group {
            if loadPhase == .failed, cacheState.loadedKey == nil {
                ContentUnavailableView {
                    Label("进展暂时无法加载", systemImage: "arrow.clockwise.circle")
                } description: {
                    Text("读取本机记录时遇到问题。你的数据没有丢失，可以立即重试。")
                } actions: {
                    Button("重新加载") {
                        requestSnapshot(force: true)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("重新读取本机的进展数据")
                }
            } else if loadPhase == .idle || (loadPhase == .loading && cacheState.loadedKey == nil) {
                ProgressView("正在加载进展…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("insights-loading")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                        if loadPhase == .failed {
                            insightsRefreshFailure
                        }

                        Text(snapshot.dateRangeText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(
                            ProgressHomeSection.visible(
                                hasRecentActivities: !snapshot.recentActivities.isEmpty
                            )
                        ) { section in
                            progressHomeSection(section, snapshot: snapshot)
                        }
                    }
                    .padding(AppTheme.pagePadding)
                    .padding(.bottom, 72)
                    .frame(maxWidth: AppTheme.readableContentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("insights-content")
            }
        }
        .appPageBackground()
        .navigationTitle("进展")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 快照请求不参与 TabView 提交选中外观的同一 MainActor 周期。
            await Task.yield()
            requestSnapshotIfNeeded()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: ModelContext.didSave
            )
        ) { notification in
            guard ModelContextSaveImpact.affectsInsights(
                notification,
                in: modelContext
            ) else {
                return
            }
            cacheState.markDataChanged()
            requestSnapshot()
        }
        .task(id: requestedCacheKey) {
            guard let requestedCacheKey else { return }
            await refreshSnapshot(for: requestedCacheKey)
        }
        .refreshable {
            let cacheKey = cacheState.currentKey()
            await refreshSnapshot(for: cacheKey)
        }
    }

    private var insightsRefreshFailure: some View {
        AppCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundStyle(AppTheme.warning)
                    .accessibilityHidden(true)
                Text("最新数据暂时没有刷新，当前内容仍可查看。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("重试") {
                    requestSnapshot(force: true)
                }
                .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func progressHomeSection(
        _ section: ProgressHomeSection,
        snapshot: InsightsScreenSnapshot
    ) -> some View {
        switch section {
        case .trainingOverview:
            ProgressGoalOverviewCard(
                goal: snapshot.fitnessGoal,
                onSelectGoal: selectGoal,
                intakeCalories: snapshot.todayIntakeCalories,
                intakeIsPartial: snapshot.todayIntakeIsPartial,
                intakeBreakdown: snapshot.todayIntakeBreakdown,
                restingCalories: healthEnergy.restingKilocalories
                    ?? snapshot.estimatedRestingCalories,
                restingUsesHealth: healthEnergy.restingKilocalories != nil,
                restingBreakdown: healthEnergy.restingComponents.map(\.progressBreakdown),
                dailyRestingEstimate: snapshot.dailyRestingEstimate,
                restingFormulaInput: snapshot.restingFormulaInput,
                activeCalories: healthEnergy.activeKilocalories
                    ?? snapshot.localActiveCalories,
                activeBreakdown: healthEnergy.activeKilocalories != nil
                    ? healthEnergy.activeComponents.map(\.progressBreakdown)
                    : snapshot.localActiveBreakdown,
                muscleSets: snapshot.weeklyPrimaryMuscleSets,
                trainingDays: snapshot.weekTrainingDays.count,
                trainingDayBreakdown: snapshot.weekTrainingDayBreakdown,
                volume: snapshot.weekVolume,
                volumeBreakdown: snapshot.weekVolumeBreakdown
            )
        case .monthlyTrend:
            MonthlyProgressTrendCard(series: snapshot.monthlyTrendSeries)
        case .conclusion:
            ProgressConclusionCard(
                title: snapshot.conclusionTitle,
                detail: snapshot.conclusionDetail,
                status: snapshot.conclusionStatus
            )
        case .recentActivities:
            HStack(alignment: .center, spacing: 12) {
                SectionHeading(title: "最近活动")
                Spacer()
                NavigationLink {
                    WorkoutHistoryView()
                } label: {
                    progressHistoryShortcut(
                        title: "训练记录",
                        systemImage: "dumbbell.fill",
                        role: .training
                    )
                }
                .buttonStyle(.plain)
                NavigationLink {
                    MealHistoryView()
                } label: {
                    progressHistoryShortcut(
                        title: "饮食记录",
                        systemImage: "fork.knife",
                        role: .meal
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 44)
            AppCard {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(
                            Array(snapshot.recentActivities.enumerated()),
                            id: \.element.id
                        ) { index, activity in
                            NavigationLink {
                                recentActivityDestination(activity)
                            } label: {
                                ProgressRecentActivityRow(activity: activity)
                            }
                            .buttonStyle(.plain)
                            if index < snapshot.recentActivities.count - 1 {
                                Divider()
                                    .overlay(AppTheme.separator)
                            }
                        }
                    }
                }
                .frame(
                    height: ProgressRecentActivityViewport.height(
                        activityCount: snapshot.recentActivities.count
                    )
                )
                .scrollIndicators(
                    snapshot.recentActivities.count
                        > ProgressRecentActivityViewport.maximumVisibleRows
                        ? .visible
                        : .hidden
                )
                .scrollBounceBehavior(.basedOnSize)
            }
        case .allData:
            SectionHeading(title: "数据与全部记录")
            RecentRecordsCard(
                workoutCount: recordCounts.workouts,
                mealCount: recordCounts.meals,
                bodyCount: recordCounts.bodyEntries,
                latestWorkout: snapshot.latestWorkout,
                latestMeal: snapshot.latestMeal,
                latestWeight: snapshot.latestWeight
            )
        case .currentGym:
            NavigationLink {
                GymLibraryView()
            } label: {
                CurrentGymContextCard(
                    gymName: snapshot.currentGymName,
                    coverImagePath: snapshot.currentGymCoverImagePath,
                    note: snapshot.currentGymNote,
                    equipmentCount: snapshot.currentEquipmentCount
                )
            }
            .buttonStyle(.plain)
        case .personalResources:
            AppCard {
                VStack(spacing: 0) {
                    NavigationLink {
                        FootprintsView()
                    } label: {
                        RecordIndexRow(
                            icon: "shoeprints.fill",
                            role: .trend,
                            title: "足迹",
                            count: snapshot.successfulFootprintCount,
                            latest: snapshot.successfulFootprintCount == 0
                                ? "Agent 成功后自动收录"
                                : "回顾你的文字与影像"
                        )
                    }

                    Divider()
                        .padding(.leading, 44)

                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        RecordIndexRow(
                            icon: "books.vertical",
                            role: .training,
                            title: "动作库",
                            count: snapshot.activeExerciseCount,
                            latest: snapshot.activeExerciseCount > 0
                                ? "查看动作详情与受力"
                                : "随训练自然形成"
                        )
                    }
                    .accessibilityIdentifier("exercise-library-link")
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func selectGoal(_ goal: FitnessGoal?) {
        var descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let profile: UserProfile
        if let existing = try? modelContext.fetch(descriptor).first {
            profile = existing
        } else {
            profile = UserProfile()
            modelContext.insert(profile)
        }
        profile.fitnessGoal = goal?.rawValue ?? ""
        profile.updatedAt = .now
        do {
            try modelContext.save()
            snapshot.fitnessGoal = goal
        } catch {
            modelContext.rollback()
            requestSnapshot(force: true)
        }
    }

    private func progressHistoryShortcut(
        title: String,
        systemImage: String,
        role: AppSemanticRole
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
            Text(title)
                .font(.caption.weight(.medium))
                .underline(true, color: role.accent)
        }
        .foregroundStyle(role.accent)
        .frame(minHeight: AppTheme.minimumTapTarget)
        .contentShape(Rectangle())
    }

    @MainActor
    private func requestSnapshotIfNeeded() {
        requestSnapshot()
    }

    @MainActor
    private func requestSnapshot(force: Bool = false) {
        guard let cacheKey = cacheState.requestKey(
            excluding: requestedCacheKey,
            force: force
        ) else { return }
        loadPhase = .loading
        requestedCacheKey = cacheKey
    }

    @MainActor
    private func refreshSnapshot(for cacheKey: InsightsSnapshotCacheKey) async {
        let interval = AppPerformance.begin(
            .derivedSnapshot,
            detail: "screen=insights,kind=refresh"
        )
        let container = modelContext.container
        let worker = Task.detached(priority: .userInitiated) {
            let loader = InsightsSnapshotLoader(modelContainer: container)
            return try await loader.load()
        }
        async let healthSnapshot = HealthEnergyReader.today()
        do {
            let payload = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { throw CancellationError() }
            guard cacheState.acceptsCompletion(for: cacheKey) else {
                if requestedCacheKey == cacheKey {
                    requestedCacheKey = nil
                }
                requestSnapshot()
                AppPerformance.end(
                    interval,
                    detail: "screen=insights,kind=refresh,stale=true"
                )
                return
            }
            snapshot = payload.snapshot
            healthEnergy = await healthSnapshot
            recordCounts = payload.counts
            loadPhase = .loaded
            if requestedCacheKey == cacheKey {
                requestedCacheKey = nil
            }
            AppPerformance.end(interval, detail: "screen=insights,kind=refresh")
        } catch is CancellationError {
            AppPerformance.end(
                interval,
                detail: "screen=insights,kind=refresh,cancelled=true"
            )
        } catch {
            guard !Task.isCancelled else {
                AppPerformance.end(
                    interval,
                    detail: "screen=insights,kind=refresh,cancelled=true"
                )
                return
            }
            if requestedCacheKey == cacheKey {
                requestedCacheKey = nil
            }
            if cacheState.currentKey() == cacheKey {
                loadPhase = .failed
            }
            AppPerformance.end(
                interval,
                detail: "screen=insights,kind=refresh,failed=true"
            )
        }
    }

    private func recentActivityDestination(_ activity: ProgressRecentActivity) -> some View {
        ProgressRecentActivityDestination(activity: activity)
    }
}

private struct InsightsSnapshotPayload: Sendable {
    let snapshot: InsightsScreenSnapshot
    let counts: InsightsRecordCounts
}

private extension HealthEnergyComponent {
    var progressBreakdown: ProgressMetricBreakdownItem {
        ProgressMetricBreakdownItem(
            label: sourceName,
            value: "\(kilocalories) kcal"
        )
    }
}

@ModelActor
private actor InsightsSnapshotLoader {
    func load(now: Date = .now) throws -> InsightsSnapshotPayload {
        try Task.checkCancellation()
        let calendar = Calendar.current
        let trendStart = calendar.date(byAdding: .day, value: -95, to: now)
            ?? .distantPast
        let mealTrendStart = calendar.date(
            byAdding: .day,
            value: -30,
            to: calendar.startOfDay(for: now)
        ) ?? .distantPast

        var workoutDescriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.date >= trendStart },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        workoutDescriptor.fetchLimit = 1000

        var mealDescriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.date >= mealTrendStart },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        mealDescriptor.fetchLimit = 1000

        var bodyDescriptor = FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.date >= trendStart },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        bodyDescriptor.fetchLimit = 500
        var latestWeightDescriptor = FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.weight != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        latestWeightDescriptor.fetchLimit = 1

        var currentGymDescriptor = FetchDescriptor<GymProfile>(
            predicate: #Predicate { $0.isCurrent },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        currentGymDescriptor.fetchLimit = 1
        var fallbackGymDescriptor = FetchDescriptor<GymProfile>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        fallbackGymDescriptor.fetchLimit = 1

        var sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.startedAt >= trendStart },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        sessionDescriptor.fetchLimit = 500
        var profileDescriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        profileDescriptor.fetchLimit = 1

        let workouts = try modelContext.fetch(workoutDescriptor)
        let meals = try modelContext.fetch(mealDescriptor)
        let bodyEntries = try modelContext.fetch(bodyDescriptor)
        let latestRecordedWeight = try modelContext.fetch(latestWeightDescriptor).first?.weight
        let profile = try modelContext.fetch(profileDescriptor).first
        try Task.checkCancellation()
        let currentGym = try modelContext.fetch(currentGymDescriptor).first
            ?? modelContext.fetch(fallbackGymDescriptor).first
        let currentGymID = currentGym?.id
        let currentEquipmentCount: Int = if let currentGymID {
            try modelContext.fetchCount(
                FetchDescriptor<GymEquipment>(
                    predicate: #Predicate { $0.gymID == currentGymID }
                )
            )
        } else {
            0
        }
        let successfulFootprintCount = try InsightsCountQueries
            .successfulFootprintCount(in: modelContext)
        let activeExerciseCount = try modelContext.fetchCount(
            FetchDescriptor<ExerciseDefinition>(
                predicate: #Predicate { $0.archivedAt == nil }
            )
        )
        let workoutSessions = try modelContext.fetch(sessionDescriptor)
        // 趋势窗口只需要这批会话的子图。直接沿当前关系读取，避免全库
        // 2,000/5,000 行扫描、无关旧数据抢占上限以及错误的趋势截断。
        let exercisePerformances = workoutSessions
            .flatMap(\.performances)
            .sorted { lhs, rhs in lhs.order < rhs.order }
        let workoutSets = exercisePerformances
            .flatMap(\.workoutSets)
            .sorted { lhs, rhs in lhs.order < rhs.order }
        try Task.checkCancellation()

        let input = InsightsSnapshotInput(
            workouts: workouts,
            meals: meals,
            bodyEntries: bodyEntries,
            latestRecordedWeight: latestRecordedWeight,
            gyms: currentGym.map { [$0] } ?? [],
            successfulFootprintCount: successfulFootprintCount,
            currentEquipmentCount: currentEquipmentCount,
            activeExerciseCount: activeExerciseCount,
            workoutSessions: workoutSessions,
            exercisePerformances: exercisePerformances,
            workoutSets: workoutSets,
            profile: profile
        )
        return try InsightsSnapshotPayload(
            snapshot: InsightsScreenSnapshot(
                input: input,
                calendar: calendar,
                now: now
            ),
            counts: InsightsCountQueries.recordCounts(in: modelContext)
        )
    }
}

private struct ProgressRecentActivityDestination: View {
    let activity: ProgressRecentActivity

    var body: some View {
        switch activity.kind {
        case .workout:
            ProgressWorkoutDestination(recordID: activity.id)
        case .meal:
            ProgressMealDestination(recordID: activity.id)
        case .body:
            ProgressBodyDestination(recordID: activity.id)
        }
    }
}

private struct ProgressWorkoutDestination: View {
    @Query private var records: [WorkoutEntry]

    init(recordID: UUID) {
        var descriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.id == recordID }
        )
        descriptor.fetchLimit = 1
        _records = Query(descriptor)
    }

    var body: some View {
        if let record = records.first {
            WorkoutRecordDetailView(workout: record)
        } else {
            ProgressView()
        }
    }
}

private struct ProgressMealDestination: View {
    @Query private var records: [MealEntry]

    init(recordID: UUID) {
        var descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.id == recordID }
        )
        descriptor.fetchLimit = 1
        _records = Query(descriptor)
    }

    var body: some View {
        if let record = records.first {
            MealRecordDetailView(meal: record)
        } else {
            ProgressView()
        }
    }
}

private struct ProgressBodyDestination: View {
    @Query private var records: [BodyEntry]

    init(recordID: UUID) {
        var descriptor = FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.id == recordID }
        )
        descriptor.fetchLimit = 1
        _records = Query(descriptor)
    }

    var body: some View {
        if let record = records.first {
            BodyRecordDetailView(entry: record)
        } else {
            ProgressView()
        }
    }
}

struct InsightsRecordCounts: Equatable, Sendable {
    var workouts = 0
    var meals = 0
    var bodyEntries = 0
}

private struct WeightTrendPoint: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let weight: Double
}

struct ProgressMuscleSetSummary: Identifiable, Sendable {
    let name: String
    let sets: Int
    var id: String {
        name
    }
}

private struct InsightsSnapshotInput: Sendable {
    struct Workout: Sendable {
        let id: UUID
        let date: Date
        let exercise: String
        let setEntriesData: Data
        let legacySets: Int?
        let legacyReps: Int?
        let legacyWeight: Double?
        let estimatedCalories: Int?
        let calorieMET: Double?
        let externalSource: String?
        let primaryMuscles: [String]
        let sourceWorkoutSessionID: UUID?
        let sourcePerformanceID: UUID?

        var resolved: ResolvedWorkout {
            let entries = setEntriesData.isEmpty
                ? []
                : (WorkoutSetStorage.decode(setEntriesData) ?? [])
            let completeVolumes = entries.compactMap { entry -> Double? in
                guard let reps = entry.reps,
                      let weight = entry.externalWeightKG,
                      reps > 0,
                      weight > 0
                else {
                    return nil
                }
                return Double(reps) * weight
            }
            let volume: Double? = if !entries.isEmpty {
                completeVolumes.isEmpty ? nil : completeVolumes.reduce(0, +)
            } else if setEntriesData.isEmpty,
                      let legacySets,
                      let legacyReps,
                      let legacyWeight
            {
                Double(legacySets * legacyReps) * legacyWeight
            } else {
                nil
            }
            return ResolvedWorkout(
                id: id,
                date: date,
                exercise: exercise,
                volume: volume,
                setCount: Self.setCount(entries: entries, legacySets: legacySets),
                activeCalories: Self.activeCalories(
                    estimatedCalories: estimatedCalories,
                    met: calorieMET,
                    externalSource: externalSource
                ),
                primaryMuscles: primaryMuscles,
                setSummary: Self.setSummary(entries: entries),
                sourceWorkoutSessionID: sourceWorkoutSessionID,
                sourcePerformanceID: sourcePerformanceID
            )
        }

        private static func activeCalories(
            estimatedCalories: Int?,
            met: Double?,
            externalSource: String?
        ) -> Int? {
            guard let estimatedCalories else { return nil }
            if externalSource != nil {
                return estimatedCalories
            }
            guard let met, met > 1 else { return nil }
            return Int((Double(estimatedCalories) * (met - 1) / met).rounded())
        }

        private static func setCount(
            entries: [WorkoutSetEvidence],
            legacySets: Int?
        ) -> Int {
            guard !entries.isEmpty else { return max(legacySets ?? 0, 0) }
            let workingEntries = entries.filter { $0.kind != .warmup }
            let logicalIndexes = Set(workingEntries.compactMap(\.logicalSetIndex))
            return logicalIndexes.isEmpty ? workingEntries.count : logicalIndexes.count
        }

        private static func setSummary(entries: [WorkoutSetEvidence]) -> String? {
            guard !entries.isEmpty else { return nil }
            let reps = entries.compactMap(\.reps)
            let weights = entries.compactMap(\.externalWeightKG)
            let representativeReps = reps.count == entries.count && Set(reps).count == 1
                ? reps.first
                : nil
            let representativeWeight = weights.count == entries.count && Set(weights).count == 1
                ? weights.first
                : nil
            let logicalIndexes = Set(entries.compactMap(\.logicalSetIndex))
            let setCount = logicalIndexes.isEmpty ? entries.count : logicalIndexes.count
            if let representativeReps, let representativeWeight {
                return "\(setCount)组 × \(representativeReps)次 · \(representativeWeight.formatted())kg"
            }
            return entries.enumerated().map { index, entry in
                var parts = ["第\(entry.logicalSetIndex ?? index + 1)组"]
                switch entry.side {
                case .some(.left):
                    parts.append("左侧")
                case .some(.right):
                    parts.append("右侧")
                case nil, .some(.none):
                    break
                }
                if let weight = entry.externalWeightKG {
                    parts.append("\(weight.formatted())kg")
                }
                if let reps = entry.reps {
                    parts.append("\(reps)次")
                } else if let seconds = entry.durationSeconds {
                    parts.append("\(seconds)秒")
                }
                return parts.joined(separator: " ")
            }.joined(separator: "，")
        }
    }

    struct ResolvedWorkout: Sendable {
        let id: UUID
        let date: Date
        let exercise: String
        let volume: Double?
        let setCount: Int
        let activeCalories: Int?
        let primaryMuscles: [String]
        let setSummary: String?
        let sourceWorkoutSessionID: UUID?
        let sourcePerformanceID: UUID?
    }

    struct Meal: Sendable {
        let id: UUID
        let date: Date
        let title: String
        let mealType: String
        let calories: Int?
    }

    struct Body: Sendable {
        let id: UUID
        let date: Date
        let weight: Double?
        let notes: String
    }

    struct Gym: Sendable {
        let id: UUID
        let name: String
        let notes: String
        let coverImagePath: String?
        let isCurrent: Bool
    }

    struct Session: Sendable {
        let id: UUID
        let startedAt: Date
        let status: WorkoutSessionStatus
    }

    struct Performance: Sendable {
        let id: UUID
        let sessionID: UUID
        let workoutProjectionSuppressed: Bool
    }

    struct SetValue: Sendable {
        let performanceID: UUID
        let status: WorkoutSetStatus
        let completedVolume: Double?
    }

    struct Profile: Sendable {
        let fitnessGoal: FitnessGoal?
        let biologicalSex: BiologicalSex
        let birthDate: Date?
        let height: Double?
    }

    let workouts: [Workout]
    let meals: [Meal]
    let bodyEntries: [Body]
    let latestRecordedWeight: Double?
    let gyms: [Gym]
    let successfulFootprintCount: Int
    let currentEquipmentCount: Int
    let activeExerciseCount: Int
    let workoutSessions: [Session]
    let exercisePerformances: [Performance]
    let workoutSets: [SetValue]
    let profile: Profile?

    static let empty = InsightsSnapshotInput()

    private init() {
        workouts = []
        meals = []
        bodyEntries = []
        latestRecordedWeight = nil
        gyms = []
        successfulFootprintCount = 0
        currentEquipmentCount = 0
        activeExerciseCount = 0
        workoutSessions = []
        exercisePerformances = []
        workoutSets = []
        profile = nil
    }

    init(
        workouts: [WorkoutEntry],
        meals: [MealEntry],
        bodyEntries: [BodyEntry],
        latestRecordedWeight: Double?,
        gyms: [GymProfile],
        successfulFootprintCount: Int,
        currentEquipmentCount: Int,
        activeExerciseCount: Int,
        workoutSessions: [WorkoutSession],
        exercisePerformances: [ExercisePerformance],
        workoutSets: [WorkoutSet],
        profile: UserProfile?
    ) {
        self.workouts = workouts.map {
            Workout(
                id: $0.id,
                date: $0.date,
                exercise: $0.exercise,
                setEntriesData: $0.setEntriesData,
                legacySets: $0.sets,
                legacyReps: $0.reps,
                legacyWeight: $0.weight,
                estimatedCalories: $0.estimatedCalories,
                calorieMET: $0.calorieMET,
                externalSource: $0.externalSource,
                primaryMuscles: $0.exerciseDefinition?.primaryMuscles ?? [],
                sourceWorkoutSessionID: $0.sourceWorkoutSessionID,
                sourcePerformanceID: $0.sourcePerformanceID
            )
        }
        self.meals = meals.map {
            Meal(
                id: $0.id,
                date: $0.date,
                title: $0.title,
                mealType: $0.mealTypeRaw,
                calories: $0.calories
            )
        }
        self.bodyEntries = bodyEntries.map {
            Body(id: $0.id, date: $0.date, weight: $0.weight, notes: $0.notes)
        }
        self.latestRecordedWeight = latestRecordedWeight
        self.gyms = gyms.map {
            Gym(
                id: $0.id,
                name: $0.name,
                notes: $0.notes,
                coverImagePath: $0.coverImagePath,
                isCurrent: $0.isCurrent
            )
        }
        self.successfulFootprintCount = successfulFootprintCount
        self.currentEquipmentCount = currentEquipmentCount
        self.activeExerciseCount = activeExerciseCount
        self.workoutSessions = workoutSessions.map {
            Session(id: $0.id, startedAt: $0.startedAt, status: $0.status)
        }
        self.exercisePerformances = exercisePerformances.map {
            Performance(
                id: $0.id,
                sessionID: $0.sessionID,
                workoutProjectionSuppressed: $0.workoutProjectionSuppressed
            )
        }
        self.workoutSets = workoutSets.map {
            SetValue(
                performanceID: $0.performanceID,
                status: $0.status,
                completedVolume: $0.completedVolume
            )
        }
        self.profile = profile.map {
            Profile(
                fitnessGoal: FitnessGoal(rawValue: $0.fitnessGoal),
                biologicalSex: $0.biologicalSex,
                birthDate: $0.birthDate,
                height: $0.height
            )
        }
    }
}

private struct InsightsScreenSnapshot: Sendable {
    static let empty = InsightsScreenSnapshot(input: .empty)

    let dateRangeText: String
    let weekTrainingCount: Int
    let weekVolume: Double?
    let weekWeightChange: Double?
    let weekTrainingDays: Set<Date>
    let trainingDayCounts: [Date: Int]
    let volumePoints: [TrainingVolumePoint]
    let recentActivities: [ProgressRecentActivity]
    let weightedBodyEntries: [WeightTrendPoint]
    let latestWorkout: String?
    let latestMeal: String?
    let latestWeight: Double?
    let currentGymName: String
    let currentGymCoverImagePath: String?
    let currentGymNote: String?
    let currentEquipmentCount: Int
    let successfulFootprintCount: Int
    let activeExerciseCount: Int
    var fitnessGoal: FitnessGoal?
    let todayIntakeCalories: Int?
    let todayIntakeIsPartial: Bool
    let todayIntakeBreakdown: [ProgressMetricBreakdownItem]
    let localActiveCalories: Int?
    let localActiveBreakdown: [ProgressMetricBreakdownItem]
    let estimatedRestingCalories: Int?
    let dailyRestingEstimate: Double?
    let restingFormulaInput: RestingEnergyFormulaInput?
    let monthlyTrendSeries: [ProgressTrendSeries]
    let weeklyPrimaryMuscleSets: [ProgressMuscleSetSummary]
    let weekTrainingDayBreakdown: [ProgressMetricBreakdownItem]
    let weekVolumeBreakdown: [ProgressMetricBreakdownItem]

    var conclusionTitle: String {
        switch weekTrainingCount {
        case 0: "等待新的训练节奏"
        case 1 ... 2: "训练正在积累"
        default: "训练节奏稳定"
        }
    }

    var conclusionDetail: String {
        switch weekTrainingCount {
        case 0: "最近 7 天还没有完整训练记录。"
        case 1 ... 2: "本周完成 \(weekTrainingCount) 次训练，继续保持规律即可。"
        default: "本周完成 \(weekTrainingCount) 次训练，频率比单次数字更值得关注。"
        }
    }

    var conclusionStatus: AppStatusRole {
        switch weekTrainingCount {
        case 0: .neutral
        case 1 ... 2: .attention
        default: .positive
        }
    }

    init(
        input: InsightsSnapshotInput,
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        let workouts = input.workouts.map(\.resolved)
        fitnessGoal = input.profile?.fitnessGoal
        let weekStart = calendar.date(byAdding: .day, value: -6, to: now)
            ?? .distantPast
        let todayStart = calendar.startOfDay(for: now)
        let monthStart = calendar.date(byAdding: .day, value: -29, to: todayStart)
            ?? .distantPast
        let todayMeals = input.meals.filter { $0.date >= todayStart && $0.date <= now }
        let knownMealCalories = todayMeals.compactMap(\.calories)
        todayIntakeCalories = knownMealCalories.isEmpty
            ? nil
            : knownMealCalories.reduce(0, +)
        todayIntakeIsPartial = todayMeals.contains { $0.calories == nil }
        todayIntakeBreakdown = todayMeals.sorted { $0.date < $1.date }.map {
            ProgressMetricBreakdownItem(
                label: "\($0.mealType) · \($0.title)",
                value: $0.calories.map { "\($0) kcal" } ?? "未记录"
            )
        }
        let todayWorkouts = workouts.filter { $0.date >= todayStart && $0.date <= now }
        let activeValues = todayWorkouts.compactMap(\.activeCalories)
        localActiveCalories = activeValues.isEmpty ? nil : activeValues.reduce(0, +)
        localActiveBreakdown = todayWorkouts.sorted { $0.date < $1.date }.map {
            ProgressMetricBreakdownItem(
                label: $0.exercise,
                value: $0.activeCalories.map { "\($0) kcal" } ?? "未计算"
            )
        }
        let completedSessions = input.workoutSessions.filter {
            $0.status == .completed || $0.status == .abandoned
        }
        let trainingDates = workouts
            .filter { $0.sourceWorkoutSessionID == nil }
            .map(\.date) + completedSessions.map(\.startedAt)
        let dayCounts = trainingDates.reduce(into: [Date: Int]()) { counts, date in
            counts[calendar.startOfDay(for: date), default: 0] += 1
        }
        trainingDayCounts = dayCounts
        let recentTrainingDays = Set(
            dayCounts.keys.filter { $0 >= calendar.startOfDay(for: weekStart) }
        )
        weekTrainingDays = recentTrainingDays
        weekTrainingDayBreakdown = recentTrainingDays.sorted(by: >).map { date in
            ProgressMetricBreakdownItem(
                label: date.formatted(.dateTime.month().day()),
                value: "\(dayCounts[date] ?? 0) 条训练"
            )
        }

        let standaloneCount = workouts.count {
            $0.sourceWorkoutSessionID == nil && $0.date >= weekStart
        }
        let projectedSessionIDs = Set(workouts.compactMap { workout in
            workout.date >= weekStart ? workout.sourceWorkoutSessionID : nil
        })
        let recentCompletedSessionIDs = Set(completedSessions.compactMap { session in
            session.startedAt >= weekStart ? session.id : nil
        })
        weekTrainingCount = standaloneCount
            + projectedSessionIDs.union(recentCompletedSessionIDs).count

        var dailyVolumes = workouts.reduce(into: [Date: Double]()) { result, workout in
            guard let volume = workout.volume, volume > 0 else { return }
            result[calendar.startOfDay(for: workout.date), default: 0] += volume
        }
        let performancesByID = Dictionary(
            uniqueKeysWithValues: input.exercisePerformances.map { ($0.id, $0) }
        )
        let sessionsByID = Dictionary(
            uniqueKeysWithValues: completedSessions.map { ($0.id, $0) }
        )
        let projectedPerformanceIDs = Set(workouts.compactMap(\.sourcePerformanceID))
        for set in input.workoutSets where set.status == .completed {
            guard let volume = set.completedVolume,
                  volume > 0,
                  let performance = performancesByID[set.performanceID],
                  !projectedPerformanceIDs.contains(performance.id),
                  !performance.workoutProjectionSuppressed,
                  let session = sessionsByID[performance.sessionID]
            else {
                continue
            }
            dailyVolumes[
                calendar.startOfDay(for: session.startedAt),
                default: 0
            ] += volume
        }
        let resolvedVolumePoints = dailyVolumes.map {
            TrainingVolumePoint(date: $0.key, volume: $0.value)
        }.sorted { $0.date < $1.date }
        volumePoints = resolvedVolumePoints
        let recentVolume = resolvedVolumePoints
            .filter { $0.date >= weekStart }
            .reduce(0) { $0 + $1.volume }
        weekVolume = recentVolume > 0 ? recentVolume : nil
        weekVolumeBreakdown = resolvedVolumePoints
            .filter { $0.date >= calendar.startOfDay(for: weekStart) }
            .sorted { $0.date > $1.date }
            .map {
                ProgressMetricBreakdownItem(
                    label: $0.date.formatted(.dateTime.month().day()),
                    value: "\($0.volume.formatted(.number.precision(.fractionLength(0)))) kg"
                )
            }

        weightedBodyEntries = input.bodyEntries
            .compactMap { entry in
                entry.weight.map {
                    WeightTrendPoint(id: entry.id, date: entry.date, weight: $0)
                }
            }
            .sorted { $0.date < $1.date }
        let latestKnownWeight = input.latestRecordedWeight
            ?? weightedBodyEntries.last?.weight
        let age = input.profile?.birthDate.flatMap {
            calendar.dateComponents([.year], from: $0, to: now).year
        }
        let dailyResting = RestingEnergyCalculator.dailyKilocalories(
            weightKG: latestKnownWeight,
            heightCM: input.profile?.height,
            age: age,
            biologicalSex: input.profile?.biologicalSex ?? .unspecified
        )
        estimatedRestingCalories = RestingEnergyCalculator.elapsedTodayKilocalories(
            daily: dailyResting,
            now: now,
            calendar: calendar
        )
        dailyRestingEstimate = dailyResting
        if let latestKnownWeight,
           let height = input.profile?.height,
           let age,
           let profile = input.profile,
           let dailyResting
        {
            restingFormulaInput = RestingEnergyFormulaInput(
                weightKG: latestKnownWeight,
                heightCM: height,
                age: age,
                biologicalSex: profile.biologicalSex,
                dailyKilocalories: dailyResting
            )
        } else {
            restingFormulaInput = nil
        }

        monthlyTrendSeries = [
            ProgressTrendProjection.dailySum(
                metric: .trainingVolume,
                samples: dailyVolumes.map {
                    ProgressTrendSample(date: $0.key, value: $0.value)
                },
                start: monthStart,
                end: now,
                calendar: calendar
            ),
            ProgressTrendProjection.dailySum(
                metric: .calorieIntake,
                samples: input.meals.map {
                    ProgressTrendSample(
                        date: $0.date,
                        value: $0.calories.map(Double.init)
                    )
                },
                start: monthStart,
                end: now,
                calendar: calendar
            ),
            ProgressTrendProjection.dailyLatest(
                metric: .weight,
                samples: input.bodyEntries.map {
                    ProgressTrendSample(date: $0.date, value: $0.weight)
                },
                start: monthStart,
                end: now,
                calendar: calendar
            )
        ]

        var muscleSets: [String: Int] = [:]
        for workout in workouts where workout.date >= weekStart && workout.setCount > 0 {
            for group in MuscleGroupMapping.resolve(workout.primaryMuscles) {
                muscleSets[group.displayName, default: 0] += workout.setCount
            }
        }
        weeklyPrimaryMuscleSets = muscleSets.map {
            ProgressMuscleSetSummary(name: $0.key, sets: $0.value)
        }.sorted {
            $0.sets == $1.sets ? $0.name < $1.name : $0.sets > $1.sets
        }
        let weekWeights = weightedBodyEntries.filter { $0.date >= weekStart }
        if weekWeights.count >= 2 {
            weekWeightChange = (weekWeights.last?.weight ?? 0)
                - (weekWeights.first?.weight ?? 0)
        } else {
            weekWeightChange = nil
        }

        let workoutActivities = workouts.map {
            ProgressRecentActivity(
                id: $0.id,
                kind: .workout,
                date: $0.date,
                title: $0.exercise,
                detail: $0.setSummary ?? "训练记录",
                metric: $0.volume.map { "\($0.formatted()) kg" }
            )
        }
        let mealActivities = input.meals.map {
            ProgressRecentActivity(
                id: $0.id,
                kind: .meal,
                date: $0.date,
                title: $0.title,
                detail: $0.mealType,
                metric: $0.calories.map { "\($0) kcal" }
            )
        }
        let bodyActivities = input.bodyEntries.map {
            ProgressRecentActivity(
                id: $0.id,
                kind: .body,
                date: $0.date,
                title: "身体记录",
                detail: $0.notes.isEmpty ? "身体变化" : $0.notes,
                metric: $0.weight.map { "\($0.formatted()) kg" }
            )
        }
        recentActivities = Array(
            (workoutActivities + mealActivities + bodyActivities)
                .sorted { $0.date > $1.date }
                .prefix(30)
        )

        latestWorkout = workouts.first?.exercise
        latestMeal = input.meals.first?.title
        latestWeight = latestKnownWeight

        let currentGym = input.gyms.first(where: \.isCurrent) ?? input.gyms.first
        currentGymName = currentGym?.name ?? "尚未建立"
        currentGymCoverImagePath = currentGym?.coverImagePath
        currentGymNote = currentGym?.notes
        currentEquipmentCount = input.currentEquipmentCount
        successfulFootprintCount = input.successfulFootprintCount
        activeExerciseCount = input.activeExerciseCount

        let format = Date.FormatStyle(date: .abbreviated, time: .omitted)
        dateRangeText = "\(monthStart.formatted(format))—\(now.formatted(format))"
    }
}

private struct RecentRecordsCard: View {
    let workoutCount: Int
    let mealCount: Int
    let bodyCount: Int
    let latestWorkout: String?
    let latestMeal: String?
    let latestWeight: Double?

    /// PRD 020 修订：足迹与动作库独立成卡后，这里只保留三类业务记录。
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近记录")
                .font(.headline)

            AppCard {
                VStack(spacing: 0) {
                    NavigationLink {
                        WorkoutHistoryView()
                    } label: {
                        RecordIndexRow(
                            icon: "figure.strengthtraining.traditional",
                            role: .training,
                            title: "训练记录",
                            count: workoutCount,
                            latest: latestWorkout ?? "暂无记录"
                        )
                    }

                    Divider()
                        .padding(.leading, 44)

                    NavigationLink {
                        MealHistoryView()
                    } label: {
                        RecordIndexRow(
                            icon: "fork.knife",
                            role: .meal,
                            title: "饮食记录",
                            count: mealCount,
                            latest: latestMeal ?? "暂无记录"
                        )
                    }

                    Divider()
                        .padding(.leading, 44)

                    NavigationLink {
                        BodyHistoryView()
                    } label: {
                        RecordIndexRow(
                            icon: "scalemass",
                            role: .body,
                            title: "体重记录",
                            count: bodyCount,
                            latest: latestWeight.map { String(format: "%.1f kg", $0) } ?? "暂无记录"
                        )
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RecordIndexRow: View {
    let icon: String
    let role: AppSemanticRole
    let title: String
    let count: Int
    let latest: String

    var body: some View {
        HStack(spacing: 12) {
            SemanticIconBadge(systemImage: icon, role: role, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("最近：\(latest)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(count) 条")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
    }
}

private struct ContributionCard: View {
    let trainingDayCounts: [Date: Int]
    var embedded = false

    var body: some View {
        if embedded {
            content
        } else {
            AppCard { content }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !embedded {
                MetricHeading(title: "训练连续性", role: .consistency)
            }

            HStack(alignment: .top, spacing: 7) {
                VStack(spacing: 4) {
                    Color.clear.frame(width: 16, height: 14)
                    ForEach(0 ..< 7, id: \.self) { row in
                        Text(weekdayLabel(for: row))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 13, alignment: .trailing)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            ForEach(Array(weeks.enumerated()), id: \.element.id) { index, _ in
                                Color.clear
                                    .frame(width: 13, height: 14)
                                    .overlay(alignment: .leading) {
                                        Text(monthLabel(at: index))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                            .fixedSize()
                                    }
                            }
                        }

                        HStack(alignment: .top, spacing: 4) {
                            ForEach(weeks) { week in
                                VStack(spacing: 4) {
                                    ForEach(week.days, id: \.self) { day in
                                        contributionCell(for: day)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 4) {
                Text("过去 13 周")
                Spacer()
                Text("少")
                ForEach(0 ..< 5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: level))
                        .frame(width: 10, height: 10)
                }
                Text("多")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var weeks: [ContributionWeek] {
        let calendar = Calendar.current
        let today = Calendar.current.startOfDay(for: .now)
        let threshold = calendar.date(byAdding: .day, value: -90, to: today) ?? today
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: threshold)?.start ?? threshold
        let lastWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let weekCount = max(1, (calendar.dateComponents([.weekOfYear], from: firstWeek, to: lastWeek).weekOfYear ?? 0) + 1)

        return (0 ..< weekCount).compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: offset, to: firstWeek) else { return nil }
            let days = (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            return ContributionWeek(start: start, days: days)
        }
    }

    private func contributionCell(for day: Date) -> some View {
        let isFuture = day > Calendar.current.startOfDay(for: .now)
        let count = trainingDayCounts[Calendar.current.startOfDay(for: day), default: 0]

        return RoundedRectangle(cornerRadius: 3)
            .fill(isFuture ? Color.clear : color(for: count))
            .frame(width: 13, height: 13)
            .accessibilityLabel(
                isFuture
                    ? ""
                    : "\(day.formatted(date: .abbreviated, time: .omitted))，\(count) 次训练"
            )
            .accessibilityHidden(isFuture)
    }

    private func weekdayLabel(for row: Int) -> String {
        guard [1, 3, 5].contains(row), let day = weeks.first?.days[row] else { return "" }
        return day.formatted(.dateTime.weekday(.narrow))
    }

    private func monthLabel(at index: Int) -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: weeks[index].start)
        if index == 0 {
            let visibleWeeks = weeks.prefix { calendar.component(.month, from: $0.start) == month }.count
            return visibleWeeks >= 2 ? "\(month)月" : ""
        } else {
            let previousMonth = calendar.component(.month, from: weeks[index - 1].start)
            guard month != previousMonth else { return "" }
        }
        return "\(month)月"
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0: Color.secondary.opacity(0.1)
        case 1: AppMetricRole.consistency.accent.opacity(0.42)
        case 2: AppMetricRole.consistency.accent.opacity(0.7)
        default: AppMetricRole.consistency.accent
        }
    }
}

private struct ContributionWeek: Identifiable {
    let start: Date
    let days: [Date]
    var id: Date {
        start
    }
}

private enum TrendRange: Int, CaseIterable, Identifiable {
    case week = 7
    case twoWeeks = 14
    case month = 30
    case quarter = 90

    var id: Int {
        rawValue
    }

    var label: String {
        switch self {
        case .week: "周"
        case .twoWeeks: "双周"
        case .month: "月"
        case .quarter: "季"
        }
    }

    var duration: TimeInterval {
        TimeInterval(rawValue * 24 * 60 * 60)
    }
}

private struct WeightTrendCard: View {
    let entries: [WeightTrendPoint]
    @State private var range: TrendRange = .month
    @State private var scrollStart = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now

    private var visibleEnd: Date {
        scrollStart.addingTimeInterval(range.duration)
    }

    private var yDomain: ClosedRange<Double> {
        guard let first = entries.first else { return -1.5 ... 101.5 }
        var minimum = first.weight
        var maximum = first.weight
        for entry in entries.dropFirst() {
            minimum = min(minimum, entry.weight)
            maximum = max(maximum, entry.weight)
        }
        return (minimum - 1.5) ... (maximum + 1.5)
    }

    private var xDomain: ClosedRange<Date> {
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .now
        let firstEntry = entries.first?.date ?? .now
        return min(ninetyDaysAgo, firstEntry) ... Date.now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetricHeading(title: "体重趋势", role: .body)
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("时间粒度", selection: $range) {
                        ForEach(TrendRange.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("\(scrollStart.formatted(.dateTime.year().month().day())) – \(visibleEnd.formatted(.dateTime.month().day()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Chart(entries) { entry in
                        LineMark(
                            x: .value("日期", entry.date),
                            y: .value("体重", entry.weight)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: 2.25,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .foregroundStyle(AppMetricRole.body.accent)
                        PointMark(
                            x: .value("日期", entry.date),
                            y: .value("体重", entry.weight)
                        )
                        .foregroundStyle(AppMetricRole.body.accent)
                    }
                    .chartScrollableAxes(.horizontal)
                    .chartXScale(domain: xDomain)
                    .chartXVisibleDomain(length: range.duration)
                    .chartScrollPosition(x: $scrollStart)
                    .chartYScale(domain: yDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                                .foregroundStyle(AppTheme.separator)
                            AxisTick()
                                .foregroundStyle(AppTheme.separator)
                            AxisValueLabel(format: .dateTime.month().day())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine()
                                .foregroundStyle(AppTheme.separator)
                            AxisTick()
                                .foregroundStyle(AppTheme.separator)
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 180)
                }
                .onChange(of: range) {
                    scrollStart = Calendar.current.date(
                        byAdding: .day,
                        value: -range.rawValue,
                        to: .now
                    ) ?? .now
                }
            }
        }
    }
}

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

/// 当前健身房是 Agent 的高频上下文，首屏直接呈现名称、封面和器械摘要。
private struct CurrentGymContextCard: View {
    let gymName: String
    let coverImagePath: String?
    let note: String?
    let equipmentCount: Int

    var body: some View {
        AppCard {
            HStack(spacing: 12) {
                LocalImageView(path: coverImagePath)
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Label("当前健身房", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.trainingAccent)
                    Text(gymName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(contextDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前健身房 \(gymName)，\(equipmentCount) 件器械")
    }

    private var contextDetail: String {
        if equipmentCount > 0 {
            return "\(equipmentCount) 件器械可供 Agent 使用"
        }
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty
        {
            return note
        }
        return "点开管理健身房与器械"
    }
}
