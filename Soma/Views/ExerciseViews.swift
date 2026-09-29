import Charts
import SwiftData
import SwiftUI
import UIKit

struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let exercise: ExerciseDefinition
    let planPrescription: TemplateExercisePrescription?

    @State private var workouts: [WorkoutEntry] = []
    @State private var performances: [ExercisePerformance] = []
    @State private var historyLimit = 50
    @State private var historyRevision = 0
    @State private var sourceHasMoreHistory = false
    @State private var olderHistoryExpanded = false
    @State private var showsContentEditor = false
    @State private var showsMediaEditor = false
    @State private var showsManagement = false
    @State private var showsDemoVideoPicker = false
    @Namespace private var mediaZoomNamespace
    @State private var presentedDemoVideo: MediaAttachmentReference?
    @State private var demoVideoError: String?

    init(
        exercise: ExerciseDefinition,
        planPrescription: TemplateExercisePrescription? = nil
    ) {
        self.exercise = exercise
        self.planPrescription = planPrescription
    }

    var body: some View {
        let historyProjection = ExerciseDetailHistoryProjection(
            workouts: workouts,
            performances: performances,
            exerciseID: exercise.id,
            historyLimit: historyLimit,
            sourceHasMoreHistory: sourceHasMoreHistory
        )

        return Form {
            if let planPrescription {
                Section("本课程目标") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("当前处方", systemImage: "scope")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.trainingAccent)
                        Text(
                            WorkoutPrescriptionFormatter.exerciseSummary(
                                planPrescription
                            )
                        )
                        .font(.subheadline.monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                        if Set(planPrescription.plannedSets.map(\.targetKind)).count > 1 {
                            Label(
                                "包含次数和时长两种目标，请按每段单位执行",
                                systemImage: "exclamationmark.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(AppTheme.warning)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("动作示意图") {
                ExerciseImageGallery(
                    images: exercise.actionIllustrations,
                    fallback: BundledExerciseCatalog.fallbackActionIllustration,
                    fallbackMessage: "当前显示通用占位图。可在「编辑媒体」中生成或上传专属示意图。"
                )
            }

            Section("标准动作") {
                LabeledContent("名称", value: exercise.canonicalName)
                LabeledContent("完成方式", value: exercise.targetKind.displayName)
                LabeledContent("左右方式", value: exercise.laterality.displayName)
                if !exercise.primaryMuscles.isEmpty || !exercise.secondaryMuscles.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        if !exercise.primaryMuscles.isEmpty {
                            muscleSummaryRow(
                                title: "主要肌群",
                                muscles: exercise.primaryMuscles
                            )
                        }
                        if !exercise.secondaryMuscles.isEmpty {
                            muscleSummaryRow(
                                title: "辅助肌群",
                                muscles: exercise.secondaryMuscles
                            )
                        }
                        if !exercise.coachingNotes
                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        {
                            Text(exercise.coachingNotes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        MuscleMapView(
                            intensities: MuscleGroupMapping.intensityMap(
                                primary: exercise.primaryMuscles,
                                secondary: exercise.secondaryMuscles
                            ),
                            showsBothSides: true,
                            height: 190,
                            allowsExpansion: true
                        )
                        Text("训练橙表示通用主要/辅助肌群，不是个人受力测量。轻点可放大。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
                                .mediaZoomSource(id: video.id, in: mediaZoomNamespace)
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

            Section {
                if let latest = historyProjection.allHistory.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最近一次")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(latest.date.formatted(
                            date: .abbreviated,
                            time: .shortened
                        ))
                        .font(.subheadline.weight(.medium))
                        Text(latest.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)

                    if let latestVolume = historyProjection.latestVolume {
                        volumeTrendView(
                            latestVolume: latestVolume,
                            points: historyProjection.displayedVolumeTrend,
                            change: historyProjection.volumeChange
                        )
                    }
                } else {
                    Text("完成一次这个动作后，这里会显示最近记录与容量趋势。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
            } header: {
                Text("训练概览")
            } footer: {
                if historyProjection.latestVolume != nil {
                    Text("容量只统计同时记录了次数和外部重量的完成组；缺失值与自重不参与计算。")
                }
            }

            if !historyProjection.displayedHistory.isEmpty {
                Section {
                    ForEach(historyProjection.displayedHistory.prefix(5)) { item in
                        historyLink(item)
                    }
                    if historyProjection.displayedHistory.count > 5 {
                        DisclosureGroup(
                            "更早记录（\(historyProjection.displayedHistory.count - 5) 条）",
                            isExpanded: $olderHistoryExpanded
                        ) {
                            ForEach(historyProjection.displayedHistory.dropFirst(5)) { item in
                                historyLink(item)
                            }
                        }
                    }
                    if historyProjection.hasMoreHistory {
                        Button("再加载 50 条") {
                            historyLimit += 50
                            olderHistoryExpanded = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                } header: {
                    HStack {
                        Text("训练记录")
                        Spacer()
                        Text(
                            "\(historyProjection.displayedHistory.count) 条\(historyProjection.hasMoreHistory ? "+" : "")"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(exercise.canonicalName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: ExerciseHistoryLoadRequest(
            limit: historyLimit,
            revision: historyRevision
        )) {
            loadHistory()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: ModelContext.didSave,
                object: modelContext
            )
        ) { notification in
            guard ModelContextSaveImpact.affectsExerciseHistory(
                notification,
                exerciseID: exercise.id,
                in: modelContext
            ) else {
                return
            }
            historyRevision &+= 1
        }
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
                    Button {
                        showsManagement = true
                    } label: {
                        Label("管理动作", systemImage: "archivebox")
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
        .navigationDestination(isPresented: $showsManagement) {
            ExerciseManagementView(exercise: exercise)
        }
        .sheet(isPresented: $showsDemoVideoPicker) {
            MediaSourceDialog(
                allowsVideo: true,
                selectionLimit: 5
            ) { media in
                addDemoVideos(media)
            }
        }
        .mediaViewerCover(
            item: $presentedDemoVideo,
            attachments: exercise.userDemoVideos,
            namespace: mediaZoomNamespace,
            deletionTitle: "删除这段示范视频？",
            deletionMessage: "视频会从动作库移除；若没有其他记录引用，文件将在数据清理时回收。",
            onDelete: removeDemoVideo
        )
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

    private func muscleSummaryRow(title: String, muscles: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Text(muscles.joined(separator: "、"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func addDemoVideos(_ media: [PickedMedia]) {
        Task { @MainActor in
            do {
                try await ExerciseDemoVideoLibrary.add(
                    media,
                    to: exercise,
                    in: modelContext
                )
            } catch {
                demoVideoError = AppErrorMessage.message(for: error, operation: .media)
            }
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
            demoVideoError = AppErrorMessage.message(for: error, operation: .media)
        }
    }

    private func loadHistory() {
        let exerciseID = exercise.id
        var workoutDescriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.exerciseID == exerciseID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        workoutDescriptor.fetchLimit = historyLimit + 1

        var performanceDescriptor = FetchDescriptor<ExercisePerformance>(
            predicate: #Predicate { $0.exerciseID == exerciseID }
        )
        // 未物化的旧 Session 只是当前投影的兜底，按同一页长增量读取并设 200 条硬上限。
        performanceDescriptor.fetchLimit = min(historyLimit + 1, 201)

        let fetchedWorkouts = (try? modelContext.fetch(workoutDescriptor)) ?? []
        let fetchedPerformances = (try? modelContext.fetch(performanceDescriptor)) ?? []
        sourceHasMoreHistory = fetchedWorkouts.count > historyLimit
            || (historyLimit < 200 && fetchedPerformances.count > historyLimit)
        workouts = Array(fetchedWorkouts.prefix(historyLimit))
        performances = Array(fetchedPerformances.prefix(min(historyLimit, 200)))
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
        VStack(alignment: .leading, spacing: 5) {
            Text(item.date.formatted(
                date: .abbreviated,
                time: .shortened
            ))
            .font(.subheadline.weight(.medium))
            Text(item.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }

    private func volumeTrendView(
        latestVolume: Double,
        points: [ExerciseVolumePoint],
        change: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                volumeMetric(
                    value: "\(number(latestVolume)) kg",
                    label: "最近容量"
                )
                if let change {
                    volumeMetric(
                        value: change.formatted(
                            .percent.precision(.fractionLength(0))
                        ),
                        label: "较上次"
                    )
                }
            }
            if points.count > 1 {
                Chart(points) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("容量", point.volume)
                    )
                    .interpolationMethod(.linear)
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 2.25,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .foregroundStyle(AppMetricRole.trainingLoad.accent)
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("容量", point.volume)
                    )
                    .symbolSize(34)
                    .foregroundStyle(AppMetricRole.trainingLoad.accent)
                    if points.count <= 4 {
                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("容量", point.volume)
                        )
                        .foregroundStyle(.clear)
                        .annotation(position: .top) {
                            Text(number(point.volume))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: points.map(\.date)) {
                        AxisGridLine()
                            .foregroundStyle(AppTheme.separator)
                        AxisTick()
                            .foregroundStyle(AppTheme.separator)
                        AxisValueLabel(format: .dateTime.month().day())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 150)
                .accessibilityLabel("最近有效训练容量趋势")
                .accessibilityValue(volumeTrendAccessibilityValue(points))
            }
        }
    }

    private func volumeMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.medium).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func volumeTrendAccessibilityValue(
        _ points: [ExerciseVolumePoint]
    ) -> String {
        points.map {
            "\($0.date.formatted(date: .abbreviated, time: .omitted)) \(number($0.volume)) 千克"
        }.joined(separator: "，")
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 1)))
    }
}

private struct ExerciseHistoryLoadRequest: Hashable {
    let limit: Int
    let revision: Int
}

/// 动作详情一次 body 只构建一份历史投影。此前 `allHistory`、分页列表、趋势和
/// 变化率会沿多个 computed property 重复合并、排序与扫描同一批记录。
private struct ExerciseDetailHistoryProjection {
    let allHistory: [ExerciseHistoryItem]
    let displayedHistory: [ExerciseHistoryItem]
    let hasMoreHistory: Bool
    let displayedVolumeTrend: [ExerciseVolumePoint]
    let latestVolume: Double?
    let volumeChange: Double?

    init(
        workouts: [WorkoutEntry],
        performances: [ExercisePerformance],
        exerciseID: UUID,
        historyLimit: Int,
        sourceHasMoreHistory: Bool
    ) {
        let projectedPerformanceIDs = Set(
            workouts.compactMap(\.sourcePerformanceID)
        )
        let sessionHistory: [ExerciseSessionHistory] = performances.compactMap { performance in
            guard performance.exerciseID == exerciseID,
                  !projectedPerformanceIDs.contains(performance.id),
                  !performance.workoutProjectionSuppressed,
                  let session = performance.session
            else {
                return nil
            }
            let sets = performance.workoutSets.filter {
                $0.status == .completed
            }
            guard !sets.isEmpty else { return nil }
            return ExerciseSessionHistory(
                performance: performance,
                session: session,
                sets: sets
            )
        }

        let history = (
            workouts.map(ExerciseHistoryItem.legacy)
                + sessionHistory.map(ExerciseHistoryItem.session)
        ).sorted { $0.date > $1.date }
        allHistory = history
        displayedHistory = Array(history.prefix(historyLimit))
        hasMoreHistory = sourceHasMoreHistory || history.count > historyLimit

        let trend: [ExerciseVolumePoint] = history.compactMap { item in
            guard let volume = item.volume, volume > 0 else { return nil }
            return ExerciseVolumePoint(
                id: item.id,
                date: item.date,
                volume: volume
            )
        }
        .sorted { $0.date < $1.date }
        let displayedTrend = Array(trend.suffix(12))
        displayedVolumeTrend = displayedTrend
        latestVolume = displayedTrend.last?.volume
        if displayedTrend.count >= 2,
           let latest = displayedTrend.last?.volume,
           let previous = displayedTrend.dropLast().last?.volume,
           previous > 0
        {
            volumeChange = (latest - previous) / previous
        } else {
            volumeChange = nil
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
        WorkoutHistoryFormatter.text(for: sets)
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
