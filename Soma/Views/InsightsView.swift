import SwiftData
import SwiftUI

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(DataSpaceController.self) private var dataSpace
    @State private var period: ProgressPeriod
    @State private var anchorDate: Date
    @State private var revision = 0
    @State private var snapshot: ProgressHistorySnapshot?
    @State private var errorMessage: String?
    @State private var healthError: String?
    @State private var showingCalendar = false
    @State private var showingSources = false
    @State private var calendarDate = Date.now
    @State private var followsCurrentPeriod: Bool

    init(initialPeriod: ProgressPeriod = .day, initialDate: Date = .now) {
        _period = State(initialValue: initialPeriod)
        _anchorDate = State(initialValue: initialDate)
        _followsCurrentPeriod = State(initialValue: Calendar.current.isDateInToday(initialDate))
    }

    private var window: ProgressPeriodWindow {
        period.window(containing: anchorDate)
    }

    private var request: ProgressHistoryRequest {
        .init(window: window, revision: revision, timeZoneID: TimeZone.current.identifier)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                periodControls
                if let errorMessage {
                    HStack {
                        Text(errorMessage).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button("重试") { revision += 1 }.frame(minHeight: 44)
                    }
                }
                if let snapshot, snapshot.window == window {
                    ProgressEnergyHistoryCard(snapshot: snapshot) { showingSources = true }
                    if period != .day {
                        ProgressTrainingBodyCards(snapshot: snapshot)
                    }
                    if period == .day, let day = snapshot.days.first, !day.isFuture {
                        ProgressDayRecordSections(day: day)
                    }
                    ProgressResourceLinks()
                } else if errorMessage == nil {
                    ProgressView("正在加载进展…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .accessibilityIdentifier("insights-loading")
                }
            }
            .padding(AppTheme.pagePadding)
            .padding(.bottom, 72)
            .frame(maxWidth: AppTheme.readableContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("insights-content")
        .appPageBackground()
        .navigationTitle("进展")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    calendarDate = anchorDate
                    showingCalendar = true
                } label: {
                    Image(systemName: "calendar")
                }.accessibilityLabel("选择日期")
            }
        }
        .sheet(isPresented: $showingCalendar) {
            NavigationStack {
                DatePicker("日期", selection: $calendarDate, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical).padding()
                    .navigationTitle("选择日期")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { showingCalendar = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") {
                                anchorDate = calendarDate
                                period = .day
                                followsCurrentPeriod = Calendar.current.isDateInToday(calendarDate)
                                showingCalendar = false
                            }
                        }
                    }
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSources) {
            if let snapshot {
                ProgressEnergySourcesView(snapshot: snapshot, healthError: healthError)
            }
        }
        .task(id: request) { await load(request) }
        .refreshable { revision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { notification in
            if ModelContextSaveImpact.affectsInsights(notification, in: modelContext) {
                revision += 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshDate() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refreshDate() }
        .onChange(of: period) {
            if followsCurrentPeriod {
                anchorDate = .now
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                refreshDate()
            }
        }
    }

    private var periodControls: some View {
        VStack(spacing: 16) {
            Picker("统计周期", selection: $period) {
                ForEach(ProgressPeriod.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("progress-period-picker")
            HStack(spacing: 8) {
                Button { move(by: -1) } label: {
                    Image(systemName: "chevron.left").dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(width: 44, height: 44)
                }.accessibilityLabel("上一\(period.title)")
                Text(window.title()).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("progress-date-range")
                Button { move(by: 1) } label: {
                    Image(systemName: "chevron.right").dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(width: 44, height: 44)
                }
                .disabled(!window.canMoveForward())
                .accessibilityLabel("下一\(period.title)")
            }.buttonStyle(.plain)
            if window != period.window(containing: .now) {
                Button(period.returnTitle) { anchorDate = .now; followsCurrentPeriod = true }
                    .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
            }
        }
    }

    private func move(by amount: Int) {
        let destination = window.shifted(by: amount)
        followsCurrentPeriod = destination == period.window(containing: .now)
        anchorDate = followsCurrentPeriod ? .now : destination.start
    }

    private func refreshDate() {
        if followsCurrentPeriod {
            anchorDate = .now
        }
        revision += 1
    }

    private func load(_ key: ProgressHistoryRequest) async {
        errorMessage = nil
        healthError = nil
        let container = modelContext.container
        let calendar = Calendar.current
        let now = Date.now
        let personal = dataSpace.activeSpace == .personal && !AppTestRuntime.isRunning
        let loader = Task.detached(priority: .userInitiated) {
            try await ProgressHistoryLoader(modelContainer: container).load(window: key.window)
        }
        var readingHealth = false
        do {
            let facts = try await withTaskCancellationHandler { try await loader.value } onCancel: { loader.cancel() }
            try Task.checkCancellation()
            guard request == key else { return }
            let local = Task.detached(priority: .userInitiated) {
                ProgressHistoryProjection.build(window: key.window, records: facts.records, profile: facts.profile, now: now, calendar: calendar)
            }
            let projection = await withTaskCancellationHandler { await local.value } onCancel: { local.cancel() }
            try Task.checkCancellation()
            guard request == key else { return }
            snapshot = projection
            guard personal else { return }
            readingHealth = true
            let healthTask = Task.detached(priority: .utility) {
                let start = calendar.date(byAdding: .day, value: -30, to: key.window.start) ?? key.window.start
                let health = try await HealthEnergyHistoryReader().read(from: start, to: min(key.window.end, now), calendar: calendar)
                return ProgressHistoryProjection.build(
                    window: key.window, records: facts.records, profile: facts.profile, history: health.days, now: now, calendar: calendar
                )
            }
            let enriched = try await withTaskCancellationHandler { try await healthTask.value } onCancel: { healthTask.cancel() }
            try Task.checkCancellation()
            guard request == key else { return }
            snapshot = enriched
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, request == key else { return }
            if readingHealth {
                healthError = "设备能量暂时无法读取"
            } else {
                errorMessage = "进展暂时无法加载"
            }
        }
    }
}

private struct ProgressHistoryRequest: Hashable {
    let window: ProgressPeriodWindow
    let revision: Int
    let timeZoneID: String
}

struct ProgressRecentActivityDestination: View {
    let activity: ProgressRecentActivity

    var body: some View {
        switch activity.kind {
        case .workout:
            ProgressWorkoutDestination(recordID: activity.id)
        case .meal:
            ProgressMealDestination(recordID: activity.id)
        case .body:
            ProgressBodyDestination(recordID: activity.id)
        }
    }
}

private struct ProgressWorkoutDestination: View {
    @Query private var records: [WorkoutEntry]

    init(recordID: UUID) {
        var descriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.id == recordID }
        )
        descriptor.fetchLimit = 1
        _records = Query(descriptor)
    }

    var body: some View {
        if let record = records.first {
            WorkoutRecordDetailView(workout: record)
        } else {
            ContentUnavailableView("记录已删除", systemImage: "tray")
        }
    }
}

private struct ProgressMealDestination: View {
    @Query private var records: [MealEntry]

    init(recordID: UUID) {
        var descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.id == recordID }
        )
        descriptor.fetchLimit = 1
        _records = Query(descriptor)
    }

    var body: some View {
        if let record = records.first {
            MealRecordDetailView(meal: record)
        } else {
            ContentUnavailableView("记录已删除", systemImage: "tray")
        }
    }
}

private struct ProgressBodyDestination: View {
    @Query private var records: [BodyEntry]

    init(recordID: UUID) {
        var descriptor = FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.id == recordID }
        )
        descriptor.fetchLimit = 1
        _records = Query(descriptor)
    }

    var body: some View {
        if let record = records.first {
            BodyRecordDetailView(entry: record)
        } else {
            ContentUnavailableView("记录已删除", systemImage: "tray")
        }
    }
}

struct InsightsRecordCounts: Equatable, Sendable {
    var workouts = 0
    var meals = 0
    var bodyEntries = 0
}
