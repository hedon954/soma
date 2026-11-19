import SwiftData
import SwiftUI

struct InsightsView: View {
    @Environment(DailyActivitySyncCoordinator.self) private var activity
    @State private var activityOwner = UUID()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(InsightsSnapshotRevisionState.self) private var insightsRevision
    @State private var period: ProgressPeriod
    @State private var anchorDate: Date
    @State private var revision = 0
    @State private var snapshot: ProgressHistorySnapshot?
    @State private var errorMessage: String?
    @State private var showingCalendar = false
    @State private var showingSources = false
    @State private var showingMealCoverage = false
    @State private var calendarDate = Date.now
    @State private var followsCurrentPeriod: Bool
    @State private var loadedRequest: ProgressHistoryRequest?

    init(initialPeriod: ProgressPeriod = .day, initialDate: Date = .now) {
        _period = State(initialValue: initialPeriod)
        _anchorDate = State(initialValue: initialDate)
        _followsCurrentPeriod = State(initialValue: Calendar.current.isDateInToday(initialDate))
    }

    private var window: ProgressPeriodWindow {
        period.window(containing: anchorDate)
    }

    private var request: ProgressHistoryRequest {
        .init(
            window: window,
            revision: revision &+ insightsRevision.dataRevision,
            timeZoneID: TimeZone.current.identifier
        )
    }

    private var showsCurrentSnapshot: Bool {
        snapshot != nil && loadedRequest?.canDisplay(request) == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                periodControls
                if let errorMessage {
                    HStack {
                        Text(errorMessage).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button("重试") { revision += 1 }.frame(minHeight: 44)
                    }
                }
                if showsCurrentSnapshot, let snapshot {
                    ProgressEnergyHistoryCard(snapshot: snapshot) { showingSources = true }
                    if period != .day {
                        ProgressTrainingBodyCards(snapshot: snapshot)
                    }
                    if period == .day, let day = snapshot.days.first, !day.isFuture {
                        ProgressDayRecordSections(day: day, activityOwner: activityOwner, onBackfillMeals: { showingMealCoverage = true })
                    } else if period == .week || period == .month,
                              snapshot.days.contains(where: { !$0.isFuture && $0.energyDeficitMissingReason != nil })
                    {
                        Button("查看缺项") { showingMealCoverage = true }
                            .frame(minHeight: 44)
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
        .navigationDestination(for: ProgressResourceDestination.self) { $0.view }
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
                ProgressEnergySourcesView(snapshot: snapshot)
            }
        }
        .sheet(isPresented: $showingMealCoverage) {
            if let snapshot, let latest = snapshot.days.last(where: { !$0.isFuture })?.date {
                let pastDays = Calendar.current.dateComponents([.day], from: snapshot.window.start, to: latest).day ?? 0
                let missingExpenditure = Set(snapshot.days.filter { !$0.isFuture && $0.energy.estimate == nil }.map(\.date))
                NavigationStack {
                    MealBackfillView(day: latest, pastDays: pastDays, missingExpenditure: missingExpenditure)
                        .navigationTitle("饮食记录完整度")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("完成") { showingMealCoverage = false } }
                        }
                }
            }
        }
        .task(id: window) {
            if window.period == .day {
                activity.select(date: window.start, owner: activityOwner)
            } else {
                activity.releaseSelection(owner: activityOwner)
            }
        }
        .onChange(of: activity.generation) {
            if window.period == .day {
                activity.select(date: window.start, owner: activityOwner)
            }
        }
        .task(id: request) {
            await load(request)
        }
        #if DEBUG
        .task { await ProgressHistoryTestFixture.listenForDailyActivityUpdates(in: modelContext) }
        #endif
        .onDisappear { activity.releaseSelection(owner: activityOwner) }
        .refreshable { revision += 1 }
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
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(window.title())
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityIdentifier("progress-date-range")
                    if window != period.window(containing: .now) {
                        Button(period.returnTitle) { anchorDate = .now; followsCurrentPeriod = true }
                            .font(.subheadline)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minHeight: 44)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                Button { move(by: 1) } label: {
                    Image(systemName: "chevron.right").dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(width: 44, height: 44)
                }
                .disabled(!window.canMoveForward())
                .accessibilityLabel("下一\(period.title)")
            }.buttonStyle(.plain)
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
        let container = modelContext.container
        let calendar = Calendar.current
        let now = Date.now
        do {
            let projection = try await ProgressHistoryLoader.snapshot(in: container, window: key.window, now: now, calendar: calendar).snapshot
            try Task.checkCancellation()
            guard request == key else { return }
            try EnergyRuntimePersistence.apply(projection.energyUpdates, in: modelContext)
            snapshot = projection
            loadedRequest = key
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, request == key else { return }
            errorMessage = AppErrorMessage.message(for: error, operation: .load)
        }
    }
}

struct ProgressHistoryRequest: Hashable {
    let window: ProgressPeriodWindow
    let revision: Int
    let timeZoneID: String

    func canDisplay(_ other: Self) -> Bool {
        window == other.window && timeZoneID == other.timeZoneID
    }
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
