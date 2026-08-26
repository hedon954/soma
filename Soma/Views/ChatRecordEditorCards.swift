import SwiftData
import SwiftUI

private struct WorkoutAutosaveValue: Equatable {
    var exercise: String
    var draft: WorkoutRecordDraft
}

private struct BodyAutosaveValue: Equatable {
    var weight: String
    var bodyFat: String
    var waist: String
    var notes: String
}

private struct GymAutosaveValue: Equatable {
    var name: String
    var notes: String
    var isCurrent: Bool
}

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
    let reference: AgentRecordReference
    let sourceMessage: CoachMessage?
    let isEditable: Bool

    var body: some View {
        switch reference.recordType {
        case ConversationIntent.workout.rawValue:
            WorkoutRecordCardLookup(
                recordID: reference.recordID,
                sourceMessage: sourceMessage,
                isEditable: isEditable
            )
        case ConversationIntent.meal.rawValue:
            MealRecordCardLookup(
                recordID: reference.recordID,
                sourceMessage: sourceMessage,
                isEditable: isEditable
            )
        case ConversationIntent.body.rawValue:
            BodyRecordCardLookup(
                recordID: reference.recordID,
                sourceMessage: sourceMessage,
                isEditable: isEditable
            )
        case ConversationIntent.gym.rawValue:
            GymRecordCardLookup(
                recordID: reference.recordID,
                sourceMessage: sourceMessage,
                isEditable: isEditable
            )
        default:
            EmptyView()
        }
    }
}

private struct WorkoutRecordCardLookup: View {
    @Environment(\.modelContext) private var modelContext
    let sourceMessage: CoachMessage?
    let isEditable: Bool
    private let recordID: Int64
    @State private var record: WorkoutEntry?

    init(recordID: Int64, sourceMessage: CoachMessage?, isEditable: Bool) {
        self.recordID = recordID
        self.sourceMessage = sourceMessage
        self.isEditable = isEditable
    }

    var body: some View {
        if let record {
            InlineWorkoutCard(
                workout: record,
                sourceMessage: sourceMessage,
                isEditable: isEditable
            )
        }
        Color.clear.frame(height: record == nil ? 1 : 0)
            .task(id: recordID) { await loadRecord() }
    }

    private func loadRecord() async {
        guard record == nil else { return }
        await Task.yield()
        var descriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.businessID == recordID }
        )
        descriptor.fetchLimit = 1
        guard !Task.isCancelled,
              let loaded = try? modelContext.fetch(descriptor).first
        else { return }
        record = loaded
    }
}

private struct MealRecordCardLookup: View {
    @Environment(\.modelContext) private var modelContext
    let sourceMessage: CoachMessage?
    let isEditable: Bool
    private let recordID: Int64
    @State private var record: MealEntry?

    init(recordID: Int64, sourceMessage: CoachMessage?, isEditable: Bool) {
        self.recordID = recordID
        self.sourceMessage = sourceMessage
        self.isEditable = isEditable
    }

    var body: some View {
        if let record {
            InlineMealCards(
                meal: record,
                sourceMessage: sourceMessage,
                isEditable: isEditable
            )
        }
        Color.clear.frame(height: record == nil ? 1 : 0)
            .task(id: recordID) { await loadRecord() }
    }

    private func loadRecord() async {
        guard record == nil else { return }
        await Task.yield()
        var descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { $0.businessID == recordID }
        )
        descriptor.fetchLimit = 1
        guard !Task.isCancelled,
              let loaded = try? modelContext.fetch(descriptor).first
        else { return }
        record = loaded
    }
}

private struct BodyRecordCardLookup: View {
    @Environment(\.modelContext) private var modelContext
    let sourceMessage: CoachMessage?
    let isEditable: Bool
    private let recordID: Int64
    @State private var record: BodyEntry?

    init(recordID: Int64, sourceMessage: CoachMessage?, isEditable: Bool) {
        self.recordID = recordID
        self.sourceMessage = sourceMessage
        self.isEditable = isEditable
    }

    var body: some View {
        if let record {
            InlineBodyCard(
                entry: record,
                sourceMessage: sourceMessage,
                isEditable: isEditable
            )
        }
        Color.clear.frame(height: record == nil ? 1 : 0)
            .task(id: recordID) { await loadRecord() }
    }

    private func loadRecord() async {
        guard record == nil else { return }
        await Task.yield()
        var descriptor = FetchDescriptor<BodyEntry>(
            predicate: #Predicate { $0.businessID == recordID }
        )
        descriptor.fetchLimit = 1
        guard !Task.isCancelled,
              let loaded = try? modelContext.fetch(descriptor).first
        else { return }
        record = loaded
    }
}

private struct GymRecordCardLookup: View {
    @Environment(\.modelContext) private var modelContext
    let sourceMessage: CoachMessage?
    let isEditable: Bool
    private let recordID: Int64
    @State private var record: GymProfile?

    init(recordID: Int64, sourceMessage: CoachMessage?, isEditable: Bool) {
        self.recordID = recordID
        self.sourceMessage = sourceMessage
        self.isEditable = isEditable
    }

    var body: some View {
        if let record {
            InlineGymCard(
                gym: record,
                sourceMessage: sourceMessage,
                isEditable: isEditable
            )
        }
        Color.clear.frame(height: record == nil ? 1 : 0)
            .task(id: recordID) { await loadRecord() }
    }

    private func loadRecord() async {
        guard record == nil else { return }
        await Task.yield()
        var descriptor = FetchDescriptor<GymProfile>(
            predicate: #Predicate { $0.businessID == recordID }
        )
        descriptor.fetchLimit = 1
        guard !Task.isCancelled,
              let loaded = try? modelContext.fetch(descriptor).first
        else { return }
        record = loaded
    }
}

private struct InlineWorkoutCard: View {
    @Environment(\.modelContext) private var modelContext
    let workout: WorkoutEntry
    let sourceMessage: CoachMessage?
    let isEditable: Bool
    @State private var exercise: String
    @State private var workoutDraft: WorkoutRecordDraft
    @State private var showsDelete = false
    @State private var saveState: InlineRecordSaveState = .idle

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
            saveState: $saveState,
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
        .inlineRecordAutosave(
            value: WorkoutAutosaveValue(exercise: exercise, draft: workoutDraft),
            isEnabled: isEditable,
            state: $saveState,
            save: save
        )
    }

    private func save() -> Bool {
        let normalized = exercise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, workoutDraft.isValid else { return false }
        let nameKey = ExerciseLibraryStore.canonicalNameKey(normalized)
        if let exerciseID = workout.exerciseID {
            var descriptor = FetchDescriptor<ExerciseDefinition>(
                predicate: #Predicate { $0.id == exerciseID }
            )
            descriptor.fetchLimit = 1
            if let current = try? modelContext.fetch(descriptor).first,
               current.canonicalNameKey != nameKey
            {
                workout.exerciseID = nil
            }
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
            weightKG: WorkoutCalorieCalculator.currentRecordedWeight(in: modelContext)
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
    @State private var saveState: InlineRecordSaveState = .idle

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
            saveState: $saveState,
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
        .inlineRecordAutosave(
            value: BodyAutosaveValue(
                weight: weight,
                bodyFat: bodyFat,
                waist: waist,
                notes: notes
            ),
            isEnabled: isEditable,
            state: $saveState,
            save: save
        )
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
    let gym: GymProfile
    let sourceMessage: CoachMessage?
    let isEditable: Bool
    @State private var name: String
    @State private var notes: String
    @State private var isCurrent: Bool
    @State private var showsDelete = false
    @State private var saveState: InlineRecordSaveState = .idle

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
            saveState: $saveState,
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
        .inlineRecordAutosave(
            value: GymAutosaveValue(name: name, notes: notes, isCurrent: isCurrent),
            isEnabled: isEditable,
            state: $saveState,
            save: save
        )
    }

    private func save() -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        gym.name = normalized
        gym.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCurrent {
            StructuredDataStore.activateGym(gym, in: modelContext)
        }
        sourceMessage?.recordManualCorrection(
            "健身房记录 \(gym.id.uuidString) 已改为 \(normalized)，当前状态 \(gym.isCurrent ? "已选择" : "未选择")"
        )
        try? modelContext.save()
        return true
    }

    private func deleteRecord() {
        sourceMessage?.recordManualCorrection("健身房记录 \(gym.id.uuidString) 已由用户删除")
        StructuredDataStore.deleteGym(gym, in: modelContext)
    }
}
