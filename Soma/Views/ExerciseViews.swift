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
            // PRD 020：列表行降密度——缩小缩略图、副文案压到一行。
            HStack(spacing: 12) {
                ExerciseArtworkView(
                    reference: definition.actionIllustrations.last
                        ?? BundledExerciseCatalog.fallbackActionIllustration,
                    contentMode: .fill
                )
                .frame(
                    width: AppTheme.listThumbnailSize.width,
                    height: AppTheme.listThumbnailSize.height
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius))

                VStack(alignment: .leading, spacing: 4) {
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
                            .lineLimit(1)
                    } else {
                        Text("暂无训练历史")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, AppTheme.listRowVerticalPadding)
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

/// PRD 020：动作详情首屏只读——示意图、名称、教练提示（折叠）、
/// 紧凑肌群图与最近训练；编辑、媒体与管理下沉到工具栏菜单的子页。
struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutEntry.date, order: .reverse)
    private var workouts: [WorkoutEntry]
    @Query(sort: \ExercisePerformance.order)
    private var performances: [ExercisePerformance]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @Query(sort: \WorkoutSet.order)
    private var workoutSets: [WorkoutSet]

    let exercise: ExerciseDefinition

    @State private var olderHistoryExpanded = false
    @State private var showsContentEditor = false
    @State private var showsMediaEditor = false
    @State private var showsDemoVideoPicker = false
    @State private var presentedDemoVideo: MediaAttachmentReference?
    @State private var demoVideoError: String?

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

    var body: some View {
        Form {
            Section("动作示意图") {
                ExerciseImageGallery(
                    images: exercise.actionIllustrations,
                    fallback: BundledExerciseCatalog.fallbackActionIllustration,
                    fallbackMessage: "当前显示通用占位图。可在「编辑媒体」中生成或上传专属示意图。"
                )
            }

            Section("标准动作") {
                LabeledContent("名称", value: exercise.canonicalName)
                if !exercise.primaryMuscles.isEmpty {
                    LabeledContent(
                        "主要肌群",
                        value: exercise.primaryMuscles.joined(separator: "、")
                    )
                }
                if !exercise.coachingNotes
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    Text(exercise.coachingNotes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                MuscleMapView(
                    intensities: MuscleGroupMapping.intensityMap(
                        primary: exercise.primaryMuscles,
                        secondary: exercise.secondaryMuscles
                    ),
                    showsBothSides: true,
                    height: 210,
                    allowsExpansion: true
                )
            } header: {
                Text("常见受力")
            } footer: {
                Text("着色按主要/辅助肌群确定性生成，不是个人受力测量。轻点可放大。")
            }

            Section("示范视频") {
                if !exercise.userDemoVideos.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(exercise.userDemoVideos) { video in
                                Button {
                                    presentedDemoVideo = video
                                } label: {
                                    VideoPosterView(path: video.path)
                                        .frame(width: 128, height: 168)
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius: AppTheme.controlRadius,
                                                style: .continuous
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("播放我的示范视频")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                Button {
                    showsDemoVideoPicker = true
                } label: {
                    Label("上传示范视频", systemImage: "video.badge.plus")
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
                ForEach(Array(allHistory.prefix(5))) { item in
                    historyLink(item)
                }
                if allHistory.count > 5 {
                    DisclosureGroup(
                        "更早记录（\(allHistory.count - 5) 条）",
                        isExpanded: $olderHistoryExpanded
                    ) {
                        ForEach(Array(allHistory.dropFirst(5))) { item in
                            historyLink(item)
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.canonicalName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showsContentEditor = true
                    } label: {
                        Label("编辑动作", systemImage: "square.and.pencil")
                    }
                    Button {
                        showsMediaEditor = true
                    } label: {
                        Label("编辑媒体", systemImage: "photo.on.rectangle.angled")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("编辑与管理")
                }
            }
        }
        .navigationDestination(isPresented: $showsContentEditor) {
            ExerciseContentEditorView(exercise: exercise)
        }
        .navigationDestination(isPresented: $showsMediaEditor) {
            ExerciseMediaEditorView(exercise: exercise)
        }
        .sheet(isPresented: $showsDemoVideoPicker) {
            MediaSourceDialog(
                allowsVideo: true,
                selectionLimit: 5
            ) { media in
                addDemoVideos(media)
            }
        }
        .fullScreenCover(item: $presentedDemoVideo) { selected in
            MediaViewer(
                attachments: exercise.userDemoVideos,
                initialAttachmentID: selected.id,
                deletionTitle: "删除这段示范视频？",
                deletionMessage: "视频会从动作库移除；若没有其他记录引用，文件将在数据清理时回收。",
                onDelete: removeDemoVideo
            )
        }
        .alert(
            "无法完成操作",
            isPresented: Binding(
                get: { demoVideoError != nil },
                set: {
                    if !$0 {
                        demoVideoError = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(demoVideoError ?? "")
        }
    }

    private func addDemoVideos(_ media: [PickedMedia]) {
        do {
            try ExerciseDemoVideoLibrary.add(
                media,
                to: exercise,
                in: modelContext
            )
        } catch {
            demoVideoError = error.localizedDescription
        }
    }

    private func removeDemoVideo(_ video: MediaAttachmentReference) {
        do {
            try ExerciseDemoVideoLibrary.remove(
                video,
                from: exercise,
                in: modelContext
            )
        } catch {
            demoVideoError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func historyLink(_ item: ExerciseHistoryItem) -> some View {
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
