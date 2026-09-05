import Charts
import SwiftData
import SwiftUI

private struct TrainingProgramLibraryProjection {
    let active: [TrainingProgram]
    let archived: [TrainingProgram]
    let namesByID: [UUID: String]

    init(programs: [TrainingProgram]) {
        var active: [TrainingProgram] = []
        var archived: [TrainingProgram] = []
        var namesByID: [UUID: String] = [:]
        active.reserveCapacity(programs.count)
        archived.reserveCapacity(programs.count)
        for program in programs {
            namesByID[program.id] = program.name
            switch program.status {
            case .active:
                active.append(program)
            case .archived:
                archived.append(program)
            }
        }
        self.active = active
        self.archived = archived
        self.namesByID = namesByID
    }
}

struct TrainingProgramLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(GuidedWorkoutCoordinator.self) private var guidedCoordinator
    @Query private var programs: [TrainingProgram]
    @Query private var resumableSessions: [WorkoutSession]
    @Query private var completedSessions: [WorkoutSession]
    @State private var showsCreation = false
    @State private var resumedSession: WorkoutSession?
    @State private var errorMessage: String?
    init() {
        let activeStatus = TrainingProgramStatus.active.rawValue
        let archivedStatus = TrainingProgramStatus.archived.rawValue
        var programDescriptor = FetchDescriptor<TrainingProgram>(
            predicate: #Predicate {
                $0.statusRaw == activeStatus || $0.statusRaw == archivedStatus
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        programDescriptor.fetchLimit = 200
        _programs = Query(programDescriptor)

        let active = WorkoutSessionStatus.active.rawValue
        let paused = WorkoutSessionStatus.paused.rawValue
        var resumableDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate {
                $0.statusRaw == active || $0.statusRaw == paused
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        resumableDescriptor.fetchLimit = 1
        _resumableSessions = Query(resumableDescriptor)

        let completed = WorkoutSessionStatus.completed.rawValue
        let abandoned = WorkoutSessionStatus.abandoned.rawValue
        var recentDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate {
                $0.statusRaw == completed || $0.statusRaw == abandoned
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        recentDescriptor.fetchLimit = 4
        _completedSessions = Query(recentDescriptor)
    }

    private var resumableSession: WorkoutSession? {
        resumableSessions.first
    }

    var body: some View {
        let projection = TrainingProgramLibraryProjection(programs: programs)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                ForEach(
                    TrainingHomeSection.visible(
                        hasResumableSession: resumableSession != nil,
                        hasRecentSessions: !completedSessions.isEmpty,
                        hasArchivedPrograms: !projection.archived.isEmpty
                    )
                ) { section in
                    trainingHomeSection(section, projection: projection)
                }
            }
            .padding(AppTheme.pagePadding)
            .padding(.bottom, 72)
            .frame(maxWidth: AppTheme.readableContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .appPageBackground()
        .navigationTitle("训练")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsCreation = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建训练计划")
            }
        }
        .sheet(isPresented: $showsCreation) {
            NavigationStack {
                TrainingProgramCreationContainer()
            }
        }
        .fullScreenCover(item: $resumedSession) { session in
            NavigationStack {
                GuidedWorkoutView(sessionID: session.id)
            }
        }
        .alert(
            "无法删除训练记录",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func trainingHomeSection(
        _ section: TrainingHomeSection,
        projection: TrainingProgramLibraryProjection
    ) -> some View {
        switch section {
        case .resume:
            if let resumableSession {
                TrainingResumeSwipeContainer(
                    session: resumableSession,
                    onResume: {
                        WorkoutInterfaceOrientationPolicy.shared
                            .setGuidedWorkoutActive(true)
                        resumedSession = resumableSession
                    },
                    onDelete: {
                        deleteSession(resumableSession)
                    }
                )
            }
        case .programs:
            SectionHeading(title: "我的计划")
            if projection.active.isEmpty {
                EmptyStateCard(
                    icon: "list.bullet.clipboard",
                    title: "还没有训练计划",
                    message: "点右上角＋选择动作组合，或在教练中描述目标让 Soma 帮你生成。"
                )
            } else {
                ForEach(projection.active) { program in
                    NavigationLink {
                        TrainingProgramDetailView(program: program)
                    } label: {
                        TrainingProgramHomeCard(program: program)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .recent:
            SectionHeading(title: "最近训练")
            AppCard {
                VStack(spacing: 0) {
                    ForEach(Array(completedSessions.prefix(3).enumerated()), id: \.element.id) { index, session in
                        NavigationLink {
                            WorkoutSessionReviewView(session: session)
                        } label: {
                            TrainingSessionHomeRow(
                                session: session,
                                fallbackProgramName: session.programID.flatMap {
                                    projection.namesByID[$0]
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteSession(session)
                            } label: {
                                Label("删除训练记录", systemImage: "trash")
                            }
                        }

                        if index < min(completedSessions.count, 3) - 1 {
                            Divider()
                                .overlay(AppTheme.separator)
                        }
                    }
                }
            }
        case .archived:
            SectionHeading(title: "已归档")
            ForEach(projection.archived) { program in
                NavigationLink {
                    TrainingProgramDetailView(program: program)
                } label: {
                    TrainingProgramHomeCard(program: program)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func deleteSession(_ session: WorkoutSession) {
        let sessionID = session.id
        Task { @MainActor in
            if guidedCoordinator.activeSessionID == sessionID,
               let owner = guidedCoordinator.activeSessionOwner
            {
                _ = await guidedCoordinator.deactivate(owner: owner)
            }
            do {
                try TrainingPlanStore.deleteSession(session, in: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct TrainingProgramCreationContainer: View {
    @Query private var definitions: [ExerciseDefinition]

    init() {
        var descriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.canonicalName)]
        )
        descriptor.fetchLimit = 2000
        _definitions = Query(descriptor)
    }

    var body: some View {
        TrainingProgramCreationView(definitions: definitions)
    }
}

private struct TrainingProgramDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AIService.self) private var ai
    @Query private var definitions: [ExerciseDefinition]
    @Query private var workouts: [WorkoutEntry]
    @Query private var bodyEntries: [BodyEntry]
    @Query private var userProfiles: [UserProfile]
    @Query private var recommendations: [RecommendationSnapshot]
    @Query private var sessions: [WorkoutSession]

    let program: TrainingProgram
    @State private var showsEditor = false
    @State private var editingPrescription: TemplateExercisePrescription?
    @State private var showsStart = false
    @State private var showsOverviewEditor = false
    @State private var overviewDraft = ""
    @State private var startedSession: WorkoutSession?
    @State private var returnToTrainingHomeAfterWorkout = false
    @State private var errorMessage: String?
    @State private var isOptimizing = false
    @State private var confirmsDelete = false
    @State private var statsExpanded = false
    @State private var statsSnapshot = TrainingProgramStatsSnapshot.empty
    @State private var isLoadingStats = false
    @State private var adviceExpanded = false
    @State private var prescriptions: [TemplateExercisePrescription]

    init(program: TrainingProgram) {
        self.program = program

        var definitionDescriptor = FetchDescriptor<ExerciseDefinition>(
            sortBy: [SortDescriptor(\.canonicalName)]
        )
        definitionDescriptor.fetchLimit = 2000
        _definitions = Query(definitionDescriptor)
        _prescriptions = State(
            initialValue: TrainingPlanStore.currentPrescriptions(for: program)
        )

        var workoutDescriptor = FetchDescriptor<WorkoutEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        workoutDescriptor.fetchLimit = 100
        _workouts = Query(workoutDescriptor)

        // 只回答“是否存在可用参考体重”；谓词过滤加单行上限，
        // 体重记录变化时不再物化十行完整模型。
        var bodyDescriptor = FetchDescriptor<BodyEntry>(
            predicate: #Predicate { ($0.weight ?? 0) > 0 },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        bodyDescriptor.fetchLimit = 1
        _bodyEntries = Query(bodyDescriptor)

        var profileDescriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        profileDescriptor.fetchLimit = 1
        _userProfiles = Query(profileDescriptor)

        let programID = program.id
        let targetKind = "training_program"
        var recommendationDescriptor = FetchDescriptor<RecommendationSnapshot>(
            predicate: #Predicate {
                $0.targetKind == targetKind && $0.targetID == programID
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        recommendationDescriptor.fetchLimit = 10
        _recommendations = Query(recommendationDescriptor)

        let completed = WorkoutSessionStatus.completed.rawValue
        let abandoned = WorkoutSessionStatus.abandoned.rawValue
        var sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate {
                $0.programID == programID
                    && ($0.statusRaw == completed || $0.statusRaw == abandoned)
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        sessionDescriptor.fetchLimit = 50
        _sessions = Query(sessionDescriptor)
    }

    private func readiness(
        for policy: AutoRecordingPolicy
    ) -> [TrainingReadinessIssue] {
        TrainingPlanStore.readiness(
            prescriptions: prescriptions,
            autoRecordingPolicy: policy,
            in: modelContext
        )
    }

    private var recommendationFingerprint: String {
        let ids = Set(prescriptions.map(\.exerciseID))
        return TrainingIntelligenceService.planFingerprint(
            prescriptions: prescriptions,
            workouts: Array(
                workouts.filter {
                    $0.exerciseID.map(ids.contains) ?? false
                }.prefix(30)
            )
        )
    }

    private var currentRecommendation: RecommendationSnapshot? {
        recommendations.first {
            $0.targetKind == "training_program"
                && $0.targetID == program.id
                && $0.inputFingerprint == recommendationFingerprint
        }
    }

    private var hasCalorieReferenceWeight: Bool {
        !bodyEntries.isEmpty
    }

    private var recentVolumePoints: [(id: UUID, date: Date, volume: Double)] {
        sessions.prefix(12).reversed().compactMap { session in
            guard let summary = statsSnapshot.summariesBySessionID[session.id]
            else {
                return nil
            }
            return (
                id: session.id,
                date: session.startedAt,
                volume: summary.completedVolume
            )
        }
    }

    /// PRD 020：统计默认折叠，首屏聚焦动作列表与开始训练。
    @ViewBuilder
    private var programStatsSection: some View {
        let volumePoints = recentVolumePoints
        if !sessions.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $statsExpanded) {
                    LabeledContent("完成次数", value: "\(sessions.count) 次")
                    if let latest = sessions.first {
                        LabeledContent(
                            "最近一次",
                            value: latest.startedAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                    }
                    if isLoadingStats,
                       statsSnapshot.summariesBySessionID.isEmpty
                    {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在载入训练统计…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if volumePoints.contains(where: { $0.volume > 0 }) {
                        Chart(volumePoints, id: \.id) { point in
                            BarMark(
                                x: .value("日期", point.date),
                                y: .value("有效容量", point.volume)
                            )
                            .foregroundStyle(AppTheme.trainingAccent.gradient)
                        }
                        .frame(height: 160)
                        .accessibilityLabel("该计划近几次训练的有效容量趋势")
                    }
                    ForEach(sessions.prefix(5)) { session in
                        NavigationLink {
                            WorkoutSessionReviewView(session: session)
                        } label: {
                            WorkoutSessionHistoryRow(
                                session: session,
                                preferredProgramName: program.name,
                                summary: statsSnapshot.summariesBySessionID[session.id]
                            )
                        }
                    }
                } label: {
                    Text("训练统计")
                }
                .accessibilityLabel("训练统计，共 \(sessions.count) 次")
            }
        }
    }

    var body: some View {
        let recommendation = currentRecommendation
        List {
            Section {
                Button {
                    overviewDraft = program.overview
                    showsOverviewEditor = true
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text(program.overview.isEmpty
                            ? "点击补充这份计划的整体思路与安排。"
                            : program.overview)
                            .font(.body)
                            .foregroundStyle(program.overview.isEmpty ? .secondary : .primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.tint)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(program.overview.isEmpty ? "编辑计划概览，当前未填写" : "编辑计划概览，\(program.overview)")
            }

            planOverviewSection

            Section {
                if prescriptions.isEmpty {
                    Text("这份计划还没有动作。")
                        .foregroundStyle(.secondary)
                }
                ForEach(prescriptions) { item in
                    prescriptionRow(item)
                }
            } header: {
                HStack {
                    Text("动作与参数")
                    Spacer()
                    if program.status == .active {
                        Button {
                            showsEditor = true
                        } label: {
                            Label("编辑全部", systemImage: "slider.horizontal.3")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.trainingAccent)
                        .textCase(nil)
                        .accessibilityHint("编辑动作顺序以及全部动作参数")
                    }
                }
            }

            programStatsSection

            if isOptimizing || recommendation != nil {
                Section {
                    DisclosureGroup(isExpanded: $adviceExpanded) {
                        if let recommendation {
                            Text(recommendation.advice)
                                .textSelection(.enabled)
                            Text("生成于 \(recommendation.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("正在生成建议…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } label: {
                        Label("训练建议", systemImage: "sparkles")
                    }
                }
            }
        }
        .navigationTitle(program.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if program.status == .active {
                        Button {
                            adviceExpanded = true
                            optimize()
                        } label: {
                            Label(
                                recommendation == nil
                                    ? "优化本次训练"
                                    : "当前建议已缓存",
                                systemImage: "sparkles"
                            )
                        }
                        .disabled(
                            isOptimizing
                                || prescriptions.isEmpty
                                || recommendation != nil
                        )

                        Divider()

                        Button("归档计划", role: .destructive) {
                            do {
                                try TrainingPlanStore.archive(
                                    program,
                                    in: modelContext
                                )
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    } else if program.status == .archived {
                        Button {
                            do {
                                try TrainingPlanStore.unarchive(
                                    program,
                                    in: modelContext
                                )
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        } label: {
                            Label("恢复计划", systemImage: "arrow.uturn.backward")
                        }
                    }

                    Button("删除计划", role: .destructive) {
                        confirmsDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("计划管理")
            }
        }
        .confirmationDialog(
            "删除训练计划？",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("删除计划", role: .destructive) {
                do {
                    try TrainingPlanStore.deleteProgram(program, in: modelContext)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除「\(program.name)」。已完成的训练历史不会被删除。")
        }
        .confirmationDialog(
            "选择录像方式",
            isPresented: $showsStart,
            titleVisibility: .visible
        ) {
            Button("每个动作录第一组") {
                start(with: .enabled)
            }
            Button("每一组都录") {
                start(with: .everySet)
            }
            Button("不录像") {
                start(with: .disabled)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择后立即开始训练。首组策略会跳过热身组；训练中仍可随时主动录像。")
        }
        .safeAreaInset(edge: .bottom) {
            if program.status == .active, !prescriptions.isEmpty {
                VStack(spacing: 8) {
                    if !hasCalorieReferenceWeight {
                        NavigationLink {
                            PersonalBodyInfoView()
                        } label: {
                            Label(
                                "补充体重后可估算本次消耗",
                                systemImage: "flame"
                            )
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(.orange)
                        .accessibilityHint("训练不会被阻断")
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            ForEach(TrainingProgramDetailAction.allCases) {
                                primaryActionButton($0)
                            }
                        }
                        VStack(spacing: 8) {
                            ForEach(TrainingProgramDetailAction.allCases) {
                                primaryActionButton($0)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .sheet(isPresented: $showsEditor) {
            NavigationStack {
                TrainingTemplateEditor(
                    program: program,
                    initialPrescriptions: prescriptions,
                    definitions: definitions
                )
            }
        }
        .sheet(item: $editingPrescription) { item in
            NavigationStack {
                TrainingPrescriptionEditorView(
                    initialDraft: TrainingPrescriptionDraft(item),
                    exercise: definition(for: item.exerciseID),
                    definitions: definitions.filter { !$0.isArchived },
                    recent: ExerciseRecentPrescriptionResolver.latest(
                        exerciseID: item.exerciseID,
                        in: modelContext
                    )
                ) { updated in
                    try saveEditedPrescription(updated, replacing: item)
                }
            }
        }
        .sheet(isPresented: $showsOverviewEditor) {
            NavigationStack {
                Form {
                    Section {
                        TextEditor(text: $overviewDraft)
                            .frame(minHeight: 180)
                            .accessibilityLabel("计划概览")
                    } footer: {
                        Text("用于说明整份计划的训练思路、节奏与注意事项。")
                    }
                }
                .navigationTitle("编辑计划概览")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showsOverviewEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            saveOverview()
                        }
                    }
                }
            }
        }
        .onChange(of: showsStart) {
            guard !showsStart, startedSession == nil else { return }
            WorkoutInterfaceOrientationPolicy.shared
                .setGuidedWorkoutActive(false)
        }
        .onChange(of: startedSession?.id) {
            guard startedSession == nil, !showsStart else { return }
            WorkoutInterfaceOrientationPolicy.shared
                .setGuidedWorkoutActive(false)
        }
        .onChange(of: program.updatedAt) {
            prescriptions = TrainingPlanStore.currentPrescriptions(for: program)
        }
        .task(id: statsExpanded) {
            guard statsExpanded else { return }
            await loadStatsSnapshot()
        }
        .fullScreenCover(item: $startedSession, onDismiss: {
            if returnToTrainingHomeAfterWorkout {
                returnToTrainingHomeAfterWorkout = false
                dismiss()
            }
        }) { session in
            NavigationStack {
                GuidedWorkoutView(sessionID: session.id) {
                    returnToTrainingHomeAfterWorkout = true
                }
            }
        }
        .alert(
            "无法完成操作",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func start(with policy: AutoRecordingPolicy) {
        do {
            startedSession = try TrainingPlanStore.startSession(
                program: program,
                autoRecordingPolicy: policy,
                in: modelContext
            )
            showsStart = false
        } catch {
            WorkoutInterfaceOrientationPolicy.shared
                .setGuidedWorkoutActive(false)
            errorMessage = error.localizedDescription
        }
    }

    private func loadStatsSnapshot() async {
        guard !isLoadingStats else { return }
        isLoadingStats = true
        defer { isLoadingStats = false }
        let interval = AppPerformance.begin(
            .derivedSnapshot,
            detail: "screen=training-program,kind=stats"
        )
        let container = modelContext.container
        let programID = program.id
        let worker = Task.detached(priority: .userInitiated) {
            let loader = TrainingProgramStatsSnapshotLoader(
                modelContainer: container
            )
            return try await loader.load(programID: programID)
        }
        do {
            let loaded = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else {
                AppPerformance.end(
                    interval,
                    detail: "screen=training-program,kind=stats,cancelled=true"
                )
                return
            }
            statsSnapshot = loaded
            AppPerformance.end(
                interval,
                detail: "screen=training-program,kind=stats"
            )
        } catch is CancellationError {
            AppPerformance.end(
                interval,
                detail: "screen=training-program,kind=stats,cancelled=true"
            )
        } catch {
            AppPerformance.end(
                interval,
                detail: "screen=training-program,kind=stats,failed=true"
            )
        }
    }

    private func saveOverview() {
        do {
            try TrainingPlanStore.updateOverview(
                overviewDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                for: program,
                in: modelContext
            )
            showsOverviewEditor = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveEditedPrescription(
        _ updated: TrainingPrescriptionDraft,
        replacing original: TemplateExercisePrescription
    ) throws {
        let ordered = prescriptions.sorted { $0.order < $1.order }
        guard let index = ordered.firstIndex(where: { $0.id == original.id }) else {
            throw TrainingPlanError.missingExercise(original.exerciseID)
        }
        var drafts = ordered.map(TrainingPrescriptionDraft.init)
        drafts[index] = updated
        try TrainingPlanStore.updateProgram(
            for: program,
            name: program.name,
            scheduleHint: program.scheduleHint,
            prescriptions: makePrescriptions(
                rows: drafts,
                definitions: definitions
            ),
            in: modelContext
        )
    }

    private func optimize() {
        guard ai.hasRequiredAPIKey else {
            errorMessage = "请先在设置的「LLM 配置」中完成配置；个人 API Key 不会上传到 Soma 后台。"
            return
        }
        isOptimizing = true
        Task {
            defer { isOptimizing = false }
            do {
                _ = try await TrainingIntelligenceService.optimize(
                    program: program,
                    prescriptions: prescriptions,
                    ai: ai,
                    in: modelContext
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 计划内动作行：有动作库定义时可点击进入动作详情。
    private func prescriptionRow(
        _ item: TemplateExercisePrescription
    ) -> some View {
        HStack(spacing: 4) {
            if let definition = definition(for: item.exerciseID) {
                NavigationLink {
                    ExerciseDetailView(
                        exercise: definition,
                        planPrescription: item
                    )
                } label: {
                    prescriptionLabel(item)
                }
            } else {
                prescriptionLabel(item)
            }

            if program.status == .active {
                Button {
                    editingPrescription = item
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.trainingAccent)
                        .frame(
                            width: AppTheme.minimumTapTarget,
                            height: AppTheme.minimumTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("编辑\(item.exerciseName)参数")
                .accessibilityHint("修改组数、次数或时长、重量、侧别与间歇")
            }
        }
    }

    private func prescriptionLabel(
        _ item: TemplateExercisePrescription
    ) -> some View {
        HStack(spacing: 12) {
            ExerciseArtworkView(
                reference: definition(for: item.exerciseID)?
                    .preferredActionIllustration
                    ?? BundledExerciseCatalog.fallbackActionIllustration
            )
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(item.order). \(item.exerciseName)")
                    .font(.subheadline.weight(.medium))
                Text(prescriptionSummary(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if Set(item.plannedSets.map(\.targetKind)).count > 1 {
                    Label("混合次数与时长", systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.warning)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func primaryActionButton(
        _ action: TrainingProgramDetailAction
    ) -> some View {
        switch action {
        case .editPlan:
            Button {
                showsEditor = true
            } label: {
                Label("编辑计划", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("编辑动作顺序以及全部动作参数")
        case .startTraining:
            Button {
                let blocking = readiness(for: .disabled).filter {
                    $0.severity == .blocking
                }
                guard blocking.isEmpty else {
                    errorMessage = blocking.map(\.message)
                        .joined(separator: "\n")
                    return
                }
                WorkoutInterfaceOrientationPolicy.shared
                    .setGuidedWorkoutActive(true)
                showsStart = true
            } label: {
                Label("开始训练", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .appPrimaryButtonStyle()
            .controlSize(.large)
        }
    }

    /// 训练效果总览：聚合当前模板全部动作的刺激肌群，确定性生成。
    private var planOverview: TrainingPlanOverview.Summary {
        TrainingPlanOverview.summarize(
            prescriptions.map { item in
                let definition = definition(for: item.exerciseID)
                return TrainingPlanOverview.ExerciseInput(
                    primaryMuscles: definition?.primaryMuscles ?? [],
                    secondaryMuscles: definition?.secondaryMuscles ?? [],
                    // V5 的独立组处方才是组数真值；`targetSets` 仅保留给
                    // V4 解码兼容，不能让 Agent 创建的计划退化成 1 组。
                    targetSets: item.plannedSets.count
                )
            }
        )
    }

    @ViewBuilder
    private var planOverviewSection: some View {
        if !prescriptions.isEmpty {
            let overview = planOverview
            Section {
                if !overview.intensities.isEmpty {
                    MuscleMapView(
                        intensities: overview.intensities,
                        showsBothSides: true,
                        height: 210,
                        allowsExpansion: true
                    )
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        "\(overview.exerciseCount) 个动作 · \(overview.totalSets) 组",
                        systemImage: "figure.strengthtraining.traditional"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.trainingAccent)
                    if !overview.primaryFocus.isEmpty {
                        focusLine("主要", groups: overview.primaryFocus)
                    }
                    if !overview.secondaryFocus.isEmpty {
                        focusLine("辅助", groups: overview.secondaryFocus)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("训练效果总览")
            } footer: {
                if !overview.intensities.isEmpty {
                    Text("按各动作的主要/辅助肌群与目标组数确定性聚合，不是个人受力测量。")
                }
            }
        }
    }

    private func focusLine(
        _ label: String,
        groups: [MuscleGroup]
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Text(groups.map(\.displayName).joined(separator: "、"))
                .font(.subheadline)
        }
    }

    private func prescriptionSummary(
        _ item: TemplateExercisePrescription
    ) -> String {
        WorkoutPrescriptionFormatter.exerciseSummary(item)
    }

    private func definition(for id: UUID) -> ExerciseDefinition? {
        definitions.first { $0.id == id }
    }
}

private struct WorkoutSessionHistoryRow: View {
    @Environment(\.modelContext) private var modelContext

    let session: WorkoutSession
    var programs: [TrainingProgram] = []
    var preferredProgramName: String?
    var summary: TrainingSessionSummary?

    private var planLabel: String {
        if let source = TrainingPlanStore.programSourceLabel(
            for: session,
            programs: programs,
            in: modelContext
        ) {
            return source
        }
        if let preferredProgramName,
           !preferredProgramName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return preferredProgramName
        }
        return "未关联训练计划"
    }

    var body: some View {
        // 计划来源解析在旧数据行上可能回查数据库；一次 body 只解析一次，
        // 正文与无障碍标签共用同一结果。
        let planLabel = planLabel
        return VStack(alignment: .leading, spacing: 4) {
            Text(planLabel)
                .font(.headline)
            Text(session.startedAt.formatted(
                date: .abbreviated,
                time: .shortened
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text(summary?.text ?? "训练总结载入中…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(planLabel)，\(session.startedAt.formatted(date: .abbreviated, time: .shortened))"
        )
    }
}

private struct WorkoutSessionReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var performances: [ExercisePerformance]
    @Query private var workouts: [WorkoutEntry]

    let session: WorkoutSession
    @State private var shareModel: WorkoutSharePosterModel?
    @State private var summary: TrainingSessionSummary?
    @State private var repairedMissingProjections = false

    init(session: WorkoutSession) {
        self.session = session
        let sessionID = session.id
        _performances = Query(FetchDescriptor<ExercisePerformance>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.order)]
        ))
        _workouts = Query(FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.sourceWorkoutSessionID == sessionID },
            sortBy: [SortDescriptor(\.date)]
        ))
    }

    private var planLabel: String? {
        TrainingPlanStore.programSourceLabel(for: session, in: modelContext)
    }

    var body: some View {
        let workoutsByPerformanceID = workouts.reduce(
            into: [UUID: WorkoutEntry]()
        ) { result, workout in
            guard let performanceID = workout.sourcePerformanceID else { return }
            result[performanceID] = workout
        }
        List {
            Section("本地总结") {
                if let planLabel {
                    LabeledContent("训练计划", value: planLabel)
                }
                Text(summary?.text ?? "正在载入训练总结…")
                if session.status == .abandoned {
                    Label("本次训练提前结束，未确认组没有计为完成。", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            Section("动作") {
                ForEach(performances) { performance in
                    if let workout = workoutsByPerformanceID[performance.id] {
                        NavigationLink {
                            WorkoutRecordDetailView(workout: workout)
                        } label: {
                            ProgressRecentActivityRow(
                                activity: .workout(workout)
                            )
                        }
                        .buttonStyle(.plain)
                    } else if performance.workoutProjectionSuppressed {
                        LabeledContent {
                            Text("训练记录已删除")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(performance.exerciseName)
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(minHeight: ProgressRecentActivityViewport.rowHeight)
                        .accessibilityElement(children: .combine)
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在恢复 \(performance.exerciseName) 的训练记录…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: ProgressRecentActivityViewport.rowHeight)
                    }
                }
            }
        }
        .navigationTitle("训练复盘")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.id) {
            await loadSummary()
            repairMissingWorkoutProjectionsIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareModel = WorkoutSharePosterBuilder.makeModel(
                        session: session,
                        in: modelContext
                    )
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("分享本次训练")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("在教练中继续总结", systemImage: "bubble.left.and.text.bubble.right") {
                        let date = session.startedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                        NotificationCenter.default.post(
                            name: .prefillCoachDraft,
                            object: "请总结 \(date) 开始的这次计划训练。请先查询 sessions，只做总结和建议，不要新增或修改训练记录。"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多操作")
            }
        }
        .sheet(item: $shareModel) { model in
            WorkoutShareSheet(model: model)
        }
    }

    private func repairMissingWorkoutProjectionsIfNeeded() {
        guard !repairedMissingProjections else { return }
        repairedMissingProjections = true
        let existing = Set(workouts.compactMap(\.sourcePerformanceID))
        var changed = false
        for performance in performances
            where !existing.contains(performance.id)
            && !performance.workoutProjectionSuppressed
        {
            if (try? GuidedWorkoutRecordStore.materialize(
                performanceID: performance.id,
                sessionID: session.id,
                in: modelContext
            )) != nil {
                changed = true
            }
        }
        guard changed else { return }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
    }

    private func loadSummary() async {
        let container = modelContext.container
        let sessionID = session.id
        let worker = Task.detached(priority: .userInitiated) {
            let loader = TrainingProgramStatsSnapshotLoader(
                modelContainer: container
            )
            return try await loader.load(sessionID: sessionID)
        }
        let loaded = try? await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard let loaded, !Task.isCancelled else { return }
        summary = loaded
    }
}

struct PerformanceReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AIService.self) private var ai
    @Environment(DataSpaceController.self) private var dataSpace
    @Environment(ConversationProcessingService.self) private var processor
    @Environment(ConversationSessionController.self)
    private var conversationSessions
    @Environment(LocationContextService.self) private var locationContext
    @Query private var analyses: [PerformanceAnalysis]
    @Query private var sets: [WorkoutSet]

    let performance: ExercisePerformance
    @State private var evidence = ""
    @State private var limitations = ""
    @State private var feedback = ""
    @State private var isEditingAnalysis = false
    @State private var isAnalyzing = false
    @State private var showsVideoPicker = false
    @Namespace private var mediaZoomNamespace
    @State private var presentedVideo: MediaAttachmentReference?
    @State private var errorMessage: String?

    private var analysis: PerformanceAnalysis? {
        analyses.first
    }

    private var videoAttachment: MediaAttachmentReference? {
        performance.activeVideoPath.map {
            MediaAttachmentReference(kind: .video, path: $0)
        }
    }

    private var recordedSets: [WorkoutSet] {
        sets.filter { $0.recordedVideoPath != nil }
    }

    init(performance: ExercisePerformance) {
        self.performance = performance
        let performanceID = performance.id
        var analysisDescriptor = FetchDescriptor<PerformanceAnalysis>(
            predicate: #Predicate { $0.performanceID == performanceID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        analysisDescriptor.fetchLimit = 1
        _analyses = Query(analysisDescriptor)
        _sets = Query(FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.performanceID == performanceID },
            sortBy: [SortDescriptor(\.order)]
        ))
    }

    var body: some View {
        Form {
            Section("动作证据") {
                if !recordedSets.isEmpty {
                    ForEach(recordedSets) { set in
                        if let path = set.recordedVideoPath {
                            Button {
                                presentedVideo = MediaAttachmentReference(
                                    kind: .video,
                                    path: path
                                )
                            } label: {
                                Label(
                                    "查看第 \(set.order) 组录像",
                                    systemImage: "play.rectangle.fill"
                                )
                            }
                            .mediaZoomSource(
                                id: MediaAttachmentReference(kind: .video, path: path).id,
                                in: mediaZoomNamespace
                            )
                        }
                    }
                    Button("添加或替换分析用录像") {
                        showsVideoPicker = true
                    }
                } else if let videoAttachment {
                    Button {
                        presentedVideo = videoAttachment
                    } label: {
                        Label("查看本组录像", systemImage: "play.rectangle.fill")
                    }
                    .mediaZoomSource(id: videoAttachment.id, in: mediaZoomNamespace)
                    Button("替换或重新录制") {
                        showsVideoPicker = true
                    }
                    Button("删除录像", role: .destructive) {
                        removeVideo()
                    }
                } else {
                    Text("没有录像。你可以主动拍摄或选择一段本动作视频。")
                        .foregroundStyle(.secondary)
                    Button {
                        showsVideoPicker = true
                    } label: {
                        Label("添加视频", systemImage: "video.badge.plus")
                    }
                }
            }

            // PRD 020：AI 复盘入口只在存在可分析视频时出现，说明下沉为 footer。
            if performance.activeVideoPath != nil, analysis == nil {
                Section {
                    Button {
                        analyze()
                    } label: {
                        if isAnalyzing {
                            ProgressView()
                        } else {
                            Label("分析这段视频", systemImage: "sparkles")
                        }
                    }
                    .disabled(isAnalyzing)
                } header: {
                    Text("AI 视频复盘")
                } footer: {
                    Text("点击后 Soma 会创建一条可恢复的教练任务，发送所选完整视频、动作身份和已确认组数值；分析经固定 Tool 保存，不会重复记录训练。")
                }
            }

            if analysis != nil {
                if isEditingAnalysis {
                    Section("可见证据") {
                        TextEditor(text: $evidence)
                            .frame(minHeight: 90)
                    }
                    Section("分析局限") {
                        TextEditor(text: $limitations)
                            .frame(minHeight: 80)
                    }
                    Section("一般训练建议") {
                        TextEditor(text: $feedback)
                            .frame(minHeight: 110)
                        Button("保存编辑") {
                            saveAnalysis()
                            isEditingAnalysis = false
                        }
                        Button("删除分析", role: .destructive) {
                            deleteAnalysis()
                            isEditingAnalysis = false
                        }
                    }
                } else {
                    // PRD 020：复盘内容默认只读，显式进入编辑后才出现编辑器。
                    Section("可见证据") {
                        Text(evidence.isEmpty ? "未记录" : evidence)
                            .foregroundStyle(evidence.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                    }
                    Section("分析局限") {
                        Text(limitations.isEmpty ? "未记录" : limitations)
                            .foregroundStyle(limitations.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                    }
                    Section {
                        Text(feedback.isEmpty ? "未记录" : feedback)
                            .foregroundStyle(feedback.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                        Button("编辑复盘内容") {
                            isEditingAnalysis = true
                        }
                    } header: {
                        Text("一般训练建议")
                    } footer: {
                        Text("若出现疼痛、眩晕或明显不适，请停止训练并寻求专业帮助；本复盘不构成医疗诊断。")
                    }
                }
            }
        }
        .navigationTitle(performance.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadAnalysis)
        .onChange(of: analysis?.id) {
            loadAnalysis()
        }
        .onChange(of: processor.isProcessing) {
            if !processor.isProcessing {
                isAnalyzing = false
                loadAnalysis()
            }
        }
        .sheet(isPresented: $showsVideoPicker) {
            MediaSourceDialog(
                allowsVideo: true,
                selectionLimit: 1
            ) { media in
                replaceVideo(with: media)
            }
        }
        .mediaViewerCover(
            item: $presentedVideo,
            attachments: presentedVideo.map { [$0] } ?? [],
            namespace: mediaZoomNamespace
        )
        .alert(
            "无法完成复盘",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func analyze() {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        Task { @MainActor in
            do {
                let fingerprint = try await TrainingIntelligenceService
                    .performanceFingerprintAsync(for: performance)
                let prompt = TrainingIntelligenceService.performanceReviewPrompt(
                    performance: performance,
                    sets: sets,
                    fingerprint: fingerprint
                )
                let attachment = try TrainingIntelligenceService
                    .makePendingPerformanceVideo(performance: performance)
                let session = conversationSessions.ensureActiveSession(
                    dataSpace: dataSpace.activeSpace,
                    in: modelContext
                )
                guard let context = ConversationProcessingContextFactory.make(
                    sessionID: session.id,
                    dataSpace: dataSpace.activeSpace,
                    ai: ai,
                    in: modelContext
                ) else {
                    isAnalyzing = false
                    errorMessage = "无法建立本次教练任务。"
                    return
                }
                let accepted = await processor.submitAsync(
                    text: prompt,
                    attachments: [attachment],
                    context: context,
                    includeLocation: false,
                    locationService: locationContext
                )
                // ADR 0045：落盘成功即接受，模型不可用只会让任务进入暂存。
                guard accepted else {
                    isAnalyzing = false
                    errorMessage = "无法保存本次复盘任务，请稍后重试。"
                    return
                }
            } catch {
                isAnalyzing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadAnalysis() {
        evidence = analysis?.evidence ?? ""
        limitations = analysis?.limitations ?? ""
        feedback = analysis?.feedback ?? ""
    }

    private func saveAnalysis() {
        guard let analysis else { return }
        analysis.evidence = evidence.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        analysis.limitations = limitations.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        analysis.feedback = feedback.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            loadAnalysis()
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAnalysis() {
        guard let analysis else { return }
        modelContext.delete(analysis)
        do {
            try modelContext.save()
            loadAnalysis()
        } catch {
            modelContext.rollback()
            loadAnalysis()
            errorMessage = error.localizedDescription
        }
    }

    private func replaceVideo(with media: [PickedMedia]) {
        guard let selected = media.first,
              case let .video(url) = selected
        else {
            errorMessage = "请选择或拍摄一段视频。"
            return
        }
        Task { @MainActor in
            var newPath: String?
            do {
                let storedPath = try await MediaStore.saveVideoAsync(from: url)
                newPath = storedPath
                let oldPath = performance.activeVideoPath
                performance.activeVideoPath = storedPath
                for analysis in analyses {
                    modelContext.delete(analysis)
                }
                try modelContext.save()
                if let oldPath {
                    _ = MediaStore.removeStoredFile(at: oldPath)
                }
                loadAnalysis()
            } catch {
                modelContext.rollback()
                if let newPath {
                    _ = MediaStore.removeStoredFile(at: newPath)
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeVideo() {
        guard let path = performance.activeVideoPath else { return }
        performance.activeVideoPath = nil
        for analysis in analyses {
            modelContext.delete(analysis)
        }
        do {
            try modelContext.save()
            _ = MediaStore.removeStoredFile(at: path)
            presentedVideo = nil
            loadAnalysis()
        } catch {
            modelContext.rollback()
            loadAnalysis()
            errorMessage = error.localizedDescription
        }
    }
}
