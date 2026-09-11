import SwiftData
import SwiftUI

struct GuidedExerciseReplacementPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID
    let onConfirm: (ExerciseDefinition, TemplateExercisePrescription) throws -> Void
    @State private var definitions: [ExerciseDefinition] = []
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        List {
            if let errorMessage {
                ContentUnavailableView(
                    "无法载入动作", systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                Button("重新载入", action: load)
            } else {
                ForEach(definitions.filter {
                    searchText.isEmpty || $0.canonicalName.localizedCaseInsensitiveContains(searchText)
                }) { exercise in
                    NavigationLink {
                        GuidedExerciseReplacementConfirmation(
                            exercise: exercise, sessionID: sessionID, onConfirm: onConfirm
                        )
                    } label: {
                        HStack(spacing: 12) {
                            ExerciseArtworkView(reference: exercise.preferredActionIllustration)
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(exercise.canonicalName)
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

    private func load() {
        do {
            definitions = try modelContext.fetch(FetchDescriptor<ExerciseDefinition>(
                predicate: #Predicate { !$0.isArchived },
                sortBy: [SortDescriptor(\.canonicalName)]
            ))
            errorMessage = nil
        } catch {
            errorMessage = "暂时无法读取本机动作库。请重新载入；如果仍失败，请退出带练后重新进入。"
        }
    }
}

private struct GuidedExerciseReplacementConfirmation: View {
    @Environment(\.modelContext) private var modelContext
    let exercise: ExerciseDefinition
    let sessionID: UUID
    let onConfirm: (ExerciseDefinition, TemplateExercisePrescription) throws -> Void
    @State private var preview: GuidedExerciseReplacementPreview?
    @State private var failed = false

    var body: some View {
        Group {
            if let preview {
                TrainingPrescriptionEditorView(
                    initialDraft: TrainingPrescriptionDraft(preview.prescription),
                    exercise: exercise, definitions: [exercise], recent: nil,
                    replacementPreview: preview
                ) { draft in
                    try onConfirm(exercise, draft.prescription(
                        order: 1, names: [exercise.id: exercise.canonicalName]
                    ))
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
            preview = try GuidedExerciseReplacementResolver.preview(
                exercise: exercise, excluding: sessionID, in: modelContext
            )
            failed = false
        } catch {
            failed = true
        }
    }
}
