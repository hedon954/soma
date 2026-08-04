import Photos
import SwiftData
import SwiftUI
import UIKit

struct WorkoutSharePosterModel: Equatable, Identifiable {
    var id = UUID()
    var dateText: String
    var title: String
    var focusMuscles: [String]
    var durationText: String
    var volumeValue: String
    var exerciseCount: Int
    var completedSets: Int
    var intensities: [MuscleGroup: Double]
    var exercises: [ExerciseLine]

    struct ExerciseLine: Equatable, Identifiable {
        var id: UUID
        var name: String
        var setCount: Int
        /// Load only, without the set-count prefix (e.g. `自重 × 5`).
        var loadSummary: String
    }
}

enum WorkoutSharePosterBuilder {
    @MainActor
    static func makeModel(
        session: WorkoutSession,
        in context: ModelContext
    ) -> WorkoutSharePosterModel {
        let summary = TrainingPlanStore.summary(for: session.id, in: context)
        let performances = ((try? context.fetch(FetchDescriptor<ExercisePerformance>())) ?? [])
            .filter { $0.sessionID == session.id }
            .sorted { $0.order < $1.order }
        let sets = (try? context.fetch(FetchDescriptor<WorkoutSet>())) ?? []
        let definitions = Dictionary(
            uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<ExerciseDefinition>())) ?? [])
                .map { ($0.id, $0) }
        )

        let intensityInputs: [(primary: [String], secondary: [String], sets: Int)] = performances.map { performance in
            let completed = sets.filter {
                $0.performanceID == performance.id && $0.status == .completed
            }.count
            let definition = definitions[performance.exerciseID]
            return (
                primary: definition?.primaryMuscles ?? [],
                secondary: definition?.secondaryMuscles ?? [],
                sets: max(completed, 1)
            )
        }
        let intensities = MuscleMapView.intensities(exercises: intensityInputs)
        let focusMuscles = topMuscleNames(from: intensities, limit: 3)

        let exerciseLines: [WorkoutSharePosterModel.ExerciseLine] = performances.compactMap { performance in
            let completed = sets
                .filter { $0.performanceID == performance.id && $0.status == .completed }
                .sorted { $0.order < $1.order }
            guard !completed.isEmpty else { return nil }
            let load = loadSummary(for: completed)
            return WorkoutSharePosterModel.ExerciseLine(
                id: performance.id,
                name: performance.exerciseName,
                setCount: completed.count,
                loadSummary: load
            )
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd EEE"

        let programName = programDisplayName(for: session, in: context)
        let focusTitle = focusMuscles.prefix(2).joined(separator: " · ")
        let volumeValue: String = summary.completedVolume > 0
            ? summary.completedVolume.formatted(.number.precision(.fractionLength(0 ... 1)))
            : "—"

        return WorkoutSharePosterModel(
            dateText: formatter.string(from: session.startedAt),
            title: programName
                ?? (focusTitle.isEmpty ? nil : focusTitle)
                ?? "本次训练",
            focusMuscles: focusMuscles,
            durationText: summary.durationText,
            volumeValue: volumeValue,
            exerciseCount: summary.exerciseCount,
            completedSets: summary.completedSets,
            intensities: intensities,
            exercises: exerciseLines
        )
    }

    private static func topMuscleNames(
        from intensities: [MuscleGroup: Double],
        limit: Int
    ) -> [String] {
        intensities
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key.displayName)
    }

    /// Plan name only — share posters omit template version.
    @MainActor
    static func programDisplayName(
        for session: WorkoutSession,
        in context: ModelContext
    ) -> String? {
        let snapshot = session.programNameSnapshot?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let snapshot, !snapshot.isEmpty {
            return snapshot
        }
        guard let label = TrainingPlanStore.programSourceLabel(
            for: session,
            in: context
        ) else {
            return nil
        }
        if let range = label.range(of: #" · v\d+$"#, options: .regularExpression) {
            return String(label[..<range.lowerBound])
        }
        return label
    }

    /// Compact load summary for the share poster (set count shown separately).
    static func loadSummary(for sets: [WorkoutSet]) -> String {
        let loads = sets.map(loadToken(for:))
        guard let first = loads.first else { return "—" }
        if loads.allSatisfy({ $0 == first }) {
            return first
        }
        let visible = loads.prefix(4)
        let joined = visible.joined(separator: " · ")
        if loads.count > visible.count {
            return "\(joined) 等"
        }
        return joined
    }

    /// Full one-line summary used by tests / callers that want set count inline.
    static func exerciseSummary(for sets: [WorkoutSet]) -> String {
        guard !sets.isEmpty else { return "0组" }
        return "\(sets.count)组 · \(loadSummary(for: sets))"
    }

    private static func loadToken(for set: WorkoutSet) -> String {
        let weight = set.actualWeightKG ?? set.plannedWeightKG
        let reps = set.actualReps ?? set.plannedReps
        let repsText = reps.map(String.init) ?? "—"
        if let weight, weight > 0 {
            let weightText = weight.formatted(.number.precision(.fractionLength(0 ... 1)))
            return "\(weightText)kg × \(repsText)"
        }
        // Bodyweight or missing external load — never show "— × N".
        return "自重 × \(repsText)"
    }
}

/// Shareable poster: one hero card + compact exercise summaries.
/// No avatar, QR, photos, location, training-day streak, or privacy copy on-image.
struct WorkoutSharePosterView: View {
    let model: WorkoutSharePosterModel

    private let ink = Color(red: 0.10, green: 0.18, blue: 0.15)
    private let muted = Color(red: 0.45, green: 0.50, blue: 0.48)
    private let posterWidth: CGFloat = 390

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            heroCard
            detailCard
            footer
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(width: posterWidth, alignment: .leading)
        .background(canvasBackground)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.dateText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(muted)
                Text(model.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if !model.focusMuscles.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(model.focusMuscles, id: \.self) { name in
                            Text(name)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ink.opacity(0.78))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(AppTheme.tint.opacity(0.12))
                                )
                        }
                    }
                }
            }

            HStack(alignment: .center, spacing: 8) {
                MuscleMapView(
                    intensities: model.intensities,
                    showsBothSides: true,
                    showsLabels: false,
                    height: 236,
                    allowsExpansion: false
                )
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    metric(model.volumeValue, unit: "kg", label: "有效容量")
                    metric("\(model.completedSets)", unit: "组", label: "完成组")
                    metric(model.durationText, unit: nil, label: "总耗时")
                }
                .frame(width: 104, alignment: .leading)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.exercises.enumerated()), id: \.element.id) { index, exercise in
                if index > 0 {
                    Divider()
                        .overlay(Color.black.opacity(0.06))
                        .padding(.vertical, 12)
                }
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Text(exercise.loadSummary)
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(muted)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(exercise.setCount)")
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundStyle(ink)
                        Text("组")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(muted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(exercise.setCount)组")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var footer: some View {
        HStack(alignment: .center) {
            Text("Soma")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.tint)
            Spacer()
            Text("本地训练记录")
                .font(.caption.weight(.semibold))
                .foregroundStyle(muted)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func metric(_ value: String, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let unit {
                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(muted)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(muted)
        }
    }

    private var canvasBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.88, green: 0.96, blue: 0.91),
                Color(red: 0.95, green: 0.97, blue: 0.95),
                Color(red: 0.98, green: 0.96, blue: 0.93)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white)
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

struct WorkoutShareSheet: View {
    let model: WorkoutSharePosterModel
    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: UIImage?
    @State private var shareURL: URL?
    @State private var errorMessage: String?
    @State private var saveMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let renderedImage {
                        Image(uiImage: renderedImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.image = renderedImage
                                } label: {
                                    Label("拷贝图片", systemImage: "doc.on.doc")
                                }
                                Button {
                                    Task { await saveToPhotos(renderedImage) }
                                } label: {
                                    Label("保存到相册", systemImage: "square.and.arrow.down")
                                }
                                if let shareURL {
                                    ShareLink(item: shareURL) {
                                        Label("分享…", systemImage: "square.and.arrow.up")
                                    }
                                }
                            }
                            .accessibilityLabel("训练分享海报")
                            .accessibilityHint("长按可保存到相册或分享")
                    } else if errorMessage == nil {
                        ProgressView("正在生成海报…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 80)
                    }

                    if let renderedImage {
                        Button {
                            Task { await saveToPhotos(renderedImage) }
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("保存到相册", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.tint)
                        .disabled(isSaving)
                    }

                    Text("也可长按图片拷贝或保存。海报在本机渲染，不含照片、视频或位置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(16)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.92, green: 0.96, blue: 0.94),
                        Color(uiColor: .systemGroupedBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("分享训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let shareURL, renderedImage != nil {
                        ShareLink(
                            item: shareURL,
                            preview: SharePreview(
                                "Soma 训练海报",
                                image: Image(uiImage: renderedImage ?? UIImage())
                            )
                        ) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                    } else if errorMessage == nil {
                        ProgressView()
                    }
                }
            }
            .task {
                await renderPoster()
            }
            .alert(
                "无法生成分享图",
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
            .alert(
                "保存图片",
                isPresented: Binding(
                    get: { saveMessage != nil },
                    set: {
                        if !$0 {
                            saveMessage = nil
                        }
                    }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveMessage ?? "")
            }
        }
    }

    @MainActor
    private func renderPoster() async {
        let poster = WorkoutSharePosterView(model: model)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = max(UIScreen.main.scale, 2)
        guard let image = renderer.uiImage,
              let data = image.pngData()
        else {
            errorMessage = "本机渲染失败，请稍后重试。"
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("soma-workout-share-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            renderedImage = image
            shareURL = url
        } catch {
            errorMessage = "无法保存分享图片。"
        }
    }

    @MainActor
    private func saveToPhotos(_ image: UIImage) async {
        isSaving = true
        defer { isSaving = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveMessage = "没有相册写入权限。请在系统设置中允许 Soma 添加照片。"
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            saveMessage = "已保存到相册。"
        } catch {
            saveMessage = "保存失败，请稍后重试。"
        }
    }
}
