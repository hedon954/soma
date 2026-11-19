#if DEBUG || SOMA_EXERCISE_METADATA_REPAIR
    import SwiftData
    import SwiftUI

    struct ExerciseMuscleRepairView: View {
        @Environment(\.modelContext) private var context
        @Environment(\.dismiss) private var dismiss
        @State private var plan: ExerciseMuscleRepair?
        @State private var preview: ExerciseMuscleRepair.Preview?
        @State private var applied: Int?
        @State private var confirms = false
        @State private var error: String?
        let onClose: () -> Void

        var body: some View {
            Form {
                if let preview {
                    Section {
                        if let applied {
                            Text("已修复 \(applied) 个动作")
                        }
                        if preview.changeCount == 0 {
                            Text("本次修复清单已处理完毕")
                            Button("关闭修复入口", action: close)
                        } else {
                            Button("应用 \(preview.changeCount) 个修复") { confirms = true }
                        }
                    } footer: {
                        Text("修复后，关联的训练详情和重新生成的分享图会使用更新的名称与受力标注。")
                    }
                    if !preview.pendingMerges.isEmpty {
                        Section("合并重复动作") {
                            ForEach(preview.pendingMerges) { merge in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(merge.sourceName) → \(merge.targetName)").font(.headline)
                                    Text("保留目标动作 ID，迁移来源动作的记录和处方")
                                }
                                .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                    if !preview.pending.isEmpty {
                        Section("名称与受力图预览") {
                            ForEach(preview.pending) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(entry.newName.map { "\(entry.name) → \($0)" } ?? entry.name).font(.headline)
                                    if !entry.primary.isEmpty {
                                        Text("主要 · \(entry.primary.map(\.displayName).joined(separator: "、"))")
                                    }
                                    if !entry.secondary.isEmpty {
                                        Text("辅助 · \(entry.secondary.map(\.displayName).joined(separator: "、"))")
                                    }
                                }
                                .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                    if !preview.unresolved.isEmpty {
                        Section("待核对 · \(preview.unresolved.count)") {
                            ForEach(preview.unresolved, id: \.self) { Text($0) }
                        }
                    }
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(AppTheme.accent)
                        Button("重新加载", action: load)
                    }
                }
            }
            .navigationTitle("修复动作元数据")
            .navigationBarTitleDisplayMode(.inline)
            .task { load() }
            .confirmationDialog("应用动作元数据修复？", isPresented: $confirms, titleVisibility: .visible) {
                Button("确认应用", action: apply)
                Button("取消", role: .cancel) {}
            }
        }

        private func load() {
            do {
                let loaded = try ExerciseMuscleRepair.load()
                preview = try loaded.preview(in: context)
                plan = loaded
                error = nil
            } catch {
                self.error = AppErrorMessage.message(for: error, operation: .load)
            }
        }

        private func apply() {
            guard let plan, let preview else { return }
            do {
                applied = try plan.apply(preview, in: context)
                load()
            } catch {
                load()
                self.error = AppErrorMessage.message(for: error, operation: .save)
            }
        }

        private func close() {
            do {
                try FileManager.default.removeItem(at: ExerciseMuscleRepair.planURL)
                dismiss()
                onClose()
            } catch {
                self.error = AppErrorMessage.message(for: error, operation: .save)
            }
        }
    }
#endif
