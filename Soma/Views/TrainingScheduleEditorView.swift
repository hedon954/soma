import SwiftData
import SwiftUI

struct TrainingScheduleEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var programs: [TrainingProgram] = []
    @State private var plans: [TrainingSchedule] = []
    @State private var definitions: [ExerciseDefinition] = []
    @State private var pickerIndex: Int?
    @State private var showsPicker = false

    let schedule: TrainingSchedule?
    @State private var draftID: UUID
    @State private var name: String
    @State private var anchor: Date
    @State private var slots: [TrainingScheduleSlotValue]
    @State private var previewDays: [TrainingContentDay] = []
    @State private var previewError: String?
    @State private var errorMessage: String?

    init(schedule: TrainingSchedule?, draft: TrainingScheduleEditorDraft? = nil) {
        self.schedule = schedule
        _draftID = State(initialValue: schedule?.id ?? UUID())
        _name = State(initialValue: schedule?.name ?? draft?.name ?? "")
        _anchor = State(initialValue: schedule?.anchorDate ?? draft?.anchor ?? .now)
        _slots = State(initialValue: schedule?.slots ?? draft?.slots ?? [.rest()])
    }

    var body: some View {
        Form {
            Section("计划") {
                TextField("计划名称", text: $name)
                DatePicker("开始日", selection: $anchor, displayedComponents: .date)
            }
            ForEach(slots.indices, id: \.self) { index in
                Section("训练安排 \(index + 1)") {
                    dayContents(index)
                    Button {
                        pickerIndex = index
                        showsPicker = true
                    } label: {
                        Label("添加训练内容", systemImage: "plus")
                    }
                    .accessibilityLabel("给第 \(index + 1) 天添加动作、课程或计划")
                    .accessibilityIdentifier("training-add-content-\(index)")
                    if slots.count > 1 {
                        Button("删除这一天", role: .destructive) { slots.remove(at: index) }
                    }
                }
            }
            Section {
                Button("加一天休息") { slots.append(.rest()) }
                    .disabled(slots.count >= 14)
            } footer: {
                Text("嵌套计划从这里展开一轮，保留休息日；前后内容另起一天。最多 14 天。")
            }
            Section("展开预览") {
                preview
            }
        }
        .sheet(isPresented: $showsPicker) {
            NavigationStack {
                TrainingContentPickerView(
                    definitions: definitions, programs: programs, plans: plans.filter { $0.id != draftID }
                ) { content in
                    if let index = pickerIndex, slots.indices.contains(index) {
                        append(content, at: index)
                    }
                    showsPicker = false
                }
            }
        }
        .navigationTitle(schedule == nil ? "新建训练计划" : "编辑训练计划")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadSources(); refreshPreview() }
        .onChange(of: slots) { _, _ in refreshPreview() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave, object: modelContext)) { _ in
            refreshPreview()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("无法保存训练计划", isPresented: Binding(
            get: { errorMessage != nil }, set: {
                if !$0 {
                    errorMessage = nil
                }
            }
        )) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder private var preview: some View {
        ForEach(Array(previewDays.enumerated()), id: \.offset) { index, day in
            Text("第 \(index + 1) 天 · \(day.title)")
        }
        if let previewError {
            Text(previewError).foregroundStyle(AppTheme.accent)
        }
    }

    private func loadSources() {
        do {
            programs = try modelContext.fetch(FetchDescriptor<TrainingProgram>())
            plans = try modelContext.fetch(FetchDescriptor<TrainingSchedule>())
            definitions = try modelContext.fetch(FetchDescriptor<ExerciseDefinition>(
                predicate: #Predicate { $0.archivedAt == nil && $0.mergedIntoID == nil },
                sortBy: [SortDescriptor(\.canonicalName)]
            ))
        } catch { errorMessage = AppErrorMessage.message(for: error, operation: .load) }
    }

    private func refreshPreview() {
        do {
            previewDays = try TrainingContentCompiler.days(scheduleID: draftID, slots: slots, in: modelContext)
            previewError = nil
        } catch {
            previewDays = []
            previewError = AppErrorMessage.message(for: error, operation: .save)
        }
    }

    @ViewBuilder private func dayContents(_ index: Int) -> some View {
        let contents = contents(at: index)
        if contents.isEmpty {
            Text("休息")
        }
        ForEach(Array(contents.enumerated()), id: \.element.id) { offset, content in
            if let prescription = content.prescription, content.kind == .exercise {
                NavigationLink {
                    TrainingPrescriptionEditorView(
                        initialDraft: TrainingPrescriptionDraft(prescription),
                        exercise: definitions.first { $0.id == prescription.exerciseID },
                        definitions: definitions, recent: nil
                    ) { updated in
                        var values = self.contents(at: index)
                        values[offset].prescription = updated.prescription(
                            order: 1, names: Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0.canonicalName) })
                        )
                        setContents(values, at: index)
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(prescription.exerciseName)
                        Text(TrainingPrescriptionDraft(prescription).prescriptionSummary)
                            .font(.caption)
                    }
                }
            } else if content.kind == .plan, let plan = plans.first(where: { $0.id == content.referenceID }) {
                NavigationLink(plan.name) { TrainingScheduleEditorView(schedule: plan) }
            } else {
                Text(title(content))
            }
        }
        .onDelete { offsets in
            var values = self.contents(at: index)
            values.remove(atOffsets: offsets)
            setContents(values, at: index)
        }
        .onMove { offsets, destination in
            var values = self.contents(at: index)
            values.move(fromOffsets: offsets, toOffset: destination)
            setContents(values, at: index)
        }
    }

    private func title(_ content: TrainingContentSource) -> String {
        switch content.kind {
        case .exercise: content.prescription?.exerciseName ?? "动作已不存在"
        case .course: programs.first { $0.id == content.referenceID }?.name ?? "课程已不存在"
        case .plan: plans.first { $0.id == content.referenceID }?.name ?? "计划已不存在"
        }
    }

    private func contents(at index: Int) -> [TrainingContentSource] {
        if let values = slots[index].contents {
            return values
        }
        if let id = slots[index].programID {
            return [TrainingContentSource(id: id, kind: .course, referenceID: id)]
        }
        return []
    }

    private func append(_ content: TrainingContentSource, at index: Int) {
        setContents(contents(at: index) + [content], at: index)
    }

    private func setContents(_ values: [TrainingContentSource], at index: Int) {
        let id = slots[index].id ?? UUID()
        slots[index] = values.isEmpty ? .rest() : .training(values, id: id)
    }

    private func save() {
        do {
            _ = try TrainingContentCompiler.days(scheduleID: draftID, slots: slots, in: modelContext)
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = schedule ?? TrainingSchedule(id: draftID, name: trimmed, anchorDate: anchor, slots: slots)
            value.name = trimmed
            value.anchorDate = anchor
            value.slots = slots
            value.updatedAt = .now
            try TrainingScheduleStore.save(value, in: modelContext)
            dismiss()
        } catch { errorMessage = AppErrorMessage.message(for: error, operation: .save) }
    }
}
