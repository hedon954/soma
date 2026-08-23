import SwiftData
import SwiftUI

enum ChatRecordEditPolicy {
    static func latestEditableAssistantMessageID(
        in messages: [CoachMessage]
    ) -> UUID? {
        guard let last = messages.last, last.isFromCoach else { return nil }
        return last.id
    }
}

/// ADR 0085：一条记录引用一张原位卡，卡片由 `AgentTurnTranscript` 插在产生它的那一步之后。
struct ChatRecordEditorCard: View {
    @Query private var workouts: [WorkoutEntry]
    @Query private var meals: [MealEntry]
    @Query private var bodies: [BodyEntry]
    @Query private var gyms: [GymProfile]

    let reference: AgentRecordReference
    let sourceMessage: CoachMessage?
    let isEditable: Bool

    var body: some View {
        if reference.recordType == ConversationIntent.workout.rawValue,
           let workout = workouts.first(where: {
               $0.businessID == reference.recordID
           })
        {
            InlineWorkoutCard(
                workout: workout,
                sourceMessage: sourceMessage,
                isEditable: isEditable
            )
        } else if reference.recordType == ConversationIntent.meal.rawValue,
                  let meal = meals.first(where: {
                      $0.businessID == reference.recordID
                  })
        {
            InlineMealCards(
                meal: meal,
                sourceMessage: sourceMessage,
                isEditable: isEditable
            )
        } else if reference.recordType == ConversationIntent.body.rawValue,
                  let body = bodies.first(where: {
                      $0.businessID == reference.recordID
                  })
        {
            InlineBodyCard(
                entry: body,
                sourceMessage: sourceMessage,
                isEditable: isEditable
            )
        } else if reference.recordType == ConversationIntent.gym.rawValue,
                  let gym = gyms.first(where: {
                      $0.businessID == reference.recordID
                  })
        {
            InlineGymCard(
                gym: gym,
                sourceMessage: sourceMessage,
                isEditable: isEditable
            )
        }
    }
}

private struct InlineWorkoutCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var definitions: [ExerciseDefinition]
    let workout: WorkoutEntry
    let sourceMessage: CoachMessage?
    let isEditable: Bool
    @State private var exercise: String
    @State private var workoutDraft: WorkoutRecordDraft
    @State private var showsDelete = false

    private var linkedDefinition: ExerciseDefinition? {
        if let exerciseID = workout.exerciseID {
            return definitions.first { $0.id == exerciseID }
        }
        return nil
    }

    init(workout: WorkoutEntry, sourceMessage: CoachMessage?, isEditable: Bool) {
        self.workout = workout
        self.sourceMessage = sourceMessage
        self.isEditable = isEditable
        _exercise = State(initialValue: workout.exercise)
        _workoutDraft = State(
            initialValue: WorkoutRecordDraft(evidence: workout.setEntries)
        )
    }

    var body: some View {
        InlineRecordShell(
            title: exercise.isEmpty ? "训练记录" : exercise,
            titleText: isEditable ? $exercise : nil,
            icon: "dumbbell.fill",
            iconTint: AppTheme.trainingAccent,
            iconSoftTint: AppTheme.trainingSoftTint,
            isEditable: isEditable,
            onSave: save,
            onDelete: { showsDelete = true },
            contentPadding: 10
        ) {
            WorkoutLogicalGroupsEditor(
                draft: $workoutDraft,
                isEditable: isEditable,
                fallbackRestSeconds: workout.restSeconds,
                density: .chatCompact
            )
        }
        .confirmationDialog("删除这条训练记录？", isPresented: $showsDelete) {
            Button("删除记录", role: .destructive, action: deleteRecord)
        }
    }

    private func save() -> Bool {
        let normalized = exercise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, workoutDraft.isValid else { return false }
        let nameKey = ExerciseLibraryStore.canonicalNameKey(normalized)
        if let exerciseID = workout.exerciseID,
           let current = definitions.first(where: { $0.id == exerciseID }),
           current.canonicalNameKey != nameKey
        {
            workout.exerciseID = nil
        }
        workout.exercise = normalized
        let definition = try? ExerciseLibraryStore.linkedExercise(
            for: workout,
            in: modelContext,
            persist: true,
            allowCreate: true
        )
        exercise = definition?.canonicalName ?? normalized
        workout.setEntries = workoutDraft.evidence
        let estimate = WorkoutCalorieCalculator.estimate(
            exercise: workout.exercise,
            intensity: workout.intensity,
            durationMinutes: workout.durationMinutes,
            sets: workout.setCount,
            reps: workout.representativeReps,
            restSeconds: workout.restSeconds,
            weightKG: WorkoutCalorieCalculator.currentReferenceWeight(in: modelContext)
        )
        workout.estimatedCalories = estimate?.calories
        workout.calorieMET = estimate?.met
        workout.calorieDurationMinutes = estimate?.durationMinutes
        workout.calorieDurationEstimated = estimate?.durationWasEstimated ?? false
        sourceMessage?.recordManualCorrection(
            "训练记录 \(workout.id.uuidString) 已修改，动作 \(workout.exercise)，保留 \(workoutDraft.groups.count) 个逻辑组的逐组事实"
        )
        try? modelContext.save()
        return true
    }

    private func deleteRecord() {
        sourceMessage?.recordManualCorrection("训练记录 \(workout.id.uuidString) 已由用户删除")
        modelContext.delete(workout)
        try? modelContext.save()
    }
}

private struct InlineBodyCard: View {
    @Environment(\.modelContext) private var modelContext
    let entry: BodyEntry
    let sourceMessage: CoachMessage?
    let isEditable: Bool
    @State private var weight: String
    @State private var bodyFat: String
    @State private var waist: String
    @State private var notes: String
    @State private var showsDelete = false

    init(entry: BodyEntry, sourceMessage: CoachMessage?, isEditable: Bool) {
        self.entry = entry
        self.sourceMessage = sourceMessage
        self.isEditable = isEditable
        _weight = State(initialValue: entry.weight.map { $0.formatted() } ?? "")
        _bodyFat = State(initialValue: entry.bodyFat.map { $0.formatted() } ?? "")
        _waist = State(initialValue: entry.waist.map { $0.formatted() } ?? "")
        _notes = State(initialValue: entry.notes)
    }

    var body: some View {
        InlineRecordShell(
            title: "身体记录",
            icon: "scalemass",
            iconTint: AppTheme.bodyAccent,
            iconSoftTint: AppTheme.bodySoftTint,
            isEditable: isEditable,
            onSave: save,
            onDelete: { showsDelete = true }
        ) {
            if isEditable {
                HStack(spacing: 6) {
                    compactMetric("kg", text: $weight, decimal: true)
                    compactMetric("%", text: $bodyFat, decimal: true)
                    compactMetric("腰围", text: $waist, decimal: true)
                }
                TextField("备注", text: $notes, axis: .vertical)
                    .font(.caption)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 2)
            } else {
                Text(
                    [
                        entry.weight.map { "\($0.formatted()) kg" },
                        entry.bodyFat.map { "体脂 \($0.formatted())%" }
                    ].compactMap { $0 }.joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("删除这条身体记录？", isPresented: $showsDelete) {
            Button("删除记录", role: .destructive, action: deleteRecord)
        }
    }

    private func save() -> Bool {
        entry.weight = Double(weight)
        entry.bodyFat = Double(bodyFat)
        entry.waist = Double(waist)
        entry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        sourceMessage?.recordManualCorrection(
            "身体记录 \(entry.id.uuidString) 已改为体重\(weight)kg、体脂\(bodyFat)%、腰围\(waist)cm"
        )
        try? modelContext.save()
        return true
    }

    private func deleteRecord() {
        sourceMessage?.recordManualCorrection("身体记录 \(entry.id.uuidString) 已由用户删除")
        modelContext.delete(entry)
        try? modelContext.save()
    }
}

private struct InlineGymCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allGyms: [GymProfile]
    let gym: GymProfile
    let sourceMessage: CoachMessage?
    let isEditable: Bool
    @State private var name: String
    @State private var notes: String
    @State private var isCurrent: Bool
    @State private var showsDelete = false

    init(gym: GymProfile, sourceMessage: CoachMessage?, isEditable: Bool) {
        self.gym = gym
        self.sourceMessage = sourceMessage
        self.isEditable = isEditable
        _name = State(initialValue: gym.name)
        _notes = State(initialValue: gym.notes)
        _isCurrent = State(initialValue: gym.isCurrent)
    }

    var body: some View {
        InlineRecordShell(
            title: name.isEmpty ? "健身房记录" : name,
            titleText: isEditable ? $name : nil,
            icon: "building.2",
            isEditable: isEditable,
            onSave: save,
            onDelete: { showsDelete = true }
        ) {
            if isEditable {
                TextField("说明", text: $notes, axis: .vertical)
                    .font(.caption)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 2)
                Toggle("当前健身房", isOn: $isCurrent)
                    .appToggleStyle()
                    .font(.caption)
                    .disabled(gym.isCurrent)
            } else if !gym.notes.isEmpty {
                Text(gym.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("删除这个健身房？", isPresented: $showsDelete) {
            Button("删除健身房", role: .destructive, action: deleteRecord)
        }
    }

    private func save() -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        gym.name = normalized
        gym.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCurrent {
            GymSelection.activate(gym, among: allGyms)
        }
        sourceMessage?.recordManualCorrection(
            "健身房记录 \(gym.id.uuidString) 已改为 \(normalized)，当前状态 \(gym.isCurrent ? "已选择" : "未选择")"
        )
        try? modelContext.save()
        return true
    }

    private func deleteRecord() {
        sourceMessage?.recordManualCorrection("健身房记录 \(gym.id.uuidString) 已由用户删除")
        StructuredDataStore.deleteGym(
            gym,
            gyms: allGyms,
            equipment: (try? modelContext.fetch(FetchDescriptor<GymEquipment>())) ?? [],
            media: (try? modelContext.fetch(FetchDescriptor<GymMedia>())) ?? [],
            in: modelContext
        )
    }
}
