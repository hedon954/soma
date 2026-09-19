import SwiftData
import SwiftUI

struct GuidedExerciseReplacementPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID
    let onConfirm: (ExerciseDefinition, TemplateExercisePrescription) throws -> Void
    @State private var choices: [GuidedWorkoutExerciseChoice] = []
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        List {
            if let errorMessage {
                ContentUnavailableView(
                    "无法载入动作",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                Button("重新载入", action: load)
            } else {
                ForEach(filteredChoices) { choice in
                    NavigationLink {
                        GuidedExerciseReplacementConfirmation(
                            exerciseID: choice.id,
                            sessionID: sessionID,
                            onConfirm: onConfirm
                        )
                    } label: {
                        HStack(spacing: 12) {
                            ExerciseArtworkView(reference: choice.artwork)
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(choice.name)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索动作")
        .navigationTitle("替换当前动作")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .task { load() }
    }

    private var filteredChoices: [GuidedWorkoutExerciseChoice] {
        guard !searchText.isEmpty else { return choices }
        return choices.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func load() {
        do {
            choices = try GuidedWorkoutScreenSnapshotLoader.replacementChoices(
                from: modelContext.container
            )
            errorMessage = nil
        } catch {
            errorMessage = "暂时无法读取本机动作库。请重新载入；如果仍失败，请退出带练后重新进入。"
        }
    }
}

struct GuidedSessionPrescriptionEditor: View {
    @Environment(\.modelContext) private var modelContext
    let exerciseID: UUID
    let prescription: TemplateExercisePrescription
    let onSave: (ExerciseDefinition, TemplateExercisePrescription) throws -> Void
    @State private var exercise: ExerciseDefinition?
    @State private var failed = false

    var body: some View {
        Group {
            if let exercise {
                TrainingPrescriptionEditorView(
                    initialDraft: TrainingPrescriptionDraft(prescription),
                    exercise: exercise,
                    definitions: [exercise],
                    recent: nil,
                    editorTitle: "调整本次目标",
                    saveTitle: "保存",
                    locksExerciseSettings: true,
                    parameterSourceExplanation: "只改这次带练还没开始的组。训练计划和动作库保持不变。"
                ) { draft in
                    try onSave(
                        exercise,
                        draft.prescription(
                            order: prescription.order,
                            names: [exercise.id: exercise.canonicalName]
                        )
                    )
                }
            } else if failed {
                ContentUnavailableView {
                    Label("无法调整本次目标", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("训练尚未更改。请重试，或先准备本动作。")
                } actions: {
                    Button("重试", action: load)
                }
            } else {
                ProgressView("正在载入本次目标…")
            }
        }
        .task { load() }
    }

    private func load() {
        do {
            let exerciseID = exerciseID
            var descriptor = FetchDescriptor<ExerciseDefinition>(
                predicate: #Predicate { $0.id == exerciseID }
            )
            descriptor.fetchLimit = 1
            guard let loaded = try modelContext.fetch(descriptor).first else {
                throw GuidedExerciseReplacementError.missingExercise
            }
            exercise = loaded
            failed = false
        } catch {
            failed = true
        }
    }
}

private struct GuidedExerciseReplacementConfirmation: View {
    @Environment(\.modelContext) private var modelContext
    let exerciseID: UUID
    let sessionID: UUID
    let onConfirm: (ExerciseDefinition, TemplateExercisePrescription) throws -> Void
    @State private var exercise: ExerciseDefinition?
    @State private var preview: GuidedExerciseReplacementPreview?
    @State private var failed = false

    var body: some View {
        Group {
            if let exercise, let preview {
                TrainingPrescriptionEditorView(
                    initialDraft: TrainingPrescriptionDraft(preview.prescription),
                    exercise: exercise,
                    definitions: [exercise],
                    recent: nil,
                    editorTitle: "确认替换参数",
                    saveTitle: "替换动作",
                    locksExerciseSettings: true,
                    parameterSourceExplanation: preview.explanation,
                    parameterSourceSummary: preview.sourceSummary
                ) { draft in
                    try onConfirm(
                        exercise,
                        draft.prescription(
                            order: 1,
                            names: [exercise.id: exercise.canonicalName]
                        )
                    )
                }
            } else if failed {
                ContentUnavailableView {
                    Label("无法读取最近记录", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("训练尚未更改。请重试，或返回选择其他动作。")
                } actions: {
                    Button("重试", action: load)
                }
            } else {
                ProgressView("正在读取最近记录…")
            }
        }
        .task { load() }
    }

    private func load() {
        do {
            let exerciseID = exerciseID
            var descriptor = FetchDescriptor<ExerciseDefinition>(
                predicate: #Predicate { $0.id == exerciseID && $0.archivedAt == nil }
            )
            descriptor.fetchLimit = 1
            guard let loaded = try modelContext.fetch(descriptor).first else {
                throw GuidedExerciseReplacementError.missingExercise
            }
            exercise = loaded
            preview = try GuidedExerciseReplacementResolver.preview(
                exercise: loaded,
                excluding: sessionID,
                in: modelContext
            )
            failed = false
        } catch {
            failed = true
        }
    }
}
