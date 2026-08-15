import SwiftData
import SwiftUI

enum ChatRecordReferenceResolver {
    static func references(in items: [AgentTurnItem]) -> [AgentRecordReference] {
        var seen = Set<String>()
        var result: [AgentRecordReference] = []
        for item in items {
            guard let output = item.output,
                  let data = output.data(using: .utf8),
                  let toolResult = try? JSONDecoder().decode(
                      AgentToolResult.self,
                      from: data
                  )
            else {
                continue
            }
            for reference in toolResult.recordRefs ?? [] {
                let key = "\(reference.recordType):\(reference.recordID)"
                guard seen.insert(key).inserted else { continue }
                result.append(reference)
            }
        }
        return result
    }
}

enum ChatRecordEditPolicy {
    static func latestEditableAssistantMessageID(
        in messages: [CoachMessage]
    ) -> UUID? {
        guard let last = messages.last, last.isFromCoach else { return nil }
        return last.id
    }
}

struct ChatRecordEditorCards: View {
    @Query private var workouts: [WorkoutEntry]
    @Query private var meals: [MealEntry]
    @Query private var bodies: [BodyEntry]
    @Query private var gyms: [GymProfile]

    let references: [AgentRecordReference]
    let sourceMessage: CoachMessage?
    let isEditable: Bool

    var body: some View {
        ForEach(references, id: \.recordID) { reference in
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
                InlineMealCard(
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
}

private struct InlineRecordShell<Content: View>: View {
    let title: String
    let icon: String
    let isEditable: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label(
                    isEditable ? "可直接修订" : "已锁定",
                    systemImage: isEditable ? "pencil.line" : "lock.fill"
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            content
        }
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(AppTheme.tint.opacity(0.12), lineWidth: 1)
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
    @State private var sets: String
    @State private var reps: String
    @State private var weight: String
    @State private var rest: String
    @State private var showsDelete = false

    init(workout: WorkoutEntry, sourceMessage: CoachMessage?, isEditable: Bool) {
        self.workout = workout
        self.sourceMessage = sourceMessage
        self.isEditable = isEditable
        _exercise = State(initialValue: workout.exercise)
        _sets = State(initialValue: workout.setCount.map(String.init) ?? "")
        _reps = State(initialValue: workout.representativeReps.map(String.init) ?? "")
        _weight = State(initialValue: workout.representativeWeight.map { $0.formatted() } ?? "")
        _rest = State(initialValue: workout.restSeconds.map(String.init) ?? "")
    }

    var body: some View {
        InlineRecordShell(title: "训练记录", icon: "figure.strengthtraining.traditional", isEditable: isEditable) {
            if isEditable {
                TextField("动作", text: $exercise)
                    .font(.body.weight(.medium))
                HStack {
                    compactNumber("组数", text: $sets)
                    compactNumber("次数", text: $reps)
                    compactNumber("重量 kg", text: $weight, decimal: true)
                    compactNumber("间歇 s", text: $rest)
                }
                actionRow(save: save, delete: { showsDelete = true })
            } else {
                Text(workout.exercise).font(.body.weight(.medium))
                Text(workout.setEvidenceSummary ?? "组次与重量未填写")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("删除这条训练记录？", isPresented: $showsDelete) {
            Button("删除记录", role: .destructive, action: deleteRecord)
        }
    }

    private func save() {
        let normalized = exercise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
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
        workout.setEntries = (0 ..< (Int(sets) ?? 0)).map { _ in
            WorkoutSetEvidence(reps: Int(reps), externalWeightKG: Double(weight))
        }
        workout.restSeconds = Int(rest)
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
            "训练记录 \(workout.id.uuidString) 已改为 \(workout.exercise)，\(sets)组，\(reps)次，\(weight)kg，间歇\(rest)秒"
        )
        try? modelContext.save()
    }

    private func deleteRecord() {
        sourceMessage?.recordManualCorrection("训练记录 \(workout.id.uuidString) 已由用户删除")
        modelContext.delete(workout)
        try? modelContext.save()
    }
}

private struct InlineMealCard: View {
    @Environment(\.modelContext) private var modelContext
    let meal: MealEntry
    let sourceMessage: CoachMessage?
    let isEditable: Bool
    @State private var type: MealType
    @State private var title: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var showsDelete = false

    init(meal: MealEntry, sourceMessage: CoachMessage?, isEditable: Bool) {
        self.meal = meal
        self.sourceMessage = sourceMessage
        self.isEditable = isEditable
        _type = State(initialValue: meal.mealType)
        _title = State(initialValue: meal.title)
        _calories = State(initialValue: meal.calories.map(String.init) ?? "")
        _protein = State(initialValue: meal.protein.map { $0.formatted() } ?? "")
        _carbs = State(initialValue: meal.carbs.map { $0.formatted() } ?? "")
        _fat = State(initialValue: meal.fat.map { $0.formatted() } ?? "")
    }

    var body: some View {
        InlineRecordShell(title: "饮食记录", icon: "fork.knife", isEditable: isEditable) {
            if isEditable {
                Picker("餐次", selection: $type) {
                    ForEach(MealType.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("餐食", text: $title)
                HStack {
                    compactNumber("kcal", text: $calories)
                    compactNumber("蛋白 g", text: $protein, decimal: true)
                    compactNumber("碳水 g", text: $carbs, decimal: true)
                    compactNumber("脂肪 g", text: $fat, decimal: true)
                }
                actionRow(save: save, delete: { showsDelete = true })
            } else {
                Text("\(meal.mealType.rawValue) · \(meal.title)").font(.body.weight(.medium))
                Text(meal.calories.map { "\($0) kcal" } ?? "热量未填写")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("删除这条饮食记录？", isPresented: $showsDelete) {
            Button("删除记录", role: .destructive, action: deleteRecord)
        }
    }

    private func save() {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        meal.mealType = type
        meal.title = normalized
        meal.calories = Int(calories)
        meal.protein = Double(protein)
        meal.carbs = Double(carbs)
        meal.fat = Double(fat)
        meal.nutritionSource = .userEdited
        sourceMessage?.recordManualCorrection(
            "饮食记录 \(meal.id.uuidString) 已改为 \(type.rawValue) \(normalized)，\(calories)kcal，蛋白\(protein)g，碳水\(carbs)g，脂肪\(fat)g"
        )
        try? modelContext.save()
    }

    private func deleteRecord() {
        sourceMessage?.recordManualCorrection("饮食记录 \(meal.id.uuidString) 已由用户删除")
        modelContext.delete(meal)
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
        InlineRecordShell(title: "身体记录", icon: "scalemass", isEditable: isEditable) {
            if isEditable {
                HStack {
                    compactNumber("体重 kg", text: $weight, decimal: true)
                    compactNumber("体脂 %", text: $bodyFat, decimal: true)
                    compactNumber("腰围 cm", text: $waist, decimal: true)
                }
                TextField("备注", text: $notes, axis: .vertical).lineLimit(1 ... 3)
                actionRow(save: save, delete: { showsDelete = true })
            } else {
                Text([entry.weight.map { "\($0.formatted()) kg" }, entry.bodyFat.map { "体脂 \($0.formatted())%" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.body.weight(.medium))
            }
        }
        .confirmationDialog("删除这条身体记录？", isPresented: $showsDelete) {
            Button("删除记录", role: .destructive, action: deleteRecord)
        }
    }

    private func save() {
        entry.weight = Double(weight)
        entry.bodyFat = Double(bodyFat)
        entry.waist = Double(waist)
        entry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        sourceMessage?.recordManualCorrection(
            "身体记录 \(entry.id.uuidString) 已改为体重\(weight)kg、体脂\(bodyFat)%、腰围\(waist)cm"
        )
        try? modelContext.save()
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
        InlineRecordShell(title: "健身房记录", icon: "building.2", isEditable: isEditable) {
            if isEditable {
                TextField("名称", text: $name)
                TextField("说明", text: $notes, axis: .vertical).lineLimit(1 ... 3)
                Toggle("设为当前健身房", isOn: $isCurrent)
                    .disabled(gym.isCurrent)
                actionRow(save: save, delete: { showsDelete = true })
            } else {
                Text(gym.name).font(.body.weight(.medium))
                if !gym.notes.isEmpty {
                    Text(gym.notes).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("删除这个健身房？", isPresented: $showsDelete) {
            Button("删除健身房", role: .destructive, action: deleteRecord)
        }
    }

    private func save() {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        gym.name = normalized
        gym.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCurrent {
            GymSelection.activate(gym, among: allGyms)
        }
        sourceMessage?.recordManualCorrection(
            "健身房记录 \(gym.id.uuidString) 已改为 \(normalized)，当前状态 \(gym.isCurrent ? "已选择" : "未选择")"
        )
        try? modelContext.save()
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

private func compactNumber(
    _ title: String,
    text: Binding<String>,
    decimal: Bool = false
) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        TextField("-", text: text)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .accessibilityLabel(title)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private func actionRow(
    save: @escaping () -> Void,
    delete: @escaping () -> Void
) -> some View {
    HStack {
        Button(role: .destructive, action: delete) {
            Label("删除", systemImage: "trash")
        }
        .buttonStyle(.plain)
        Spacer()
        Button("保存", action: save)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
    }
    .font(.caption.weight(.semibold))
}
