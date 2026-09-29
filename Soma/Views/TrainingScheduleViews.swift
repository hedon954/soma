import SwiftData
import SwiftUI

struct TrainingScheduleHomeSection: View {
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
                        Text("\(schedule.slots.count) 天一轮")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            EmptyStateCard(
                icon: "calendar",
                title: "还没有训练计划",
                message: "把课程排进每一天。休息也是一天。"
            )
            NavigationLink {
                TrainingScheduleEditorView(schedule: nil)
            } label: {
                Text("新建训练计划")
                    .frame(maxWidth: .infinity)
            }
            .appPrimaryButtonStyle()
        }
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
        switch resolution.attention {
        case .paused:
            return "已经隔了一整轮没有新的训练记录。可以先练最常完成的一堂，或从今天接上原来的周期。"
        case .restDay:
            return "今天按计划休息。"
        case .settled:
            return "今天这堂课已经完成。"
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
                   programs.contains(where: { $0.id == programID })
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
                Button(resolution.attention.isMakeup ? "补上这堂课" : "开始今天的课") {
                    showsStart = true
                }
                .appPrimaryButtonStyle()
                .disabled(!programs.contains { $0.id == programID })
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
        programs.first { $0.id == id }?.name ?? "课程"
    }

    private func refresh() {
        do {
            resolution = try TrainingScheduleStore.sync(schedule, in: modelContext)
        } catch {
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
        guard let programID, let program = programs.first(where: { $0.id == programID }) else {
            return
        }
        do {
            WorkoutInterfaceOrientationPolicy.shared.setGuidedWorkoutActive(true)
            startedSession = try TrainingPlanStore.startSession(
                program: program,
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

struct TrainingScheduleEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var programs: [TrainingProgram]

    let schedule: TrainingSchedule?
    @State private var name: String
    @State private var anchor: Date
    @State private var slots: [TrainingScheduleSlotValue]
    @State private var errorMessage: String?

    init(schedule: TrainingSchedule?) {
        self.schedule = schedule
        _name = State(initialValue: schedule?.name ?? "")
        _anchor = State(initialValue: schedule?.anchorDate ?? .now)
        _slots = State(initialValue: schedule?.slots ?? [TrainingScheduleSlotValue.rest()])
        let active = TrainingProgramStatus.active.rawValue
        var descriptor = FetchDescriptor<TrainingProgram>(
            predicate: #Predicate { $0.statusRaw == active },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        _programs = Query(descriptor)
    }

    var body: some View {
        Form {
            Section("计划") {
                TextField("计划名称", text: $name)
                DatePicker("开始日", selection: $anchor, displayedComponents: .date)
            }
            Section("每一天") {
                ForEach(slots.indices, id: \.self) { index in
                    dayRow(index)
                }
                Button("加一天") {
                    guard slots.count < 14 else { return }
                    slots.append(.rest())
                }
                .disabled(slots.count >= 14)
            }
            if programs.isEmpty {
                Section {
                    Text("先在训练页建一堂课程，再把它排进某一天。")
                }
            }
        }
        .navigationTitle(schedule == nil ? "新建训练计划" : "编辑训练计划")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(!canSave)
            }
        }
        .alert(
            "无法保存训练计划",
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

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && slots.contains { $0.program != nil }
    }

    private func dayRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("第 \(index + 1) 天")
                Spacer()
                if slots.count > 1 {
                    Button("去掉") { slots.remove(at: index) }
                        .font(.subheadline)
                }
            }
            Picker("这一天", selection: kindBinding(index)) {
                Text("休息").tag("rest")
                Text("课程").tag("course")
            }
            .pickerStyle(.segmented)
            if slots[index].program != nil {
                Picker("课程", selection: courseBinding(index)) {
                    Text("选择课程").tag(UUID?.none)
                    ForEach(programs) { program in
                        Text(program.name).tag(Optional(program.id))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("第 \(index + 1) 天")
    }

    private func kindBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { slots[index].program == nil ? "rest" : "course" },
            set: { kind in
                if kind == "rest" {
                    slots[index] = .rest()
                } else if slots[index].program == nil, let id = programs.first?.id {
                    slots[index] = .course(id)
                }
            }
        )
    }

    private func courseBinding(_ index: Int) -> Binding<UUID?> {
        Binding(
            get: { slots[index].programID },
            set: { id in
                if let id {
                    slots[index] = .course(id)
                }
            }
        )
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let usable = slots.map { slot -> TrainingScheduleSlotValue in
            guard let programID = slot.program, programs.contains(where: { $0.id == programID }) else {
                return .rest()
            }
            return .course(programID)
        }
        guard usable.contains(where: { $0.program != nil }) else {
            errorMessage = "至少有一天要排一堂课程。"
            return
        }
        do {
            if let schedule {
                schedule.name = trimmed
                schedule.anchorDate = anchor
                schedule.slots = usable
                schedule.updatedAt = .now
                try TrainingScheduleStore.save(schedule, in: modelContext)
            } else {
                let created = TrainingSchedule(
                    name: trimmed,
                    anchorDate: anchor,
                    slots: usable
                )
                try TrainingScheduleStore.save(created, in: modelContext)
            }
            dismiss()
        } catch {
            errorMessage = AppErrorMessage.message(for: error, operation: .general)
        }
    }
}
