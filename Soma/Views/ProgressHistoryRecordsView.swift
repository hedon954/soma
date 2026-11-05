import Charts
import SwiftData
import SwiftUI

struct ProgressTrainingBodyCards: View {
    let snapshot: ProgressHistorySnapshot
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let summary = ProgressPeriodSummary.make(snapshot: snapshot) {
            VStack(spacing: 14) {
                summaryLink(summary.training, kind: .workout)
                summaryLink(summary.body, kind: .body)
            }
        }
    }

    private func summaryLink(_ summary: ProgressPeriodSummary.Metric, kind: ProgressRecentActivity.Kind) -> some View {
        let isTraining = kind == .workout
        return NavigationLink {
            ProgressPeriodRecordsView(snapshot: snapshot, kind: kind)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isTraining ? "dumbbell.fill" : "scalemass.fill")
                    .foregroundStyle(isTraining ? AppTheme.trainingAccent : AppTheme.bodyAccent)
                VStack(alignment: .leading, spacing: 6) {
                    Text(isTraining ? "训练" : "身体").font(.headline)
                    Text(summary.value).font(.subheadline).foregroundStyle(.secondary)
                    if let detail = summary.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }.fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                Spacer(minLength: 6)
                if !dynamicTypeSize.isAccessibilitySize, summary.showsChart {
                    miniChart(summary)
                        .accessibilityIdentifier(isTraining ? "progress-training-mini-chart" : "progress-body-mini-chart")
                }
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }.padding(18).background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier(isTraining ? "progress-training-summary" : "progress-body-summary")
    }

    private func miniChart(_ summary: ProgressPeriodSummary.Metric) -> some View {
        let accent = summary.metric.isBody ? AppTheme.bodyAccent
            : summary.metric == .volume ? AppMetricRole.trainingLoad.accent : AppMetricRole.consistency.accent
        let values = summary.points.map(\.value)
        let range = summary.metric.isBody
            ? max(0, (values.min() ?? 0) - 1) ... ((values.max() ?? 1) + 1)
            : 0 ... max(1, values.max() ?? 1)
        return Chart(summary.points) { point in
            if let end = point.end {
                RectangleMark(
                    xStart: .value("开始", point.date.addingTimeInterval(end.timeIntervalSince(point.date) * 0.2)),
                    xEnd: .value("结束", end.addingTimeInterval(-end.timeIntervalSince(point.date) * 0.2)),
                    yStart: .value("基线", 0), yEnd: .value(summary.metric.title, point.value)
                ).foregroundStyle(accent)
            } else {
                LineMark(x: .value("日期", point.date), y: .value(summary.metric.title, point.value)).foregroundStyle(accent)
                PointMark(x: .value("日期", point.date), y: .value(summary.metric.title, point.value)).foregroundStyle(accent)
            }
        }
        .chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: range)
        .frame(width: 95, height: 42)
        .accessibilityLabel("\(summary.chartLabel)，单位\(summary.metric.unit)")
    }
}

struct ProgressDayRecordSections: View {
    let day: ProgressDailyMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 进展「日」展示当日日常活动；「训练记录」区块仍排除（ADR 0146 / Hedon 2026-11-05）。
            let dailyRecords = day.records.filter(\.isDailyActivity)
            if !dailyRecords.isEmpty {
                Text("日常活动").font(.headline)
                ForEach(dailyRecords, id: \.activity.id) { record in
                    NavigationLink { ProgressRecentActivityDestination(activity: record.activity) } label: {
                        ProgressRecentActivityRow(activity: record.activity)
                    }.buttonStyle(.plain)
                }
            }
            ForEach([ProgressRecentActivity.Kind.meal, .workout, .body], id: \.title) { kind in
                let records = day.records.filter {
                    $0.activity.kind == kind && (kind != .workout || !$0.isDailyActivity)
                }
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
            ForEach(ProgressRecordSections.make(snapshot: snapshot, kind: kind)) { day in
                Section {
                    ForEach(day.records, id: \.activity.id) { record in
                        NavigationLink { ProgressRecentActivityDestination(activity: record.activity) } label: {
                            ProgressRecentActivityRow(activity: record.activity, showsDisclosure: false)
                        }
                    }
                } header: {
                    HStack {
                        Text(day.date.formatted(.dateTime.month().day().weekday()))
                            .accessibilityIdentifier("progress-record-day-\(Int(day.date.timeIntervalSince1970))")
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
            try EnergyRuntimePersistence.apply(updated.energyUpdates, in: context)
            snapshot = updated
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == revision else { return }
            errorMessage = AppErrorMessage.message(for: error, operation: .load)
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
