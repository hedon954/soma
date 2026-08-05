import SwiftData
import SwiftUI

struct TrainingPrescriptionDraft: Identifiable {
    var id: UUID
    var exerciseID: UUID
    var sets: String
    var reps: String
    var weight: String
    var rest: String
    var firstSetIsWarmup: Bool

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        sets: String = "",
        reps: String = "",
        weight: String = "",
        rest: String = "",
        firstSetIsWarmup: Bool = false
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
        self.reps = reps
        self.weight = weight
        self.rest = rest
        self.firstSetIsWarmup = firstSetIsWarmup
    }

    init(_ prescription: TemplateExercisePrescription) {
        self.init(
            exerciseID: prescription.exerciseID,
            sets: prescription.targetSets.map(String.init) ?? "",
            reps: prescription.targetReps.map(String.init) ?? "",
            weight: prescription.targetWeightKG.map { $0.formatted() } ?? "",
            rest: prescription.targetRestSeconds.map(String.init) ?? "",
            firstSetIsWarmup: prescription.firstSetIsWarmup
        )
    }

    func prescription(
        order: Int,
        names: [UUID: String]
    ) -> TemplateExercisePrescription {
        TemplateExercisePrescription(
            exerciseID: exerciseID,
            exerciseName: names[exerciseID] ?? "已删除动作",
            order: order,
            targetSets: Int(sets),
            targetReps: Int(reps),
            targetWeightKG: Double(weight),
            targetRestSeconds: Int(rest),
            firstSetIsWarmup: firstSetIsWarmup
        )
    }
}

struct TrainingProgramCreationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let definitions: [ExerciseDefinition]
    @State private var name = ""
    @State private var goal = ""
    @State private var scheduleHint = ""
    @State private var rows: [TrainingPrescriptionDraft] = []
    @State private var errorMessage: String?
    @State private var editMode = EditMode.inactive
    @State private var detailsExpanded = false

    private var activeDefinitions: [ExerciseDefinition] {
        definitions.filter { !$0.isArchived }
    }

    var body: some View {
        Form {
            // PRD 020：创建时只要求计划名称；目标与安排提示折叠为可选区。
            Section("计划") {
                TextField("计划名称", text: $name)
                DisclosureGroup("更多（可选）", isExpanded: $detailsExpanded) {
                    TextField("训练目标（可选）", text: $goal, axis: .vertical)
                        .lineLimit(2 ... 4)
                    TextField("安排提示（可选）", text: $scheduleHint)
                }
            }

            TrainingPrescriptionRowsSection(
                rows: $rows,
                definitions: activeDefinitions
            )

            if activeDefinitions.isEmpty {
                Section {
                    ContentUnavailableView(
                        "动作库为空",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("先在教练中记录一次训练，动作形成后即可在这里组合计划。")
                    )
                }
            }
        }
        .navigationTitle("新建训练计划")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建", action: save)
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty || rows.isEmpty
                    )
            }
        }
        .planSaveErrorAlert(message: $errorMessage)
    }

    private func save() {
        let normalizedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        do {
            _ = try TrainingPlanStore.createProgram(
                name: normalizedName,
                goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
                templateName: normalizedName,
                scheduleHint: scheduleHint.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                prescriptions: makePrescriptions(
                    rows: rows,
                    definitions: activeDefinitions
                ),
                source: "gui",
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TrainingTemplateEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let program: TrainingProgram
    let currentVersion: WorkoutTemplateVersion?
    let definitions: [ExerciseDefinition]

    @State private var name: String
    @State private var scheduleHint: String
    @State private var rows: [TrainingPrescriptionDraft]
    @State private var errorMessage: String?
    @State private var editMode = EditMode.inactive

    init(
        program: TrainingProgram,
        currentVersion: WorkoutTemplateVersion?,
        initialPrescriptions: [TemplateExercisePrescription],
        definitions: [ExerciseDefinition]
    ) {
        self.program = program
        self.currentVersion = currentVersion
        self.definitions = definitions
        _name = State(initialValue: currentVersion?.name ?? program.name)
        _scheduleHint = State(initialValue: currentVersion?.scheduleHint ?? "")
        _rows = State(initialValue: initialPrescriptions.map(
            TrainingPrescriptionDraft.init
        ))
    }

    private var activeDefinitions: [ExerciseDefinition] {
        definitions.filter { !$0.isArchived }
    }

    var body: some View {
        Form {
            Section("模板") {
                TextField("模板名称", text: $name)
                TextField("安排提示", text: $scheduleHint)
            }

            TrainingPrescriptionRowsSection(
                rows: $rows,
                definitions: activeDefinitions
            )
        }
        .navigationTitle("新建模板版本")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty || rows.isEmpty
                    )
            }
        }
        .planSaveErrorAlert(message: $errorMessage)
    }

    private func save() {
        do {
            _ = try TrainingPlanStore.createNextVersion(
                for: program,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                scheduleHint: scheduleHint.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                prescriptions: makePrescriptions(
                    rows: rows,
                    definitions: activeDefinitions
                ),
                source: "gui",
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TrainingPrescriptionRowsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode
    @Binding var rows: [TrainingPrescriptionDraft]
    let definitions: [ExerciseDefinition]

    var body: some View {
        Section("动作顺序") {
            if rows.isEmpty {
                Text("选择动作后，可拖动调整顺序；处方按需展开编辑。")
                    .foregroundStyle(.secondary)
            }

            ForEach(rows) { row in
                let exercise = exercise(for: row.exerciseID)
                let recent = ExerciseRecentPrescriptionResolver.latest(
                    exerciseID: row.exerciseID,
                    in: modelContext
                )
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        NavigationLink {
                            TrainingPrescriptionEditorView(
                                initialDraft: row,
                                exercise: exercise,
                                definitions: definitions,
                                recent: recent
                            ) { updated in
                                guard let index = rows.firstIndex(where: {
                                    $0.id == updated.id
                                }) else { return }
                                rows[index] = updated
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ExerciseArtworkView(
                                    reference: exercise?.preferredActionIllustration
                                        ?? BundledExerciseCatalog.fallbackActionIllustration
                                )
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14))

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(exercise?.canonicalName ?? "已归档动作")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(row.prescriptionSummary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("展开编辑组数、次数、重量和间歇")

                        Menu {
                            Button("删除动作", systemImage: "trash", role: .destructive) {
                                rows.removeAll { $0.id == row.id }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                        }
                        .accessibilityLabel("管理\(exercise?.canonicalName ?? "动作")")
                    }

                    if let recent, !recent.summary.isEmpty {
                        Button {
                            apply(recent, to: row.id)
                        } label: {
                            Label(
                                "使用上次：\(recent.summary)",
                                systemImage: "clock.arrow.circlepath"
                            )
                            .font(.subheadline)
                            .lineLimit(2)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityHint("只应用最近训练中明确记录的数值")
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete { rows.remove(atOffsets: $0) }
            .onMove { rows.move(fromOffsets: $0, toOffset: $1) }

            if rows.count > 1 {
                Button {
                    withAnimation {
                        editMode?.wrappedValue = editMode?.wrappedValue == .active
                            ? .inactive
                            : .active
                    }
                } label: {
                    Label(
                        editMode?.wrappedValue == .active ? "完成排序" : "调整顺序",
                        systemImage: "arrow.up.arrow.down"
                    )
                }
            }

            NavigationLink {
                TrainingExercisePickerView(
                    definitions: definitions,
                    allowsMultipleSelection: true
                ) { exercises in
                    rows.append(contentsOf: exercises.map {
                        TrainingPrescriptionDraft(exerciseID: $0.id)
                    })
                }
            } label: {
                Label("选择动作", systemImage: "plus.circle.fill")
            }
            .disabled(definitions.isEmpty)
        }
    }

    private func exercise(for id: UUID) -> ExerciseDefinition? {
        definitions.first { $0.id == id }
    }

    private func apply(
        _ recent: RecentExercisePrescription,
        to rowID: UUID
    ) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else {
            return
        }
        rows[index].apply(recent)
    }
}

private struct TrainingExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let definitions: [ExerciseDefinition]
    let allowsMultipleSelection: Bool
    let onSelect: ([ExerciseDefinition]) -> Void
    @State private var searchText = ""
    @State private var selectedIDs: Set<UUID> = []

    private var filteredDefinitions: [ExerciseDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return definitions }
        return definitions.filter {
            $0.canonicalName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(filteredDefinitions) { exercise in
            Button {
                select(exercise)
            } label: {
                HStack(spacing: 12) {
                    ExerciseArtworkView(
                        reference: exercise.preferredActionIllustration
                    )
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    Text(exercise.canonicalName)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if allowsMultipleSelection {
                        Image(systemName: selectedIDs.contains(exercise.id)
                            ? "checkmark.circle.fill"
                            : "circle")
                            .foregroundStyle(
                                selectedIDs.contains(exercise.id)
                                    ? Color.accentColor
                                    : Color.secondary
                            )
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .overlay {
            if filteredDefinitions.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("选择动作")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索动作库")
        .safeAreaInset(edge: .bottom) {
            if allowsMultipleSelection {
                Button {
                    let selected = definitions.filter {
                        selectedIDs.contains($0.id)
                    }
                    onSelect(selected)
                    dismiss()
                } label: {
                    Text(selectedIDs.isEmpty
                        ? "请选择动作"
                        : "添加 \(selectedIDs.count) 个动作")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedIDs.isEmpty)
                .padding()
                .background(.bar)
            }
        }
    }

    private func select(_ exercise: ExerciseDefinition) {
        if allowsMultipleSelection {
            if selectedIDs.contains(exercise.id) {
                selectedIDs.remove(exercise.id)
            } else {
                selectedIDs.insert(exercise.id)
            }
        } else {
            onSelect([exercise])
            dismiss()
        }
    }
}

private struct TrainingPrescriptionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: ExerciseDefinition?
    let definitions: [ExerciseDefinition]
    let recent: RecentExercisePrescription?
    let onSave: (TrainingPrescriptionDraft) -> Void
    @State private var draft: TrainingPrescriptionDraft

    init(
        initialDraft: TrainingPrescriptionDraft,
        exercise: ExerciseDefinition?,
        definitions: [ExerciseDefinition],
        recent: RecentExercisePrescription?,
        onSave: @escaping (TrainingPrescriptionDraft) -> Void
    ) {
        self.exercise = exercise
        self.definitions = definitions
        self.recent = recent
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
        _moreExpanded = State(initialValue: !initialDraft.weight.isEmpty
            || !initialDraft.rest.isEmpty
            || initialDraft.firstSetIsWarmup)
    }

    @State private var moreExpanded: Bool

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ExerciseArtworkView(
                        reference: exercise?.preferredActionIllustration
                            ?? BundledExerciseCatalog.fallbackActionIllustration
                    )
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text(exercise?.canonicalName ?? "已归档动作")
                        .font(.title3.bold())
                }
            }

            // PRD 020：处方默认只露组数与次数；重量、间歇与热身进折叠区。
            Section("本次处方") {
                Grid(horizontalSpacing: 12, verticalSpacing: 14) {
                    GridRow {
                        metric("组数", text: $draft.sets, keyboard: .numberPad)
                        metric("次数", text: $draft.reps, keyboard: .numberPad)
                    }
                }
                DisclosureGroup("更多处方", isExpanded: $moreExpanded) {
                    Grid(horizontalSpacing: 12, verticalSpacing: 14) {
                        GridRow {
                            metric("重量 kg", text: $draft.weight, keyboard: .decimalPad)
                            metric("间歇秒", text: $draft.rest, keyboard: .numberPad)
                        }
                    }
                    Toggle("第 1 组是热身组", isOn: $draft.firstSetIsWarmup)
                }
            }
        }
        .navigationTitle("编辑动作")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink {
                        TrainingExercisePickerView(
                            definitions: definitions,
                            allowsMultipleSelection: false
                        ) { exercises in
                            guard let replacement = exercises.first else { return }
                            draft.exerciseID = replacement.id
                        }
                    } label: {
                        Label("更换动作", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多操作")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    onSave(draft)
                    dismiss()
                }
            }
        }
    }

    private func metric(
        _ label: String,
        text: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("可选", text: text)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        }
    }
}

private extension TrainingPrescriptionDraft {
    var prescriptionSummary: String {
        var values: [String] = []
        if !weight.isEmpty {
            values.append(Double(weight) == 0 ? "自重" : "\(weight) kg")
        }
        if !reps.isEmpty {
            values.append("\(reps) 次")
        }
        if !sets.isEmpty {
            values.append("\(sets) 组")
        }
        if !rest.isEmpty {
            values.append("间歇 \(rest) 秒")
        }
        if firstSetIsWarmup {
            values.append("首组热身")
        }
        return values.isEmpty ? "按状态完成 · 点击设置" : values.joined(separator: " · ")
    }

    mutating func apply(_ recent: RecentExercisePrescription) {
        if let setCount = recent.setCount {
            sets = String(setCount)
        }
        if let reps = recent.reps {
            self.reps = String(reps)
        }
        if let weightKG = recent.weightKG {
            weight = weightKG.formatted()
        }
        if let restSeconds = recent.restSeconds {
            rest = String(restSeconds)
        }
        if let firstSetIsWarmup = recent.firstSetIsWarmup {
            self.firstSetIsWarmup = firstSetIsWarmup
        }
    }
}

private func makePrescriptions(
    rows: [TrainingPrescriptionDraft],
    definitions: [ExerciseDefinition]
) -> [TemplateExercisePrescription] {
    let names = Dictionary(uniqueKeysWithValues: definitions.map {
        ($0.id, $0.canonicalName)
    })
    return rows.enumerated().map { index, row in
        row.prescription(order: index + 1, names: names)
    }
}

private extension View {
    func planSaveErrorAlert(message: Binding<String?>) -> some View {
        alert(
            "无法保存",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: {
                    if !$0 {
                        message.wrappedValue = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
