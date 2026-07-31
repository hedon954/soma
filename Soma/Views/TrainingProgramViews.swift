import SwiftData
import SwiftUI

struct TrainingProgramLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrainingProgram.updatedAt, order: .reverse)
    private var programs: [TrainingProgram]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    private var resumableSession: WorkoutSession? {
        sessions.first {
            $0.status == .active || $0.status == .paused
        }
    }

    var body: some View {
        List {
            if let resumableSession {
                Section("进行中") {
                    NavigationLink {
                        GuidedWorkoutView(session: resumableSession)
                    } label: {
                        Label(
                            "继续 \(resumableSession.startedAt.formatted(date: .omitted, time: .shortened)) 的训练",
                            systemImage: "play.circle.fill"
                        )
                    }
                }
            }

            Section("训练计划") {
                if programs.isEmpty {
                    ContentUnavailableView(
                        "还没有训练计划",
                        systemImage: "list.bullet.clipboard",
                        description: Text("在教练里描述你的目标与动作，Soma 会创建可审查的训练计划。")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(programs.filter { $0.status == .active }) { program in
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
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.startedAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                ))
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
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle("训练计划")
    }

    private func programRow(_ program: TrainingProgram) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(program.name)
                .font(.headline)
            Text(program.goal.isEmpty ? "未记录目标" : program.goal)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

private struct TrainingProgramDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AIService.self) private var ai
    @Query(sort: \WorkoutTemplateVersion.createdAt, order: .reverse)
    private var allVersions: [WorkoutTemplateVersion]
    @Query(sort: \ExerciseDefinition.canonicalName)
    private var definitions: [ExerciseDefinition]
    @Query(sort: \WorkoutEntry.date, order: .reverse)
    private var workouts: [WorkoutEntry]
    @Query(sort: \RecommendationSnapshot.createdAt, order: .reverse)
    private var recommendations: [RecommendationSnapshot]

    let program: TrainingProgram
    @State private var showsEditor = false
    @State private var showsStart = false
    @State private var autoRecording = false
    @State private var startedSession: WorkoutSession?
    @State private var errorMessage: String?
    @State private var isOptimizing = false

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

    private var readiness: [TrainingReadinessIssue] {
        TrainingPlanStore.readiness(
            prescriptions: prescriptions,
            autoRecording: autoRecording,
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

    var body: some View {
        List {
            Section("计划") {
                LabeledContent("目标", value: program.goal.isEmpty ? "未记录" : program.goal)
                if let currentVersion {
                    LabeledContent("当前模板", value: "\(currentVersion.name) · v\(currentVersion.version)")
                    if !currentVersion.scheduleHint.isEmpty {
                        LabeledContent("安排", value: currentVersion.scheduleHint)
                    }
                }
            }

            Section("动作") {
                if prescriptions.isEmpty {
                    Text("当前模板没有动作。")
                        .foregroundStyle(.secondary)
                }
                ForEach(prescriptions.sorted(by: { $0.order < $1.order })) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(item.order). \(item.exerciseName)")
                            .font(.headline)
                        Text(prescriptionSummary(item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if !versions.isEmpty {
                Section("版本历史") {
                    ForEach(versions) { version in
                        HStack {
                            Text("v\(version.version) · \(version.name)")
                            Spacer()
                            Text(version.createdAt.formatted(
                                date: .abbreviated,
                                time: .omitted
                            ))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("训练建议") {
                if let currentRecommendation {
                    Text(currentRecommendation.advice)
                        .textSelection(.enabled)
                    Text("生成于 \(currentRecommendation.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("只有你主动点击后，Soma 才会根据当前计划和已有训练历史生成建议。")
                        .foregroundStyle(.secondary)
                }
                Button {
                    optimize()
                } label: {
                    if isOptimizing {
                        ProgressView()
                    } else {
                        Label(
                            currentRecommendation == nil
                                ? "优化本次训练"
                                : "当前建议已缓存",
                            systemImage: "sparkles"
                        )
                    }
                }
                .disabled(
                    isOptimizing
                        || prescriptions.isEmpty
                        || currentRecommendation != nil
                )
            }

            if program.status == .active {
                Section {
                    Button {
                        autoRecording = false
                        showsStart = true
                    } label: {
                        Label("开始训练", systemImage: "play.fill")
                    }
                    .disabled(prescriptions.isEmpty)

                    Button {
                        showsEditor = true
                    } label: {
                        Label("编辑并创建新版本", systemImage: "slider.horizontal.3")
                    }

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
                }
            }
        }
        .navigationTitle(program.name)
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
        .sheet(isPresented: $showsStart) {
            NavigationStack {
                Form {
                    Section {
                        Toggle("每个动作自动录制一组", isOn: $autoRecording)
                    } footer: {
                        Text("首组是热身时录第 2 组，否则录第 1 组。麦克风关闭，视频只保存在 Soma。")
                    }
                    if !readiness.isEmpty {
                        Section("开始前检查") {
                            ForEach(readiness) { issue in
                                Label(
                                    issue.message,
                                    systemImage: issue.severity == .blocking
                                        ? "xmark.octagon.fill"
                                        : "exclamationmark.triangle.fill"
                                )
                                .foregroundStyle(
                                    issue.severity == .blocking
                                        ? Color.red
                                        : Color.orange
                                )
                            }
                        }
                    }
                }
                .navigationTitle("准备训练")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showsStart = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("开始") {
                            start()
                        }
                        .disabled(readiness.contains {
                            $0.severity == .blocking
                        })
                    }
                }
            }
            .presentationDetents([.medium, .large])
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

    private func start() {
        do {
            startedSession = try TrainingPlanStore.startSession(
                program: program,
                autoRecording: autoRecording,
                in: modelContext
            )
            showsStart = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func optimize() {
        guard ai.hasRequiredAPIKey else {
            errorMessage = "请先在设置中配置本机 AI 服务；个人 API Key 不会上传到 Soma 后台。"
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

    private func prescriptionSummary(
        _ item: TemplateExercisePrescription
    ) -> String {
        var values: [String] = []
        if let sets = item.targetSets {
            values.append("\(sets) 组")
        }
        if let reps = item.targetReps {
            values.append("每组 \(reps) 次")
        }
        if let weight = item.targetWeightKG {
            values.append("\(weight.formatted()) kg")
        }
        if let rest = item.targetRestSeconds {
            values.append("间歇 \(rest) 秒")
        }
        if item.firstSetIsWarmup {
            values.append("首组热身")
        }
        return values.isEmpty ? "处方值未记录" : values.joined(separator: " · ")
    }
}

private struct TrainingTemplateEditor: View {
    struct Row: Identifiable {
        var id: UUID
        var exerciseID: UUID
        var sets: String
        var reps: String
        var weight: String
        var rest: String
        var firstSetIsWarmup: Bool
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let program: TrainingProgram
    let currentVersion: WorkoutTemplateVersion?
    let definitions: [ExerciseDefinition]

    @State private var name: String
    @State private var scheduleHint: String
    @State private var rows: [Row]
    @State private var errorMessage: String?

    init(
        program: TrainingProgram,
        currentVersion: WorkoutTemplateVersion?,
        initialPrescriptions: [TemplateExercisePrescription],
        definitions: [ExerciseDefinition]
    ) {
        self.program = program
        self.currentVersion = currentVersion
        self.definitions = definitions
        _name = State(initialValue: currentVersion?.name ?? program.name)
        _scheduleHint = State(initialValue: currentVersion?.scheduleHint ?? "")
        _rows = State(initialValue: initialPrescriptions.map {
            Row(
                id: UUID(),
                exerciseID: $0.exerciseID,
                sets: $0.targetSets.map(String.init) ?? "",
                reps: $0.targetReps.map(String.init) ?? "",
                weight: $0.targetWeightKG.map { $0.formatted() } ?? "",
                rest: $0.targetRestSeconds.map(String.init) ?? "",
                firstSetIsWarmup: $0.firstSetIsWarmup
            )
        })
    }

    private var activeDefinitions: [ExerciseDefinition] {
        definitions.filter { !$0.isArchived }
    }

    var body: some View {
        Form {
            Section("模板") {
                TextField("模板名称", text: $name)
                TextField("安排提示", text: $scheduleHint)
            }
            Section("动作顺序") {
                ForEach($rows) { $row in
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("动作", selection: $row.exerciseID) {
                            ForEach(activeDefinitions) { exercise in
                                Text(exercise.canonicalName)
                                    .tag(exercise.id)
                            }
                        }
                        HStack {
                            metric("组", text: $row.sets)
                            metric("次", text: $row.reps)
                            metric("kg", text: $row.weight)
                            metric("休息秒", text: $row.rest)
                        }
                        Toggle("第 1 组是热身组", isOn: $row.firstSetIsWarmup)
                    }
                    .padding(.vertical, 5)
                }
                .onDelete { rows.remove(atOffsets: $0) }
                .onMove { rows.move(fromOffsets: $0, toOffset: $1) }

                if let first = activeDefinitions.first {
                    Button {
                        rows.append(Row(
                            id: UUID(),
                            exerciseID: first.id,
                            sets: "",
                            reps: "",
                            weight: "",
                            rest: "",
                            firstSetIsWarmup: false
                        ))
                    } label: {
                        Label("添加动作", systemImage: "plus.circle")
                    }
                }
            }
        }
        .navigationTitle("新建模板版本")
        .environment(\.editMode, .constant(.active))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(name.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty || rows.isEmpty)
            }
        }
        .alert(
            "无法保存",
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

    private func metric(
        _ label: String,
        text: Binding<String>
    ) -> some View {
        TextField(label, text: text)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(label)
    }

    private func save() {
        let names = Dictionary(uniqueKeysWithValues: activeDefinitions.map {
            ($0.id, $0.canonicalName)
        })
        let values = rows.enumerated().map { index, row in
            TemplateExercisePrescription(
                exerciseID: row.exerciseID,
                exerciseName: names[row.exerciseID] ?? "已删除动作",
                order: index + 1,
                targetSets: Int(row.sets),
                targetReps: Int(row.reps),
                targetWeightKG: Double(row.weight),
                targetRestSeconds: Int(row.rest),
                firstSetIsWarmup: row.firstSetIsWarmup
            )
        }
        do {
            _ = try TrainingPlanStore.createNextVersion(
                for: program,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                scheduleHint: scheduleHint.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                prescriptions: values,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct WorkoutSessionReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExercisePerformance.order)
    private var allPerformances: [ExercisePerformance]
    @Query(sort: \WorkoutSet.order) private var allSets: [WorkoutSet]

    let session: WorkoutSession

    private var performances: [ExercisePerformance] {
        allPerformances.filter { $0.sessionID == session.id }
    }

    var body: some View {
        List {
            Section("本地总结") {
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
                            Text(
                                "\(sets.count) 组已确认"
                                    + (performance.activeVideoPath == nil
                                        ? ""
                                        : " · 有录像")
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
    @State private var isAnalyzing = false
    @State private var showsVideoPicker = false
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

    var body: some View {
        Form {
            Section("动作证据") {
                if let videoAttachment {
                    Button {
                        presentedVideo = videoAttachment
                    } label: {
                        Label("查看本组录像", systemImage: "play.rectangle.fill")
                    }
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

            Section("AI 视频复盘") {
                Text("只有点击下方按钮后，Soma 才会创建一条可恢复的教练任务，并发送所选视频或关键帧、动作身份和已确认组数值。分析必须经固定 Tool 保存，不会重复记录训练。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    analyze()
                } label: {
                    if isAnalyzing {
                        ProgressView()
                    } else {
                        Label(
                            analysis == nil ? "分析这段视频" : "当前视频已分析",
                            systemImage: "sparkles"
                        )
                    }
                }
                .disabled(
                    performance.activeVideoPath == nil
                        || isAnalyzing
                        || analysis != nil
                )
            }

            if analysis != nil {
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
                    Text("若出现疼痛、眩晕或明显不适，请停止训练并寻求专业帮助；本复盘不构成医疗诊断。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("保存编辑", action: saveAnalysis)
                    Button("删除分析", role: .destructive) {
                        deleteAnalysis()
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
        .fullScreenCover(item: $presentedVideo) { video in
            MediaViewer(
                attachments: [video],
                initialAttachmentID: video.id
            )
        }
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
            guard accepted else {
                errorMessage = processor.isProcessing
                    ? "已有教练任务正在执行，请完成后再试。"
                    : "请先配置 AI 服务，或开启后台持续处理。"
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
