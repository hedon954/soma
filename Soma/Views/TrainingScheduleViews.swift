import SwiftData
import SwiftUI

struct TrainingScheduleHomeSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var cycleDays: Int?
    @Query private var schedules: [TrainingSchedule]

    init() {
        let active = TrainingScheduleStatus.active.rawValue
        var descriptor = FetchDescriptor<TrainingSchedule>(
            predicate: #Predicate { $0.statusRaw == active },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        _schedules = Query(descriptor)
    }

    var body: some View {
        SectionHeading(title: "训练计划")
        if let schedule = schedules.first {
            NavigationLink {
                TrainingScheduleDetailView(schedule: schedule)
            } label: {
                AppCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(schedule.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                        Text(cycleDays.map { "\($0) 天一轮" } ?? "查看训练安排")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .onAppear {
                cycleDays = try? TrainingContentCompiler.days(
                    scheduleID: schedule.id, slots: schedule.slots, in: modelContext, validating: false
                ).count
            }
            NavigationLink("新建训练计划") { TrainingScheduleEditorView(schedule: nil) }
        } else {
            EmptyStateCard(
                icon: "calendar",
                title: "还没有训练计划",
                message: "把动作、课程或计划排进每一天。休息也是一天。"
            )
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    newScheduleButton
                    coachScheduleButton
                }
                VStack(spacing: 8) {
                    newScheduleButton
                    coachScheduleButton
                }
            }
        }
    }

    private var newScheduleButton: some View {
        NavigationLink {
            TrainingScheduleEditorView(schedule: nil)
        } label: {
            Text("新建训练计划")
                .frame(maxWidth: .infinity)
        }
        .appPrimaryButtonStyle()
    }

    private var coachScheduleButton: some View {
        Button {
            CoachComposerCommand.pendingSend = ScheduleDraftAnswerText.opening
            NotificationCenter.default.post(name: .sendCoachMessage, object: nil)
        } label: {
            Text("教练来排")
                .frame(maxWidth: .infinity)
        }
        .appSecondaryButtonStyle()
        .accessibilityLabel("用教练起草训练计划")
    }
}

struct TrainingScheduleDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var programs: [TrainingProgram]

    let schedule: TrainingSchedule
    @State private var resolution = TrainingScheduleResolution(
        attention: .settled,
        expiredDueDays: [],
        probeProgramID: nil
    )
    @State private var errorMessage: String?
    @State private var days: [TrainingContentDay] = []
    @State private var showsStart = false
    @State private var startedSession: WorkoutSession?

    init(schedule: TrainingSchedule) {
        self.schedule = schedule
        let active = TrainingProgramStatus.active.rawValue
        let archived = TrainingProgramStatus.archived.rawValue
        var descriptor = FetchDescriptor<TrainingProgram>(
            predicate: #Predicate {
                $0.statusRaw == active || $0.statusRaw == archived
            }
        )
        descriptor.fetchLimit = 200
        _programs = Query(descriptor)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(days, id: \.id) { day in
                    Text(day.title)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.accent)
                }
                Text(summary)
                    .font(.body)
                    .foregroundStyle(AppTheme.accent)
                actions
            }
            .padding(AppTheme.pagePadding)
            .frame(maxWidth: AppTheme.readableContentMaxWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appPageBackground()
        .navigationTitle(schedule.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TrainingScheduleEditorView(schedule: schedule)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("编辑训练计划")
            }
        }
        .onAppear(perform: refresh)
        .onReceive(
            NotificationCenter.default.publisher(
                for: ModelContext.didSave,
                object: modelContext
            )
        ) { _ in
            refresh()
        }
        .confirmationDialog(
            "选择录像方式",
            isPresented: $showsStart,
            titleVisibility: .visible
        ) {
            Button("每个动作录第一组") { start(with: .enabled) }
            Button("每一组都录") { start(with: .everySet) }
            Button("不录像") { start(with: .disabled) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择后立即开始训练。首组策略会跳过热身组；训练中仍可随时主动录像。")
        }
        .fullScreenCover(item: $startedSession) { session in
            NavigationStack {
                GuidedWorkoutView(sessionID: session.id)
            }
        }
        .alert(
            "无法更新训练计划",
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

    private var summary: String {
        if days.isEmpty {
            return "训练内容暂不可用，请编辑计划后重试。"
        }
        switch resolution.attention {
        case .paused:
            return "已经隔了一整轮没有新的训练记录。可以先练最常完成的一堂，或从今天接上原来的周期。"
        case .restDay:
            return "今天按计划休息。"
        case .settled:
            return "今天的训练已经完成。"
        case let .due(programID, _, makeup):
            let name = programName(programID)
            return makeup ? "把「\(name)」补上。下一次训练机会到来前，仍然只有这一堂。" : "今天是「\(name)」。"
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch resolution.attention {
        case .paused:
            VStack(alignment: .leading, spacing: 12) {
                if let programID = resolution.probeProgramID,
                   days.contains(where: { $0.id == programID && !$0.prescriptions.isEmpty })
                {
                    Button("先练「\(programName(programID))」") {
                        showsStart = true
                    }
                    .appPrimaryButtonStyle()
                }
                Button("从今天接上") {
                    perform { try TrainingScheduleStore.reanchor(schedule, in: modelContext) }
                }
                .appPrimaryButtonStyle()
            }
        case let .due(programID, dueDay, _):
            VStack(alignment: .leading, spacing: 12) {
                Button(resolution.attention.isMakeup ? "补上这次训练" : "开始今天的训练") {
                    showsStart = true
                }
                .appPrimaryButtonStyle()
                .disabled(!days.contains { $0.id == programID && !$0.prescriptions.isEmpty })
                Button("今天休息") {
                    perform {
                        try TrainingScheduleStore.recordRest(
                            schedule,
                            dueDay: dueDay,
                            in: modelContext
                        )
                    }
                }
            }
        case .restDay, .settled:
            EmptyView()
        }
    }

    private func programName(_ id: UUID) -> String {
        days.first { $0.id == id }?.title ?? "训练内容"
    }

    private func refresh() {
        do {
            days = try TrainingContentCompiler.days(
                scheduleID: schedule.id, slots: schedule.slots, in: modelContext
            )
            resolution = try TrainingScheduleStore.sync(schedule, in: modelContext)
        } catch {
            days = []
            errorMessage = AppErrorMessage.message(for: error, operation: .general)
        }
    }

    private func start(with policy: AutoRecordingPolicy) {
        let programID: UUID? = switch resolution.attention {
        case let .due(id, _, _):
            id
        case .paused:
            resolution.probeProgramID
        default:
            nil
        }
        guard let programID, let day = days.first(where: { $0.id == programID }) else {
            return
        }
        do {
            WorkoutInterfaceOrientationPolicy.shared.setGuidedWorkoutActive(true)
            startedSession = try TrainingPlanStore.startSession(
                prescriptions: day.prescriptions,
                sourceID: day.id,
                name: schedule.name + " · " + day.title,
                autoRecordingPolicy: policy,
                in: modelContext
            )
            showsStart = false
        } catch {
            WorkoutInterfaceOrientationPolicy.shared.setGuidedWorkoutActive(false)
            errorMessage = AppErrorMessage.message(for: error, operation: .general)
        }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            refresh()
        } catch {
            errorMessage = AppErrorMessage.message(for: error, operation: .general)
        }
    }
}

private extension TrainingScheduleAttention {
    var isMakeup: Bool {
        if case let .due(_, _, makeup) = self {
            return makeup
        }
        return false
    }
}
