import SwiftData
import SwiftUI

struct GuidedWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(GuidedWorkoutCoordinator.self) private var coordinator
    @Environment(WorkoutCameraService.self) private var camera
    @Query(sort: \ExercisePerformance.order)
    private var allPerformances: [ExercisePerformance]
    @Query(sort: \WorkoutSet.order)
    private var allSets: [WorkoutSet]
    @Query(sort: \ExerciseDefinition.canonicalName)
    private var definitions: [ExerciseDefinition]

    let session: WorkoutSession
    @State private var actualReps = ""
    @State private var actualWeight = ""
    @State private var showsEndConfirmation = false
    @State private var showsReplacement = false
    @State private var errorMessage: String?

    private var performances: [ExercisePerformance] {
        allPerformances.filter { $0.sessionID == session.id }
    }

    private var currentPerformance: ExercisePerformance? {
        guard let id = session.currentPerformanceID else { return nil }
        return performances.first { $0.id == id }
    }

    private var currentSet: WorkoutSet? {
        guard let id = session.currentSetID else { return nil }
        return allSets.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            if session.autoRecordingPolicy != .disabled,
               session.autoRecordingPolicy != .cancelled
            {
                cameraCard
            }

            Spacer(minLength: 0)
            phaseContent
            Spacer(minLength: 0)

            if let message = coordinator.recordingErrorMessage {
                Label(message, systemImage: "camera.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarBackButtonHidden(session.status == .active)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if session.status == .active {
                    Button("暂停") {
                        run { try await coordinator.pause(in: modelContext) }
                    }
                } else if session.status == .paused {
                    Button("继续") {
                        do {
                            try coordinator.resume(in: modelContext)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("结束", role: .destructive) {
                    showsEndConfirmation = true
                }
            }
        }
        .task {
            await coordinator.activate(session, in: modelContext)
            if session.guidedPhase == .ready {
                do {
                    try coordinator.introduceCurrentExercise(in: modelContext)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .task(id: session.guidedPhaseRaw) {
            guard session.guidedPhase == .preSetCountdown else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled,
                  session.guidedPhase == .preSetCountdown
            else {
                return
            }
            run { try await coordinator.beginCurrentSet(in: modelContext) }
        }
        .onChange(of: session.currentSetID, initial: true) {
            actualReps = currentSet?.plannedReps.map(String.init) ?? ""
            actualWeight = currentSet?.plannedWeightKG.map {
                $0.formatted()
            } ?? ""
        }
        .confirmationDialog(
            "提前结束本次训练？",
            isPresented: $showsEndConfirmation
        ) {
            Button("结束并保留已完成组", role: .destructive) {
                run {
                    try await coordinator.endEarly(in: modelContext)
                    dismiss()
                }
            }
            Button("继续训练", role: .cancel) {}
        }
        .sheet(isPresented: $showsReplacement) {
            NavigationStack {
                List(definitions.filter { !$0.isArchived }) { exercise in
                    Button(exercise.canonicalName) {
                        do {
                            try coordinator.replaceCurrentExercise(
                                with: exercise,
                                in: modelContext
                            )
                            showsReplacement = false
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .navigationTitle("替换当前动作")
            }
        }
        .alert(
            "训练操作失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ProgressView(
                value: Double(
                    performances.count {
                        $0.status == .completed || $0.status == .skipped
                    }
                ),
                total: Double(max(performances.count, 1))
            )
            HStack {
                Text(currentPerformance?.exerciseName ?? "训练总结")
                    .font(.title2.bold())
                Spacer()
                Text("\(performances.count { $0.status == .completed })/\(performances.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cameraCard: some View {
        VStack(spacing: 8) {
            WorkoutCameraPreview(session: camera.captureSession)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .topLeading) {
                    Label(
                        camera.state == .recording ? "录制中" : "前置相机",
                        systemImage: camera.state == .recording
                            ? "record.circle.fill"
                            : "person.crop.rectangle"
                    )
                    .font(.caption.bold())
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
                }
            HStack {
                Text(camera.state.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    if session.autoRecordingPolicy == .enabled {
                        Button("暂停后续自动录像") {
                            setRecordingPolicy(.paused)
                        }
                    } else if session.autoRecordingPolicy == .paused {
                        Button("恢复自动录像") {
                            setRecordingPolicy(.enabled)
                        }
                    }
                    Button("取消本次自动录像", role: .destructive) {
                        setRecordingPolicy(.cancelled)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("自动录像设置")
            }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch session.guidedPhase {
        case .ready:
            ProgressView("准备训练…")
        case .exerciseIntroduction:
            VStack(spacing: 16) {
                Text(currentExerciseDefinition?.coachingNotes.nilIfBlank
                    ?? "确认器械和动作空间，准备后开始第一组。")
                    .font(.body)
                Button("准备本动作") {
                    do {
                        try coordinator.prepareCurrentSet(in: modelContext)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                HStack {
                    Button("替换动作") { showsReplacement = true }
                    Button("跳过动作") {
                        run {
                            try await coordinator.skipCurrentExercise(
                                in: modelContext
                            )
                        }
                    }
                }
            }
        case .preSetCountdown:
            VStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 56))
                Text("3 秒后开始第 \(currentSet?.order ?? 1) 组")
                    .font(.title3.bold())
            }
        case .setInProgress:
            VStack(spacing: 18) {
                Text("第 \(currentSet?.order ?? 1) 组")
                    .font(.largeTitle.bold())
                Text(plannedSetText)
                    .foregroundStyle(.secondary)
                Button("完成本组") {
                    do {
                        try coordinator.requestSetConfirmation(
                            in: modelContext
                        )
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("跳过本组") {
                    run {
                        try await coordinator.skipCurrentSet(in: modelContext)
                    }
                }
            }
        case .setConfirmation:
            VStack(spacing: 16) {
                Text("确认实际完成")
                    .font(.title3.bold())
                HStack {
                    TextField("次数", text: $actualReps)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    TextField("重量 kg", text: $actualWeight)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                Button("保存本组") {
                    run {
                        try await coordinator.confirmCurrentSet(
                            actualReps: Int(actualReps),
                            actualWeightKG: Double(actualWeight),
                            in: modelContext
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .resting:
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let remaining = coordinator.remainingRestSeconds(
                    for: session,
                    in: modelContext
                )
                VStack(spacing: 16) {
                    Text("休息")
                        .font(.headline)
                    Text("\(remaining)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Button(remaining == 0 ? "开始下一组" : "结束休息") {
                        do {
                            try coordinator.finishRest(in: modelContext)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case .sessionReview:
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("本次训练已完成")
                    .font(.title2.bold())
                Text(
                    TrainingPlanStore.summary(
                        for: session.id,
                        in: modelContext
                    ).text
                )
                .multilineTextAlignment(.center)
                Button("保存并结束") {
                    do {
                        try coordinator.complete(in: modelContext)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .completed:
            Text("训练已保存")
        }
    }

    private var currentExerciseDefinition: ExerciseDefinition? {
        guard let id = currentPerformance?.exerciseID else { return nil }
        return definitions.first { $0.id == id }
    }

    private var plannedSetText: String {
        var values: [String] = []
        if let reps = currentSet?.plannedReps {
            values.append("\(reps) 次")
        }
        if let weight = currentSet?.plannedWeightKG {
            values.append("\(weight.formatted()) kg")
        }
        return values.isEmpty ? "按身体状态完成" : values.joined(separator: " · ")
    }

    private func run(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        Task {
            do {
                try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setRecordingPolicy(_ policy: AutoRecordingPolicy) {
        run {
            try await coordinator.setRecordingPolicy(
                policy,
                in: modelContext
            )
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
