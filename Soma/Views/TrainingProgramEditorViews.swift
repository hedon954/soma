import SwiftData
import SwiftUI

struct TrainingPrescriptionDraft: Identifiable {
    var id: UUID
    var exerciseID: UUID
    var laterality: ExerciseLaterality
    var restBetweenSetsSeconds: String
    var restBetweenSidesSeconds: String
    var plannedSets: [TrainingSetPrescriptionDraft]

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        laterality: ExerciseLaterality = .none,
        restBetweenSetsSeconds: String = "",
        restBetweenSidesSeconds: String = "",
        plannedSets: [TrainingSetPrescriptionDraft] = [
            TrainingSetPrescriptionDraft(order: 1)
        ]
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.laterality = laterality
        self.restBetweenSetsSeconds = restBetweenSetsSeconds
        self.restBetweenSidesSeconds = restBetweenSidesSeconds
        self.plannedSets = plannedSets
    }

    init(_ prescription: TemplateExercisePrescription) {
        self.init(
            exerciseID: prescription.exerciseID,
            laterality: prescription.laterality,
            restBetweenSetsSeconds: prescription.targetRestSeconds.map(String.init) ?? "",
            restBetweenSidesSeconds: prescription.restBetweenSidesSeconds.map(String.init) ?? "",
            plannedSets: prescription.plannedSets.isEmpty
                ? [TrainingSetPrescriptionDraft(order: 1)]
                : prescription.plannedSets
                .sorted { $0.order < $1.order }
                .map(TrainingSetPrescriptionDraft.init)
        )
    }

    func prescription(
        order: Int,
        names: [UUID: String]
    ) -> TemplateExercisePrescription {
        let sets = plannedSets.enumerated().map { index, draft in
            draft.prescription(
                order: index + 1,
                laterality: laterality
            )
        }
        let first = sets.first
        return TemplateExercisePrescription(
            exerciseID: exerciseID,
            exerciseName: names[exerciseID] ?? "已删除动作",
            order: order,
            targetSets: sets.count,
            targetReps: first?.targetKind == .repetitions
                ? first?.targetReps
                : nil,
            targetWeightKG: first?.targetWeightKG,
            targetRestSeconds: Int(restBetweenSetsSeconds),
            restBetweenSidesSeconds: laterality == .both
                ? Int(restBetweenSidesSeconds)
                : nil,
            firstSetIsWarmup: first?.kind == .warmup,
            laterality: laterality,
            plannedSets: sets
        )
    }
}

struct TrainingSetPrescriptionDraft: Identifiable, Equatable {
    var id: UUID
    var order: Int
    var kind: WorkoutSetKind
    var targetKind: WorkoutTargetKind
    var reps: String
    var durationSeconds: String
    var weight: String
    var leftWeight: String
    var rightWeight: String
    var restBetweenSidesSeconds: String
    var restAfterSetSeconds: String
    var notes: String

    init(
        id: UUID = UUID(),
        order: Int,
        kind: WorkoutSetKind = .working,
        targetKind: WorkoutTargetKind = .repetitions,
        reps: String = "",
        durationSeconds: String = "",
        weight: String = "",
        leftWeight: String = "",
        rightWeight: String = "",
        restBetweenSidesSeconds: String = "",
        restAfterSetSeconds: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.order = order
        self.kind = kind
        self.targetKind = targetKind
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.weight = weight
        self.leftWeight = leftWeight
        self.rightWeight = rightWeight
        self.restBetweenSidesSeconds = restBetweenSidesSeconds
        self.restAfterSetSeconds = restAfterSetSeconds
        self.notes = notes
    }

    init(_ value: TemplateSetPrescriptionValue) {
        self.init(
            id: value.id,
            order: value.order,
            kind: value.kind,
            targetKind: value.targetKind,
            reps: value.targetReps.map(String.init) ?? "",
            durationSeconds: value.targetDurationSeconds.map(String.init) ?? "",
            weight: value.targetWeightKG.map { $0.formatted() } ?? "",
            leftWeight: value.leftWeightKG.map { $0.formatted() } ?? "",
            rightWeight: value.rightWeightKG.map { $0.formatted() } ?? "",
            restBetweenSidesSeconds: value.restBetweenSidesSeconds.map(String.init) ?? "",
            restAfterSetSeconds: value.restAfterSetSeconds.map(String.init) ?? "",
            notes: value.notes
        )
    }

    func prescription(
        order: Int,
        laterality: ExerciseLaterality
    ) -> TemplateSetPrescriptionValue {
        let weights: (
            shared: Double?,
            left: Double?,
            right: Double?
        ) = switch laterality {
        case .none:
            (Double(weight), nil, nil)
        case .both:
            (nil, Double(leftWeight), Double(rightWeight))
        case .left:
            (nil, Double(leftWeight), nil)
        case .right:
            (nil, nil, Double(rightWeight))
        }
        return TemplateSetPrescriptionValue(
            id: id,
            order: order,
            kind: kind,
            targetKind: targetKind,
            targetReps: targetKind == .repetitions ? Int(reps) : nil,
            targetDurationSeconds: targetKind == .duration
                ? Int(durationSeconds)
                : nil,
            targetWeightKG: weights.shared,
            leftWeightKG: weights.left,
            rightWeightKG: weights.right,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct TrainingProgramCreationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let definitions: [ExerciseDefinition]
    @State private var name = ""
    @State private var overview = ""
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
            Section("计划") {
                TextField("计划名称", text: $name)
                TextField(
                    "计划概览（可选）",
                    text: $overview,
                    axis: .vertical
                )
                .lineLimit(3 ... 7)
                DisclosureGroup("更多（可选）", isExpanded: $detailsExpanded) {
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
                goal: overview.trimmingCharacters(in: .whitespacesAndNewlines),
                scheduleHint: scheduleHint.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                prescriptions: makePrescriptions(
                    rows: rows,
                    definitions: activeDefinitions
                ),
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
    let definitions: [ExerciseDefinition]

    @State private var name: String
    @State private var scheduleHint: String
    @State private var rows: [TrainingPrescriptionDraft]
    @State private var errorMessage: String?
    @State private var editMode = EditMode.inactive

    init(
        program: TrainingProgram,
        initialPrescriptions: [TemplateExercisePrescription],
        definitions: [ExerciseDefinition]
    ) {
        self.program = program
        self.definitions = definitions
        _name = State(initialValue: program.name)
        _scheduleHint = State(initialValue: program.scheduleHint)
        _rows = State(initialValue: initialPrescriptions.map(
            TrainingPrescriptionDraft.init
        ))
    }

    private var activeDefinitions: [ExerciseDefinition] {
        definitions.filter { !$0.isArchived }
    }

    var body: some View {
        Form {
            Section("计划") {
                TextField("计划名称", text: $name)
                TextField("安排提示", text: $scheduleHint)
            }

            TrainingPrescriptionRowsSection(
                rows: $rows,
                definitions: activeDefinitions
            )
        }
        .navigationTitle("编辑训练计划")
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
            try TrainingPlanStore.updateProgram(
                for: program,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                scheduleHint: scheduleHint.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                prescriptions: makePrescriptions(
                    rows: rows,
                    definitions: activeDefinitions
                ),
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
        Section {
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
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(row.prescriptionSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Label("编辑参数", systemImage: "pencil")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(AppTheme.trainingAccent)
                                }
                                Spacer(minLength: 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("查看或编辑该动作的处方；相同组已收成一句")

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
                        TrainingPrescriptionDraft(
                            exerciseID: $0.id,
                            laterality: $0.laterality,
                            plannedSets: [
                                TrainingSetPrescriptionDraft(
                                    order: 1,
                                    targetKind: $0.targetKind
                                )
                            ]
                        )
                    })
                }
            } label: {
                Label("选择动作", systemImage: "plus.circle.fill")
            }
            .disabled(definitions.isEmpty)
        } header: {
            Text("动作与参数")
        } footer: {
            Text("点按动作修改组数、次数或时长、重量、侧别与间歇。")
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

struct TrainingExercisePickerView: View {
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
                .appPrimaryButtonStyle()
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

private extension TrainingPrescriptionDraft {
    var prescriptionSummary: String {
        WorkoutPrescriptionFormatter.exerciseSummary(
            prescription(order: 1, names: [:])
        )
    }

    mutating func apply(_ recent: RecentExercisePrescription) {
        let count = max(recent.setCount ?? plannedSets.count, 1)
        let seed = plannedSets.last ?? TrainingSetPrescriptionDraft(order: 1)
        if plannedSets.count < count {
            plannedSets.append(contentsOf: (plannedSets.count ..< count).map { index in
                var copy = seed
                copy.id = UUID()
                copy.order = index + 1
                return copy
            })
        } else if plannedSets.count > count {
            plannedSets.removeLast(plannedSets.count - count)
        }
        for index in plannedSets.indices {
            plannedSets[index].order = index + 1
            if let reps = recent.reps {
                plannedSets[index].targetKind = .repetitions
                plannedSets[index].reps = String(reps)
            }
            if let weightKG = recent.weightKG {
                plannedSets[index].weight = weightKG.formatted()
            }
        }
        if let restSeconds = recent.restSeconds {
            restBetweenSetsSeconds = String(restSeconds)
        }
        if let firstSetIsWarmup = recent.firstSetIsWarmup,
           let firstIndex = plannedSets.indices.first
        {
            plannedSets[firstIndex].kind = firstSetIsWarmup ? .warmup : .working
        }
    }
}

func makePrescriptions(
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
