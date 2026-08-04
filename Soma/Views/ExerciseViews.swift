import Charts
import SwiftData
import SwiftUI
import UIKit

struct ExerciseLibraryView: View {
    @Query(sort: \ExerciseDefinition.canonicalName)
    private var definitions: [ExerciseDefinition]
    @Query(sort: \WorkoutEntry.date, order: .reverse)
    private var workouts: [WorkoutEntry]
    @Query(sort: \ExercisePerformance.order)
    private var performances: [ExercisePerformance]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @Query(sort: \WorkoutSet.order) private var workoutSets: [WorkoutSet]
    @State private var searchText = ""

    private var activeDefinitions: [ExerciseDefinition] {
        filtered(definitions.filter { !$0.isArchived })
    }

    private var archivedDefinitions: [ExerciseDefinition] {
        filtered(definitions.filter(\.isArchived))
    }

    var body: some View {
        List {
            if definitions.isEmpty {
                ContentUnavailableView(
                    "动作库会随训练自然形成",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("在教练中描述训练后，Soma 会用稳定动作身份串联历史。")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if activeDefinitions.isEmpty, archivedDefinitions.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                Section("动作") {
                    ForEach(activeDefinitions) { definition in
                        exerciseLink(definition)
                    }
                }
                if !archivedDefinitions.isEmpty {
                    Section("已归档") {
                        ForEach(archivedDefinitions) { definition in
                            exerciseLink(definition)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .appPageBackground()
        .navigationTitle("动作库")
        .searchable(text: $searchText, prompt: "搜索标准动作名称")
    }

    private func exerciseLink(
        _ definition: ExerciseDefinition
    ) -> some View {
        NavigationLink {
            ExerciseDetailView(exercise: definition)
        } label: {
            HStack(spacing: 12) {
                ExerciseArtworkView(
                    reference: definition.actionIllustrations.last
                        ?? BundledExerciseCatalog.fallbackActionIllustration,
                    contentMode: .fill
                )
                .frame(width: 64, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(definition.canonicalName)
                            .font(.headline)
                        if definition.isArchived {
                            Text("已归档")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let latest = latestHistory(for: definition) {
                        Text("最近：\(latest.date.formatted(date: .abbreviated, time: .omitted)) · \(latest.summary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text("暂无训练历史")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(definition.canonicalName)，\(latestHistory(for: definition)?.summary ?? "暂无训练历史")"
            )
        }
    }

    private func filtered(
        _ values: [ExerciseDefinition]
    ) -> [ExerciseDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return values }
        return values.filter {
            $0.canonicalName.localizedCaseInsensitiveContains(query)
        }
    }

    private func latestHistory(
        for definition: ExerciseDefinition
    ) -> ExerciseHistoryItem? {
        let legacy = workouts
            .filter { $0.exerciseID == definition.id }
            .map(ExerciseHistoryItem.legacy)
        let guided: [ExerciseHistoryItem] = performances.compactMap { performance in
            guard performance.exerciseID == definition.id,
                  let session = sessions.first(where: {
                      $0.id == performance.sessionID
                  })
            else {
                return nil
            }
            let sets = workoutSets.filter {
                $0.performanceID == performance.id
                    && $0.status == .completed
            }
            return ExerciseHistoryItem.session(ExerciseSessionHistory(
                performance: performance,
                session: session,
                sets: sets
            ))
        }
        return (legacy + guided).max { $0.date < $1.date }
    }
}

struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AIService.self) private var ai
    @Query(sort: \ExerciseDefinition.canonicalName)
    private var definitions: [ExerciseDefinition]
    @Query(sort: \ExerciseMergeRecord.createdAt, order: .reverse)
    private var mergeRecords: [ExerciseMergeRecord]
    @Query(sort: \WorkoutEntry.date, order: .reverse)
    private var workouts: [WorkoutEntry]
    @Query(sort: \ExercisePerformance.order)
    private var performances: [ExercisePerformance]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @Query(sort: \WorkoutSet.order)
    private var workoutSets: [WorkoutSet]

    let exercise: ExerciseDefinition

    @State private var name: String
    @State private var coachingNotes: String
    @State private var primaryMuscles: String
    @State private var secondaryMuscles: String
    @State private var movementPatterns: String
    @State private var mergeTargetID: UUID?
    @State private var errorMessage: String?
    @State private var isGeneratingContent = false
    @State private var generatingImageKind: ExerciseImageKind?
    @State private var imagePickerKind: ExerciseImageKind?
    @State private var showsVideoPicker = false
    @State private var guidanceTitle = ""
    @State private var guidanceURL = ""
    @State private var presentedVideo: MediaAttachmentReference?

    init(exercise: ExerciseDefinition) {
        self.exercise = exercise
        _name = State(initialValue: exercise.canonicalName)
        _coachingNotes = State(initialValue: exercise.coachingNotes)
        _primaryMuscles = State(initialValue: exercise.primaryMuscles.joined(
            separator: "、"
        ))
        _secondaryMuscles = State(initialValue: exercise.secondaryMuscles.joined(
            separator: "、"
        ))
        _movementPatterns = State(initialValue: exercise.movementPatterns.joined(
            separator: "、"
        ))
    }

    private var history: [WorkoutEntry] {
        workouts.filter { $0.exerciseID == exercise.id }
    }

    private var sessionHistory: [ExerciseSessionHistory] {
        performances.compactMap { performance in
            guard performance.exerciseID == exercise.id,
                  let session = sessions.first(where: {
                      $0.id == performance.sessionID
                  })
            else {
                return nil
            }
            let sets = workoutSets.filter {
                $0.performanceID == performance.id
                    && $0.status == .completed
            }
            return ExerciseSessionHistory(
                performance: performance,
                session: session,
                sets: sets
            )
        }
        .sorted { $0.date > $1.date }
    }

    private var allHistory: [ExerciseHistoryItem] {
        (
            history.map(ExerciseHistoryItem.legacy)
                + sessionHistory.map(ExerciseHistoryItem.session)
        ).sorted { $0.date > $1.date }
    }

    private var volumeTrend: [ExerciseVolumePoint] {
        allHistory.compactMap { item in
            guard let volume = item.volume, volume > 0 else { return nil }
            return ExerciseVolumePoint(
                id: item.id,
                date: item.date,
                volume: volume
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var mergeTargets: [ExerciseDefinition] {
        definitions.filter { $0.id != exercise.id && !$0.isArchived }
    }

    private var latestMerge: ExerciseMergeRecord? {
        mergeRecords.first {
            $0.sourceExerciseID == exercise.id && $0.undoneAt == nil
        }
    }

    var body: some View {
        Form {
            Section("动作示意图") {
                ExerciseImageGallery(
                    images: exercise.actionIllustrations,
                    fallback: BundledExerciseCatalog.fallbackActionIllustration,
                    fallbackMessage: "当前显示通用占位图。可主动生成或上传这个动作的专属示意图。",
                    onDelete: removeImage
                )
                Button {
                    generateImage(.actionIllustration)
                } label: {
                    generationLabel(
                        kind: .actionIllustration,
                        title: "AI 生成动作示意图"
                    )
                }
                .disabled(generatingImageKind != nil || exercise.isArchived)
                Button {
                    imagePickerKind = .actionIllustration
                } label: {
                    Label("上传我的动作图", systemImage: "photo.badge.plus")
                }
                .disabled(exercise.isArchived)
            }

            Section("标准动作") {
                TextField("动作名称", text: $name)
                TextField(
                    "辅助教练信息",
                    text: $coachingNotes,
                    axis: .vertical
                )
                .lineLimit(3 ... 8)
                TextField("主要肌群，用顿号分隔", text: $primaryMuscles)
                TextField("辅助肌群，用顿号分隔", text: $secondaryMuscles)
                TextField("动作模式，用顿号分隔", text: $movementPatterns)
                Button("保存修改", action: save)
                    .disabled(exercise.isArchived)
                Button {
                    generateContent()
                } label: {
                    if isGeneratingContent {
                        ProgressView()
                    } else {
                        Label("AI 生成动作说明", systemImage: "sparkles")
                    }
                }
                .disabled(isGeneratingContent || exercise.isArchived)
            }

            Section("通用肌群与动作模式") {
                MuscleMapView(
                    intensities: MuscleGroupMapping.intensityMap(
                        primary: split(primaryMuscles),
                        secondary: split(secondaryMuscles)
                    ),
                    height: 300,
                    allowsExpansion: true
                )
                Text("着色由程序根据主要/辅助肌群确定性生成，表示该动作通常涉及的肌群，不是你的个人受力测量。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(
                    exercise.muscleMaps.filter {
                        $0.source == .generated || $0.source == .user
                    }
                ) { reference in
                    HStack {
                        Label(reference.title, systemImage: "photo")
                        Spacer()
                        Button(role: .destructive) {
                            removeImage(reference)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("删除\(reference.title)")
                    }
                }
            }

            Section("示范与指导视频") {
                if exercise.userDemoVideos.isEmpty,
                   exercise.guidanceVideos.isEmpty
                {
                    Text("可以保存多段自己的示范视频，或添加 Soma 自有、已授权内容及外部链接。Soma 不抓取或重新分发第三方课程。")
                        .foregroundStyle(.secondary)
                }
                ForEach(exercise.userDemoVideos) { video in
                    HStack {
                        Button {
                            presentedVideo = video
                        } label: {
                            Label("我的示范视频", systemImage: "play.rectangle")
                        }
                        Spacer()
                        Button(role: .destructive) {
                            removeUserVideo(video)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("删除这段示范视频")
                    }
                }
                ForEach(exercise.guidanceVideos) { source in
                    HStack {
                        if let url = source.url {
                            Link(destination: url) {
                                Label(source.title, systemImage: "link")
                            }
                        } else {
                            Label(source.title, systemImage: "play.rectangle")
                        }
                        Spacer()
                        Text(source.kind.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            var values = exercise.guidanceVideos
                            values.removeAll { $0.id == source.id }
                            exercise.guidanceVideos = values
                            try? modelContext.save()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("移除这个指导视频来源")
                    }
                }
                Button {
                    showsVideoPicker = true
                } label: {
                    Label("添加我的示范视频", systemImage: "video.badge.plus")
                }
                TextField("外部视频标题", text: $guidanceTitle)
                TextField("https://…", text: $guidanceURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                Button("添加外部链接", action: addGuidanceLink)
                    .disabled(
                        guidanceTitle.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                            || guidanceURL.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
            }

            if !exercise.contentRevisions.isEmpty {
                Section("动作说明版本") {
                    ForEach(exercise.contentRevisions.reversed()) { revision in
                        Button {
                            restore(revision)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(
                                        revision.source == .ai
                                            ? "AI 生成"
                                            : "手动编辑"
                                    )
                                    Text(revision.createdAt.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("恢复")
                            }
                        }
                    }
                }
            }

            Section("训练历史") {
                if let latest = allHistory.first {
                    LabeledContent("最近一次") {
                        Text(latest.summary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                LabeledContent("累计记录", value: "\(allHistory.count) 条")
                if !volumeTrend.isEmpty {
                    Chart(volumeTrend.suffix(12)) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("容量", point.volume)
                        )
                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("容量", point.volume)
                        )
                    }
                    .frame(height: 150)
                    .accessibilityLabel("最近有效训练容量趋势")
                }
                ForEach(allHistory) { item in
                    switch item.source {
                    case let .legacy(workout):
                        NavigationLink {
                            WorkoutRecordDetailView(workout: workout)
                        } label: {
                            historyLabel(item)
                        }
                    case let .session(value):
                        NavigationLink {
                            PerformanceReviewView(
                                performance: value.performance
                            )
                        } label: {
                            historyLabel(item)
                        }
                    }
                }
            }

            Section("动作管理") {
                if exercise.isArchived {
                    if let latestMerge {
                        Button("撤销最近一次合并") {
                            do {
                                try ExerciseLibraryStore.undo(
                                    latestMerge,
                                    in: modelContext
                                )
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    } else {
                        Text("该动作已归档，历史记录仍然保留。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if !mergeTargets.isEmpty {
                        Picker("合并到", selection: $mergeTargetID) {
                            Text("选择目标动作").tag(nil as UUID?)
                            ForEach(mergeTargets) { target in
                                Text(target.canonicalName)
                                    .tag(target.id as UUID?)
                            }
                        }
                        Button("合并并归档当前动作") {
                            merge()
                        }
                        .disabled(mergeTargetID == nil)
                    }
                    Button("归档动作", role: .destructive) {
                        do {
                            try ExerciseLibraryStore.archive(
                                exercise,
                                in: modelContext
                            )
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.canonicalName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsVideoPicker) {
            MediaSourceDialog(
                allowsVideo: true,
                selectionLimit: 5
            ) { media in
                addUserVideos(media)
            }
        }
        .sheet(item: $imagePickerKind) { kind in
            MediaSourceDialog(
                allowsVideo: false,
                selectionLimit: 5
            ) { media in
                addUserImages(media, kind: kind)
            }
        }
        .fullScreenCover(item: $presentedVideo) { selected in
            MediaViewer(
                attachments: exercise.userDemoVideos,
                initialAttachmentID: selected.id,
                deletionTitle: "删除这段示范视频？",
                deletionMessage: "视频会从动作库移除；若没有其他记录引用，文件将在数据清理时回收。",
                onDelete: removeUserVideo
            )
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

    private func save() {
        do {
            if name.trimmingCharacters(in: .whitespacesAndNewlines)
                != exercise.canonicalName
            {
                try ExerciseLibraryStore.rename(
                    exercise,
                    to: name,
                    in: modelContext
                )
            }
            exercise.apply(ExerciseContentRevision(
                source: .manual,
                coachingNotes: coachingNotes.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                primaryMuscles: split(primaryMuscles),
                secondaryMuscles: split(secondaryMuscles),
                movementPatterns: split(movementPatterns)
            ))
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func merge() {
        guard let mergeTargetID,
              let target = mergeTargets.first(where: { $0.id == mergeTargetID })
        else {
            return
        }
        do {
            _ = try ExerciseLibraryStore.merge(
                source: exercise,
                into: target,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func split(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: "、,，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func generateContent() {
        guard ai.hasRequiredAPIKey else {
            errorMessage = "请先在设置中配置 AI 服务。打开动作详情本身不会自动消耗模型请求。"
            return
        }
        isGeneratingContent = true
        Task {
            defer { isGeneratingContent = false }
            do {
                let revision = try await TrainingIntelligenceService
                    .generateContent(
                        for: exercise,
                        ai: ai,
                        in: modelContext
                    )
                coachingNotes = revision.coachingNotes
                primaryMuscles = revision.primaryMuscles.joined(separator: "、")
                secondaryMuscles = revision.secondaryMuscles.joined(separator: "、")
                movementPatterns = revision.movementPatterns.joined(separator: "、")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func generationLabel(
        kind: ExerciseImageKind,
        title: String
    ) -> some View {
        if generatingImageKind == kind {
            HStack {
                ProgressView()
                Text("正在生成")
            }
        } else {
            Label(title, systemImage: "sparkles")
        }
    }

    private func generateImage(_ kind: ExerciseImageKind) {
        guard ai.hasRequiredAPIKey else {
            errorMessage = "请先在设置中配置 AI 服务。图片只会在你主动点击后生成。"
            return
        }
        generatingImageKind = kind
        Task {
            defer { generatingImageKind = nil }
            do {
                _ = try await ExerciseImageGenerationService.generate(
                    kind: kind,
                    for: exercise,
                    ai: ai,
                    in: modelContext
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore(_ revision: ExerciseContentRevision) {
        exercise.apply(ExerciseContentRevision(
            source: .manual,
            coachingNotes: revision.coachingNotes,
            primaryMuscles: revision.primaryMuscles,
            secondaryMuscles: revision.secondaryMuscles,
            movementPatterns: revision.movementPatterns
        ))
        coachingNotes = revision.coachingNotes
        primaryMuscles = revision.primaryMuscles.joined(separator: "、")
        secondaryMuscles = revision.secondaryMuscles.joined(separator: "、")
        movementPatterns = revision.movementPatterns.joined(separator: "、")
        try? modelContext.save()
    }

    private func addUserVideos(_ media: [PickedMedia]) {
        let originalValues = exercise.userDemoVideos
        var values = exercise.userDemoVideos
        var createdPaths: [String] = []
        do {
            for item in media {
                guard case let .video(url) = item else { continue }
                let path = try MediaStore.saveVideo(from: url)
                createdPaths.append(path)
                values.append(MediaAttachmentReference(
                    kind: .video,
                    path: path
                ))
            }
            exercise.userDemoVideos = values
            try modelContext.save()
        } catch {
            exercise.userDemoVideos = originalValues
            modelContext.rollback()
            for path in createdPaths {
                _ = MediaStore.removeStoredFile(at: path)
            }
            errorMessage = error.localizedDescription
        }
    }

    private func addUserImages(
        _ media: [PickedMedia],
        kind: ExerciseImageKind
    ) {
        let originalValues = exercise.imageReferences
        var values = originalValues
        var createdPaths: [String] = []
        do {
            for item in media {
                guard case let .image(data) = item else { continue }
                let path = try MediaStore.saveImage(data)
                createdPaths.append(path)
                values.append(ExerciseImageReference(
                    kind: kind,
                    source: .user,
                    title: kind == .actionIllustration
                        ? "我的动作图"
                        : "我的肌群图",
                    localPath: path
                ))
            }
            exercise.imageReferences = values
            try modelContext.save()
        } catch {
            exercise.imageReferences = originalValues
            modelContext.rollback()
            for path in createdPaths {
                _ = MediaStore.removeStoredFile(at: path)
            }
            errorMessage = error.localizedDescription
        }
    }

    private func removeImage(_ reference: ExerciseImageReference) {
        guard reference.source != .bundled else { return }
        let originalValues = exercise.imageReferences
        exercise.imageReferences.removeAll { $0.id == reference.id }
        do {
            try modelContext.save()
            if let path = reference.localPath {
                _ = MediaStore.removeStoredFile(at: path)
            }
        } catch {
            exercise.imageReferences = originalValues
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func removeUserVideo(_ video: MediaAttachmentReference) {
        var values = exercise.userDemoVideos
        values.removeAll { $0.id == video.id }
        exercise.userDemoVideos = values
        do {
            try modelContext.save()
            _ = MediaStore.removeStoredFile(at: video.path)
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func addGuidanceLink() {
        let rawValue = guidanceURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let url = URL(string: rawValue),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else {
            errorMessage = "请输入有效的 HTTP 或 HTTPS 链接。"
            return
        }
        var values = exercise.guidanceVideos
        values.append(ExerciseVideoSource(
            title: guidanceTitle.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            kind: .externalLink,
            url: url
        ))
        exercise.guidanceVideos = values
        guidanceTitle = ""
        guidanceURL = ""
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func historyLabel(_ item: ExerciseHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.date.formatted(
                date: .abbreviated,
                time: .shortened
            ))
            Text(item.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ExerciseSessionHistory: Identifiable {
    var performance: ExercisePerformance
    var session: WorkoutSession
    var sets: [WorkoutSet]

    var id: UUID {
        performance.id
    }

    var date: Date {
        session.startedAt
    }

    var volume: Double? {
        let values = sets.compactMap(\.completedVolume)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var summary: String {
        let setDetails = sets.sorted { $0.order < $1.order }.map { set in
            [
                set.actualWeightKG.map { "\($0.formatted())kg" },
                set.actualReps.map { "\($0)次" }
            ].compactMap { $0 }.joined(separator: "×")
        }.filter { !$0.isEmpty }
        return "\(sets.count) 组已确认"
            + (setDetails.isEmpty
                ? ""
                : " · \(setDetails.joined(separator: "、"))")
    }
}

private struct ExerciseHistoryItem: Identifiable {
    enum Source {
        case legacy(WorkoutEntry)
        case session(ExerciseSessionHistory)
    }

    var source: Source

    static func legacy(_ value: WorkoutEntry) -> ExerciseHistoryItem {
        ExerciseHistoryItem(source: .legacy(value))
    }

    static func session(_ value: ExerciseSessionHistory) -> ExerciseHistoryItem {
        ExerciseHistoryItem(source: .session(value))
    }

    var id: UUID {
        switch source {
        case let .legacy(value): value.id
        case let .session(value): value.id
        }
    }

    var date: Date {
        switch source {
        case let .legacy(value): value.date
        case let .session(value): value.date
        }
    }

    var summary: String {
        switch source {
        case let .legacy(value): ExerciseQuickFill.text(for: value)
        case let .session(value): value.summary
        }
    }

    var volume: Double? {
        switch source {
        case let .legacy(value): value.estimatedVolume
        case let .session(value): value.volume
        }
    }
}

private struct ExerciseVolumePoint: Identifiable {
    var id: UUID
    var date: Date
    var volume: Double
}

private extension ExerciseVideoSource.SourceKind {
    var label: String {
        switch self {
        case .soma: "Soma 自有"
        case .authorized: "已授权"
        case .externalLink: "外部链接"
        }
    }
}

private struct ExerciseImageGallery: View {
    let images: [ExerciseImageReference]
    let fallback: ExerciseImageReference
    let fallbackMessage: String
    let onDelete: (ExerciseImageReference) -> Void

    var body: some View {
        if images.isEmpty {
            ExerciseArtworkView(reference: fallback, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            Text(fallbackMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let image = images.first, images.count == 1 {
            imageCard(image)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(images) { reference in
                        imageCard(reference)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func imageCard(
        _ reference: ExerciseImageReference
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ExerciseArtworkView(
                reference: reference,
                contentMode: .fit
            )
            .frame(width: 248, height: 248)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            HStack {
                Text(reference.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if reference.source != .bundled {
                    Button(role: .destructive) {
                        onDelete(reference)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("删除\(reference.title)")
                }
            }
        }
        .frame(width: 248)
    }
}
