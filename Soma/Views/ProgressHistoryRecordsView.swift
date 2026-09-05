import Charts
import SwiftData
import SwiftUI

struct ProgressTrainingBodyCards: View {
    let snapshot: ProgressHistorySnapshot
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 14) {
            NavigationLink {
                ProgressPeriodRecordsView(snapshot: snapshot, kind: .workout)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "dumbbell.fill").foregroundStyle(AppTheme.trainingAccent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("训练").font(.headline)
                        Text("\(snapshot.trainingDayCount) 天 · \(snapshot.logicalSets) 组").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    if !dynamicTypeSize.isAccessibilitySize, ProgressDetailTrend.showsMiniChart(snapshot: snapshot, metric: .sets) {
                        Chart(snapshot.energyBuckets) { bucket in
                            RectangleMark(
                                xStart: .value("开始", bucket.start.addingTimeInterval(bucket.end.timeIntervalSince(bucket.start) * 0.2)),
                                xEnd: .value("结束", bucket.end.addingTimeInterval(-bucket.end.timeIntervalSince(bucket.start) * 0.2)),
                                yStart: .value("基线", 0),
                                yEnd: .value("逻辑组数", snapshot.days.filter { $0.date >= bucket.start && $0.date < bucket.end }.reduce(0) { $0 + $1.logicalSets })
                            )
                            .foregroundStyle(AppMetricRole.consistency.accent)
                        }.chartXAxis(.hidden).chartYAxis(.hidden).frame(width: 115, height: 42)
                            .accessibilityIdentifier("progress-training-mini-chart")
                    }
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }.padding(18).background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).accessibilityIdentifier("progress-training-summary")
            NavigationLink {
                ProgressPeriodRecordsView(snapshot: snapshot, kind: .body)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "scalemass.fill").foregroundStyle(AppTheme.bodyAccent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("身体").font(.headline)
                        Text(lastWeight?.weight.map { "最近体重 \($0.formatted()) kg" } ?? "未记录体重")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let lastWeight {
                            Text(lastWeight.activity.date.formatted(.dateTime.month().day())).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 6)
                    if !dynamicTypeSize.isAccessibilitySize, ProgressDetailTrend.showsMiniChart(snapshot: snapshot, metric: .weight) {
                        Chart(weightPoints) { point in
                            LineMark(x: .value("日期", point.date), y: .value("体重", point.value)).foregroundStyle(AppTheme.bodyAccent)
                            PointMark(x: .value("日期", point.date), y: .value("体重", point.value)).foregroundStyle(AppTheme.bodyAccent)
                        }.chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: weightRange).frame(width: 115, height: 42)
                            .accessibilityIdentifier("progress-body-mini-chart")
                    }
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }.padding(18).background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).accessibilityIdentifier("progress-body-summary")
        }
    }

    private var weightRecords: [ProgressHistoryRecord] {
        snapshot.days.compactMap(\.latestWeight)
    }

    private var lastWeight: ProgressHistoryRecord? {
        weightRecords.last
    }

    private var weightPoints: [ProgressDetailTrendPoint] {
        ProgressDetailTrend.points(snapshot: snapshot, metric: .weight)
    }

    private var weightRange: ClosedRange<Double> {
        let values = weightPoints.map(\.value)
        return max(0, (values.min() ?? 0) - 1) ... ((values.max() ?? 1) + 1)
    }
}

struct ProgressDayRecordSections: View {
    let day: ProgressDailyMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach([ProgressRecentActivity.Kind.meal, .workout, .body], id: \.title) { kind in
                let records = day.records.filter { $0.activity.kind == kind }
                if !records.isEmpty {
                    HStack {
                        Text(kind.title).font(.headline)
                        Spacer()
                        if kind == .workout {
                            ProgressDayShareButton(day: day.date)
                        }
                    }
                    ForEach(records, id: \.activity.id) { record in
                        NavigationLink { ProgressRecentActivityDestination(activity: record.activity) } label: {
                            ProgressRecentActivityRow(activity: record.activity)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct ProgressPeriodRecordsView: View {
    @State private var snapshot: ProgressHistorySnapshot
    let kind: ProgressRecentActivity.Kind
    @Environment(\.modelContext) private var context
    @State private var revision = 0
    @State private var errorMessage: String?

    init(snapshot: ProgressHistorySnapshot, kind: ProgressRecentActivity.Kind) {
        _snapshot = State(initialValue: snapshot)
        self.kind = kind
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                    Button("重试") { revision += 1 }
                }
            }
            Section {
                Text(snapshot.window.title()).foregroundStyle(.secondary)
                if kind == .workout {
                    LabeledContent("训练天数", value: "\(snapshot.trainingDayCount) 天")
                    LabeledContent("工作组", value: "\(snapshot.logicalSets) 组")
                    LabeledContent("已记录容量", value: "\(snapshot.volume.formatted()) kg")
                }
            }
            Section {
                ProgressDetailTrendView(snapshot: snapshot, kind: kind)
            }
            if kind == .workout {
                let muscles = ProgressMuscleWorkload.aggregate(snapshot.days.flatMap(\.records))
                if !muscles.isEmpty {
                    Section("肌群工作组") { ProgressMuscleWorkloadView(rows: muscles) }
                }
            }
            ForEach(snapshot.days.filter { day in day.records.contains { $0.activity.kind == kind } }) { day in
                Section {
                    ForEach(day.records.filter { $0.activity.kind == kind }, id: \.activity.id) { record in
                        NavigationLink { ProgressRecentActivityDestination(activity: record.activity) } label: {
                            ProgressRecentActivityRow(activity: record.activity, showsDisclosure: false)
                        }
                    }
                } header: {
                    HStack {
                        Text(day.date.formatted(.dateTime.month().day().weekday()))
                        Spacer()
                        if kind == .workout {
                            ProgressDayShareButton(day: day.date)
                        }
                    }
                }
            }
        }
        .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden).appPageBackground()
        .task(id: revision) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { notification in
            if ModelContextSaveImpact.affectsInsights(notification, in: context) {
                revision += 1
            }
        }
    }

    private func reload() async {
        let container = context.container
        let window = snapshot.window
        let generation = revision
        let task = Task.detached(priority: .userInitiated) {
            let facts = try await ProgressHistoryLoader(modelContainer: container).load(window: window)
            return ProgressHistoryProjection.build(window: window, records: facts.records, profile: facts.profile)
        }
        do {
            let updated = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard !Task.isCancelled, generation == revision else { return }
            snapshot = updated
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == revision else { return }
            errorMessage = "记录暂时无法刷新"
        }
    }
}

struct ProgressDayShareButton: View {
    let day: Date
    @Environment(\.modelContext) private var context
    @State private var model: WorkoutSharePosterModel?
    @State private var failed = false

    var body: some View {
        Button {
            do {
                model = try WorkoutSharePosterBuilder.makeModel(forDay: day, in: context)
                failed = model == nil
            } catch { failed = true }
        } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }
            .accessibilityLabel("分享当天训练")
            .sheet(item: $model) { WorkoutShareSheet(model: $0) }
            .alert("当天训练暂时无法分享", isPresented: $failed) { Button("知道了", role: .cancel) {} }
    }
}

extension ProgressRecentActivity.Kind {
    var title: String {
        switch self {
        case .workout: "训练记录"
        case .meal: "饮食记录"
        case .body: "身体记录"
        }
    }
}
