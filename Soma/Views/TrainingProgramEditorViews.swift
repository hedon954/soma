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

    private var activeDefinitions: [ExerciseDefinition] {
        definitions.filter { !$0.isArchived }
    }

    var body: some View {
        Form {
            Section("计划") {
                TextField("计划名称", text: $name)
                TextField("训练目标（可选）", text: $goal, axis: .vertical)
                    .lineLimit(2 ... 4)
                TextField("安排提示（可选）", text: $scheduleHint)
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
        .environment(\.editMode, .constant(.active))
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
        .environment(\.editMode, .constant(.active))
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
    @Binding var rows: [TrainingPrescriptionDraft]
    let definitions: [ExerciseDefinition]
    @State private var selectedRowID: UUID?
    @State private var showsExercisePicker = false

    var body: some View {
        Section("动作顺序") {
            if rows.isEmpty {
                Text("添加动作后，可拖动调整顺序并填写处方。")
                    .foregroundStyle(.secondary)
            }

            ForEach($rows) { $row in
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        selectedRowID = row.id
                        showsExercisePicker = true
                    } label: {
                        HStack {
                            Text(exerciseName(for: row.exerciseID))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(
                        "选择动作，当前是\(exerciseName(for: row.exerciseID))"
                    )

                    Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            metric("组数", text: $row.sets, keyboard: .numberPad)
                            metric("次数", text: $row.reps, keyboard: .numberPad)
                        }
                        GridRow {
                            metric("重量 kg", text: $row.weight, keyboard: .decimalPad)
                            metric("间歇秒", text: $row.rest, keyboard: .numberPad)
                        }
                    }
                    Toggle("第 1 组是热身组", isOn: $row.firstSetIsWarmup)
                }
                .padding(.vertical, 6)
            }
            .onDelete { rows.remove(atOffsets: $0) }
            .onMove { rows.move(fromOffsets: $0, toOffset: $1) }

            Button {
                selectedRowID = nil
                showsExercisePicker = true
            } label: {
                Label("选择并添加动作", systemImage: "plus.circle")
            }
            .disabled(definitions.isEmpty)
        }
        .sheet(isPresented: $showsExercisePicker) {
            TrainingExercisePickerView(definitions: definitions) { exercise in
                if let selectedRowID,
                   let index = rows.firstIndex(where: { $0.id == selectedRowID })
                {
                    rows[index].exerciseID = exercise.id
                } else {
                    rows.append(TrainingPrescriptionDraft(
                        exerciseID: exercise.id
                    ))
                }
            }
        }
    }

    private func metric(
        _ label: String,
        text: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("可选", text: text)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        }
    }

    private func exerciseName(for id: UUID) -> String {
        definitions.first { $0.id == id }?.canonicalName ?? "已归档动作"
    }
}

private struct TrainingExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let definitions: [ExerciseDefinition]
    let onSelect: (ExerciseDefinition) -> Void
    @State private var searchText = ""

    private var filteredDefinitions: [ExerciseDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return definitions }
        return definitions.filter {
            $0.canonicalName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredDefinitions) { exercise in
                Button {
                    onSelect(exercise)
                    dismiss()
                } label: {
                    Label(
                        exercise.canonicalName,
                        systemImage: "figure.strengthtraining.traditional"
                    )
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
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
