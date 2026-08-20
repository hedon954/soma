import Charts
import SwiftData
import SwiftUI

struct TrainingProgramLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrainingProgram.updatedAt, order: .reverse)
    private var programs: [TrainingProgram]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @Query(sort: \ExerciseDefinition.canonicalName)
    private var definitions: [ExerciseDefinition]
    @State private var showsCreation = false
    @State private var resumedSession: WorkoutSession?
    @State private var errorMessage: String?
    private var activePrograms: [TrainingProgram] {
        programs.filter { $0.status == .active }
    }

    private var resumableSession: WorkoutSession? {
        sessions.first {
            $0.status == .active || $0.status == .paused
        }
    }

    var body: some View {
        List {
            if let resumableSession {
                Section("继续训练") {
                    Button {
                        WorkoutInterfaceOrientationPolicy.shared
                            .setGuidedWorkoutActive(true)
                        resumedSession = resumableSession
                    } label: {
                        Label(
                            "继续 \(resumableSession.startedAt.formatted(date: .omitted, time: .shortened)) 的训练",
                            systemImage: "play.circle.fill"
                        )
                    }
                }
            }

            Section("我的计划") {
                if activePrograms.isEmpty {
                    ContentUnavailableView(
                        "还没有训练计划",
                        systemImage: "list.bullet.clipboard",
                        description: Text("点右上角＋选择动作组合，或在教练中描述目标让 Soma 帮你生成。")
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(activePrograms) { program in
                        NavigationLink {
                            TrainingProgramDetailView(program: program)
                        } label: {
                            programRow(program)
                        }
                    }
                }
            }

            let archived = programs.filter { $0.status == .archived }
            if !archived.isEmpty {
                Section("已归档") {
                    ForEach(archived) { program in
                        NavigationLink {
                            TrainingProgramDetailView(program: program)
                        } label: {
                            programRow(program)
                        }
                    }
                }
            }

            let completed = sessions.filter {
                $0.status == .completed || $0.status == .abandoned
            }
            if !completed.isEmpty {
                Section("训练历史") {
                    ForEach(completed.prefix(20)) { session in
                        NavigationLink {
                            WorkoutSessionReviewView(session: session)
                        } label: {
                            WorkoutSessionHistoryRow(
                                session: session,
                                programs: programs
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteSession(session)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("删除计划训练记录")
                            .tint(.red)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle("训练")
        .onAppear {
            TrainingPlanStore.backfillProgramSources(in: modelContext)
        }
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
                TrainingProgramCreationView(definitions: definitions)
            }
        }
        .fullScreenCover(item: $resumedSession) { session in
            NavigationStack {
                GuidedWorkoutView(session: session)
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

    private func programRow(_ program: TrainingProgram) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(program.name)
                .font(.headline)
            Text(program.overview.isEmpty ? "未填写计划概览" : program.overview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private func deleteSession(_ session: WorkoutSession) {
        do {
            try TrainingPlanStore.deleteSession(session, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TrainingProgramDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AIService.self) private var ai
    @Query(sort: \WorkoutTemplateVersion.createdAt, order: .reverse)
    private var allVersions: [WorkoutTemplateVersion]
    @Query(sort: \ExerciseDefinition.canonicalName)
    private var definitions: [ExerciseDefinition]
    @Query(sort: \WorkoutEntry.date, order: .reverse)
    private var workouts: [WorkoutEntry]
    @Query(sort: \BodyEntry.date, order: .reverse)
    private var bodyEntries: [BodyEntry]
    @Query(sort: \UserProfile.updatedAt, order: .reverse)
    private var userProfiles: [UserProfile]
    @Query(sort: \RecommendationSnapshot.createdAt, order: .reverse)
    private var recommendations: [RecommendationSnapshot]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    let program: TrainingProgram
    @State private var showsEditor = false
    @State private var showsStart = false
    @State private var showsOverviewEditor = false
    @State private var overviewDraft = ""
    @State private var startedSession: WorkoutSession?
    @State private var errorMessage: String?
    @State private var isOptimizing = false
    @State private var confirmsDelete = false
    @State private var statsExpanded = false
    @State private var versionsExpanded = false
    @State private var adviceExpanded = false

    private var versions: [WorkoutTemplateVersion] {
        allVersions.filter { $0.programID == program.id }
    }

    private var currentVersion: WorkoutTemplateVersion? {
        guard let id = program.currentTemplateVersionID else { return nil }
        return versions.first { $0.id == id }
    }

    private var prescriptions: [TemplateExercisePrescription] {
        guard let currentVersion else { return [] }
        return TrainingPlanStore.prescriptions(
            for: currentVersion,
            in: modelContext
        )
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
        bodyEntries.contains { ($0.weight ?? 0) > 0 }
            || userProfiles.contains { ($0.referenceWeight ?? 0) > 0 }
    }

    private var programSessions: [WorkoutSession] {
        let familyIDs = Set(versions.map(\.familyID))
        return sessions.filter { session in
            guard session.status == .completed || session.status == .abandoned else {
                return false
            }
            if session.programID == program.id {
                return true
            }
            if let familyID = session.sourceTemplateFamilyID {
                return familyIDs.contains(familyID)
            }
            return false
        }
    }

    private var recentVolumePoints: [(id: UUID, date: Date, volume: Double)] {
        programSessions.prefix(12).reversed().map { session in
            (
                id: session.id,
                date: session.startedAt,
                volume: TrainingPlanStore.summary(
                    for: session.id,
                    in: modelContext
                ).completedVolume
            )
        }
    }

    /// PRD 020：统计默认折叠，首屏聚焦动作列表与开始训练。
    @ViewBuilder
    private var programStatsSection: some View {
        if !programSessions.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $statsExpanded) {
                    LabeledContent("完成次数", value: "\(programSessions.count) 次")
                    if let latest = programSessions.first {
                        LabeledContent(
                            "最近一次",
                            value: latest.startedAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                    }
                    if recentVolumePoints.contains(where: { $0.volume > 0 }) {
                        Chart(recentVolumePoints, id: \.id) { point in
                            BarMark(
                                x: .value("日期", point.date),
                                y: .value("有效容量", point.volume)
                            )
                            .foregroundStyle(AppTheme.tint.gradient)
                        }
                        .frame(height: 160)
                        .accessibilityLabel("该计划近几次训练的有效容量趋势")
                    }
                    ForEach(programSessions.prefix(5)) { session in
                        NavigationLink {
                            WorkoutSessionReviewView(session: session)
                        } label: {
                            WorkoutSessionHistoryRow(
                                session: session,
                                preferredProgramName: program.name
                            )
                        }
                    }
                } label: {
                    Text("训练统计")
                }
                .accessibilityLabel("训练统计，共 \(programSessions.count) 次")
            }
        }
    }

    var body: some View {
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

            Section("动作") {
                if prescriptions.isEmpty {
                    Text("这份计划还没有动作。")
                        .foregroundStyle(.secondary)
                }
                ForEach(prescriptions.sorted(by: { $0.order < $1.order })) { item in
                    prescriptionRow(item)
                }
            }

            programStatsSection

            if !versions.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $versionsExpanded) {
                        ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                            let previous = versions.dropFirst(index + 1).first
                            let changeLog = TrainingPlanStore.resolvedChangeLog(
                                for: version,
                                previous: previous,
                                in: modelContext
                            )
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("v\(version.version) · \(version.name)")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer(minLength: 8)
                                    Text(version.createdAt.formatted(
                                        date: .abbreviated,
                                        time: .omitted
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Text(changeDescription(for: changeLog))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 2)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(
                                "v\(version.version) \(version.name)，\(changeDescription(for: changeLog))"
                            )
                        }
                    } label: {
                        Text("版本历史")
                    }
                    .accessibilityLabel("版本历史，共 \(versions.count) 个版本")
                }
            }

            if isOptimizing || currentRecommendation != nil {
                Section {
                    DisclosureGroup(isExpanded: $adviceExpanded) {
                        if let currentRecommendation {
                            Text(currentRecommendation.advice)
                                .textSelection(.enabled)
                            Text("生成于 \(currentRecommendation.createdAt.formatted(date: .abbreviated, time: .shortened))")
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
                            showsEditor = true
                        } label: {
                            Label("编辑并创建新版本", systemImage: "slider.horizontal.3")
                        }

                        Button {
                            adviceExpanded = true
                            optimize()
                        } label: {
                            Label(
                                currentRecommendation == nil
                                    ? "优化本次训练"
                                    : "当前建议已缓存",
                                systemImage: "sparkles"
                            )
                        }
                        .disabled(
                            isOptimizing
                                || prescriptions.isEmpty
                                || currentRecommendation != nil
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
            Text("将删除「\(program.name)」及其全部模板版本。已完成的训练历史不会被删除。")
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
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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
                    currentVersion: currentVersion,
                    initialPrescriptions: prescriptions,
                    definitions: definitions
                )
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
        .fullScreenCover(item: $startedSession) { session in
            NavigationStack {
                GuidedWorkoutView(session: session)
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

    private func changeDescription(for changeLog: TemplateVersionChangeLog) -> String {
        let details = changeLog.details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !details.isEmpty {
            return details
        }
        return changeLog.summary
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
    @ViewBuilder
    private func prescriptionRow(
        _ item: TemplateExercisePrescription
    ) -> some View {
        if let definition = definition(for: item.exerciseID) {
            NavigationLink {
                ExerciseDetailView(exercise: definition)
            } label: {
                prescriptionLabel(item)
            }
        } else {
            prescriptionLabel(item)
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
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                Text("\(item.order). \(item.exerciseName)")
                    .font(.headline)
                Text(prescriptionSummary(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .accessibilityElement(children: .combine)
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
                Text(overview.overviewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("训练效果总览")
            } footer: {
                if !overview.intensities.isEmpty {
                    Text("按各动作的主要/辅助肌群与目标组数确定性聚合，不是个人受力测量。")
                }
            }
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
            if let version = session.sourceTemplateVersion {
                return "\(preferredProgramName) · v\(version)"
            }
            return preferredProgramName
        }
        return "未关联训练计划"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(planLabel)
                .font(.headline)
            Text(session.startedAt.formatted(
                date: .abbreviated,
                time: .shortened
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text(
                TrainingPlanStore.summary(
                    for: session.id,
                    in: modelContext
                ).text
            )
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
    @Query(sort: \ExercisePerformance.order)
    private var allPerformances: [ExercisePerformance]
    @Query(sort: \WorkoutSet.order) private var allSets: [WorkoutSet]

    let session: WorkoutSession
    @State private var shareModel: WorkoutSharePosterModel?

    private var performances: [ExercisePerformance] {
        allPerformances.filter { $0.sessionID == session.id }
    }

    private var planLabel: String? {
        TrainingPlanStore.programSourceLabel(for: session, in: modelContext)
    }

    var body: some View {
        List {
            Section("本地总结") {
                if let planLabel {
                    LabeledContent("训练计划", value: planLabel)
                }
                Text(
                    TrainingPlanStore.summary(
                        for: session.id,
                        in: modelContext
                    ).text
                )
                if session.status == .abandoned {
                    Label("本次训练提前结束，未确认组没有计为完成。", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            Section("动作") {
                ForEach(performances) { performance in
                    NavigationLink {
                        PerformanceReviewView(performance: performance)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(performance.exerciseName)
                                .font(.headline)
                            let sets = allSets.filter {
                                $0.performanceID == performance.id
                                    && $0.status == .completed
                            }
                            let videoCount = Set(
                                sets.compactMap(\.recordedVideoPath)
                                    + [performance.activeVideoPath].compactMap { $0 }
                            ).count
                            Text(
                                "\(sets.count) 组已确认"
                                    + (videoCount == 0
                                        ? ""
                                        : " · \(videoCount) 段录像")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("训练复盘")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if TrainingPlanStore.backfillProgramSource(
                for: session,
                in: modelContext
            ) {
                try? modelContext.save()
            }
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
}

struct PerformanceReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AIService.self) private var ai
    @Environment(DataSpaceController.self) private var dataSpace
    @Environment(ConversationProcessingService.self) private var processor
    @Environment(ConversationSessionController.self)
    private var conversationSessions
    @Environment(LocationContextService.self) private var locationContext
    @Query(sort: \PerformanceAnalysis.createdAt, order: .reverse)
    private var allAnalyses: [PerformanceAnalysis]
    @Query(sort: \WorkoutSet.order) private var allSets: [WorkoutSet]

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
        allAnalyses.first { $0.performanceID == performance.id }
    }

    private var videoAttachment: MediaAttachmentReference? {
        performance.activeVideoPath.map {
            MediaAttachmentReference(kind: .video, path: $0)
        }
    }

    private var recordedSets: [WorkoutSet] {
        allSets.filter {
            $0.performanceID == performance.id
                && $0.recordedVideoPath != nil
        }
        .sorted { $0.order < $1.order }
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
                    Text("点击后 Soma 会创建一条可恢复的教练任务，发送所选视频或关键帧、动作身份和已确认组数值；分析经固定 Tool 保存，不会重复记录训练。")
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
        do {
            let fingerprint = try TrainingIntelligenceService
                .performanceFingerprint(for: performance)
            let prompt = TrainingIntelligenceService.performanceReviewPrompt(
                performance: performance,
                sets: allSets,
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
                errorMessage = "无法建立本次教练任务。"
                return
            }
            let accepted = processor.submit(
                text: prompt,
                attachments: [attachment],
                context: context,
                includeLocation: false,
                locationService: locationContext
            )
            // ADR 0045：落盘成功即接受，模型不可用只会让任务进入暂存。
            guard accepted else {
                errorMessage = "无法保存本次复盘任务，请稍后重试。"
                return
            }
            isAnalyzing = true
        } catch {
            errorMessage = error.localizedDescription
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
        var newPath: String?
        do {
            let storedPath = try MediaStore.saveVideo(from: url)
            newPath = storedPath
            let oldPath = performance.activeVideoPath
            performance.activeVideoPath = storedPath
            for analysis in allAnalyses
                where analysis.performanceID == performance.id
            {
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

    private func removeVideo() {
        guard let path = performance.activeVideoPath else { return }
        performance.activeVideoPath = nil
        for analysis in allAnalyses
            where analysis.performanceID == performance.id
        {
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
