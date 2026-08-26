import SwiftData
import SwiftUI

/// PRD 020：动作内容编辑子页，只承接名称、肌群和 AI 说明；管理操作保持按需。
struct ExerciseContentEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AIService.self) private var ai

    let exercise: ExerciseDefinition

    @State private var name: String
    @State private var coachingNotes: String
    @State private var primaryMuscles: String
    @State private var secondaryMuscles: String
    @State private var movementPatterns: String
    @State private var laterality: ExerciseLaterality
    @State private var targetKind: WorkoutTargetKind
    @State private var errorMessage: String?
    @State private var isGeneratingContent = false

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
        _laterality = State(initialValue: exercise.laterality)
        _targetKind = State(initialValue: exercise.targetKind)
    }

    var body: some View {
        Form {
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
                Picker("完成方式", selection: $targetKind) {
                    ForEach(WorkoutTargetKind.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                Picker("左右方式", selection: $laterality) {
                    ForEach(ExerciseLaterality.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .pickerStyle(.menu)
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
        }
        .navigationTitle("编辑动作")
        .navigationBarTitleDisplayMode(.inline)
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
            exercise.apply(ExerciseContent(
                coachingNotes: coachingNotes.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                primaryMuscles: split(primaryMuscles),
                secondaryMuscles: split(secondaryMuscles),
                movementPatterns: split(movementPatterns)
            ))
            exercise.laterality = laterality
            exercise.targetKind = targetKind
            try modelContext.save()
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
            errorMessage = "请先在设置的「LLM 配置」中完成配置。打开动作详情本身不会自动消耗模型请求。"
            return
        }
        isGeneratingContent = true
        Task {
            defer { isGeneratingContent = false }
            do {
                let content = try await TrainingIntelligenceService
                    .generateContent(
                        for: exercise,
                        ai: ai,
                        in: modelContext
                    )
                coachingNotes = content.coachingNotes
                primaryMuscles = content.primaryMuscles.joined(separator: "、")
                secondaryMuscles = content.secondaryMuscles.joined(separator: "、")
                movementPatterns = content.movementPatterns.joined(separator: "、")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// 低频归档与合并独立于内容编辑；只有用户主动进入时才读取候选和合并记录。
struct ExerciseManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExerciseDefinition.canonicalName)
    private var definitions: [ExerciseDefinition]
    @Query(sort: \ExerciseMergeRecord.createdAt, order: .reverse)
    private var mergeRecords: [ExerciseMergeRecord]

    let exercise: ExerciseDefinition

    @State private var mergeTargetID: UUID?
    @State private var errorMessage: String?

    init(exercise: ExerciseDefinition) {
        self.exercise = exercise
        let exerciseID = exercise.id
        var definitionDescriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.canonicalName)]
        )
        definitionDescriptor.fetchLimit = 2000
        _definitions = Query(definitionDescriptor)
        var mergeDescriptor = FetchDescriptor<ExerciseMergeRecord>(
            predicate: #Predicate {
                $0.sourceExerciseID == exerciseID && $0.undoneAt == nil
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        mergeDescriptor.fetchLimit = 1
        _mergeRecords = Query(mergeDescriptor)
    }

    private var mergeTargets: [ExerciseDefinition] {
        definitions.filter { $0.id != exercise.id }
    }

    var body: some View {
        Form {
            Section("动作管理") {
                if exercise.isArchived {
                    if let latestMerge = mergeRecords.first {
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
        .navigationTitle("管理动作")
        .navigationBarTitleDisplayMode(.inline)
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
}

/// PRD 020：动作媒体子页，承接示意图生成/上传、肌群图管理与示范视频。
struct ExerciseMediaEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AIService.self) private var ai

    let exercise: ExerciseDefinition

    @State private var errorMessage: String?
    @State private var generatingImageKind: ExerciseImageKind?
    @State private var imagePickerKind: ExerciseImageKind?
    @State private var showsVideoPicker = false
    @State private var guidanceTitle = ""
    @State private var guidanceURL = ""
    @Namespace private var mediaZoomNamespace
    @State private var presentedVideo: MediaAttachmentReference?

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

            let customMuscleMaps = exercise.muscleMaps.filter {
                $0.source == .generated || $0.source == .user
            }
            if !customMuscleMaps.isEmpty {
                Section("肌群图") {
                    ForEach(customMuscleMaps) { reference in
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
                        .mediaZoomSource(id: video.id, in: mediaZoomNamespace)
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
        }
        .navigationTitle("编辑媒体")
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
        .mediaViewerCover(
            item: $presentedVideo,
            attachments: exercise.userDemoVideos,
            namespace: mediaZoomNamespace,
            deletionTitle: "删除这段示范视频？",
            deletionMessage: "视频会从动作库移除；若没有其他记录引用，文件将在数据清理时回收。",
            onDelete: removeUserVideo
        )
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
            errorMessage = "请先在设置的「LLM 配置」中完成配置。图片只会在你主动点击后生成。"
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

    private func addUserVideos(_ media: [PickedMedia]) {
        Task { @MainActor in
            do {
                try await ExerciseDemoVideoLibrary.add(
                    media,
                    to: exercise,
                    in: modelContext
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addUserImages(
        _ media: [PickedMedia],
        kind: ExerciseImageKind
    ) {
        Task { @MainActor in
            let originalValues = exercise.imageReferences
            var values = originalValues
            var createdPaths: [String] = []
            do {
                for item in media {
                    guard case let .image(data) = item else { continue }
                    let path = try await MediaStore.saveImageAsync(data)
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
        do {
            try ExerciseDemoVideoLibrary.remove(
                video,
                from: exercise,
                in: modelContext
            )
        } catch {
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
}

/// 示范视频的共享写入规则：动作详情首屏与媒体编辑子页复用同一套
/// 保存/回滚/文件回收逻辑，避免在多个 View 中复制。
@MainActor
enum ExerciseDemoVideoLibrary {
    static func add(
        _ media: [PickedMedia],
        to exercise: ExerciseDefinition,
        in modelContext: ModelContext
    ) async throws {
        let originalValues = exercise.userDemoVideos
        var values = originalValues
        var createdPaths: [String] = []
        do {
            for item in media {
                guard case let .video(url) = item else { continue }
                let path = try await MediaStore.saveVideoAsync(from: url)
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
            throw error
        }
    }

    static func remove(
        _ video: MediaAttachmentReference,
        from exercise: ExerciseDefinition,
        in modelContext: ModelContext
    ) throws {
        var values = exercise.userDemoVideos
        values.removeAll { $0.id == video.id }
        exercise.userDemoVideos = values
        do {
            try modelContext.save()
            _ = MediaStore.removeStoredFile(at: video.path)
        } catch {
            modelContext.rollback()
            throw error
        }
    }
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

/// Shared gallery for action illustrations; delete is only offered
/// when an `onDelete` handler is provided (media editor).
struct ExerciseImageGallery: View {
    let images: [ExerciseImageReference]
    let fallback: ExerciseImageReference
    let fallbackMessage: String
    var onDelete: ((ExerciseImageReference) -> Void)?

    var body: some View {
        if images.isEmpty {
            ExerciseArtworkView(reference: fallback, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
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
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            HStack {
                Text(reference.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if reference.source != .bundled, let onDelete {
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
