import SwiftData
import SwiftUI
import UIKit

private struct GuidedWorkoutAlertItem: Identifiable {
    enum Kind: Equatable {
        case operation
        case recording
    }

    let id = UUID()
    let kind: Kind
    let message: String

    var title: String {
        switch kind {
        case .operation:
            "训练操作失败"
        case .recording:
            "录像无法继续"
        }
    }

    var offersSettings: Bool {
        kind == .recording && message.contains("系统设置")
    }
}

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
    @State private var presentation = GuidedWorkoutPresentationState()
    @State private var showsActualEditor = false
    @State private var showsEndConfirmation = false
    @State private var showsReplacement = false
    @State private var presentedAlert: GuidedWorkoutAlertItem?

    init(session: WorkoutSession) {
        self.session = session
        #if DEBUG
            if ProcessInfo.processInfo.environment["SOMA_GUIDED_CAPTURE_PREVIEW"] == "1" {
                _presentation = State(initialValue: GuidedWorkoutPresentationState(
                    mode: .expandedCapture
                ))
            }
        #endif
    }

    private var performances: [ExercisePerformance] {
        allPerformances
            .filter { $0.sessionID == session.id }
            .sorted { $0.order < $1.order }
    }

    private var currentPerformance: ExercisePerformance? {
        guard let id = session.currentPerformanceID else { return nil }
        return performances.first { $0.id == id }
    }

    private var currentSet: WorkoutSet? {
        guard let id = session.currentSetID else { return nil }
        return allSets.first { $0.id == id }
    }

    private var currentPerformanceSets: [WorkoutSet] {
        guard let id = currentPerformance?.id else { return [] }
        return allSets
            .filter { $0.performanceID == id }
            .sorted { $0.order < $1.order }
    }

    private var sessionSets: [WorkoutSet] {
        let performanceIDs = Set(performances.map(\.id))
        return allSets.filter { performanceIDs.contains($0.performanceID) }
    }

    private var completedSetCount: Int {
        sessionSets.count { $0.status == .completed }
    }

    private var projectionKey: String {
        [
            session.statusRaw,
            session.guidedPhaseRaw,
            session.currentSetID?.uuidString ?? "none",
            session.restTargetEndAt?.timeIntervalSince1970.formatted() ?? "none",
            String(completedSetCount)
        ].joined(separator: ":")
    }

    private var currentExerciseDefinition: ExerciseDefinition? {
        guard let id = currentPerformance?.exerciseID else { return nil }
        return definitions.first { $0.id == id }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                if session.status == .active,
                   presentation.mode == .expandedCapture,
                   session.guidedPhase == .setInProgress,
                   camera.state == .recording
                {
                    GuidedExpandedCaptureView(
                        camera: camera,
                        sessionStartedAt: session.startedAt,
                        performance: currentPerformance,
                        performanceCount: performances.count,
                        set: currentSet,
                        sets: currentPerformanceSets,
                        targetText: targetText,
                        coachingNote: coachingNote,
                        isLandscape: proxy.size.width > proxy.size.height,
                        cameraErrorMessage: coordinator.recordingErrorMessage,
                        onCollapse: {
                            var next = presentation
                            next.collapse()
                            presentation = next
                        },
                        onPause: pauseOrResume,
                        onComplete: completeCurrentSet,
                        onEdit: { showsActualEditor = true },
                        onMore: { showsEndConfirmation = true }
                    )
                } else {
                    compactContent(isLandscape: proxy.size.width > proxy.size.height)
                }
            }
        }
        .navigationBarBackButtonHidden(session.status == .active)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: coordinator.recordingFailure?.id) {
            if let failure = coordinator.recordingFailure {
                presentRecordingError(failure.message)
            }
        }
        .task {
            WorkoutInterfaceOrientationPolicy.shared
                .setGuidedWorkoutActive(true)
            await coordinator.activate(session, in: modelContext)
            if session.guidedPhase == .ready {
                do {
                    try coordinator.introduceCurrentExercise(in: modelContext)
                } catch {
                    presentOperationError(error)
                }
            }
        }
        .task(id: projectionKey) {
            await WorkoutSystemProjectionCoordinator.shared.update(
                session: session,
                completedSetCount: completedSetCount,
                totalSetCount: sessionSets.count
            )
        }
        .onDisappear {
            WorkoutInterfaceOrientationPolicy.shared
                .setGuidedWorkoutActive(false)
            Task { await camera.stopPreview() }
        }
        .onChange(of: session.currentSetID, initial: true) {
            actualReps = currentSet?.plannedReps.map(String.init) ?? ""
            actualWeight = currentSet?.plannedWeightKG.map {
                $0.formatted()
            } ?? ""
        }
        .onChange(of: camera.state) {
            var next = presentation
            next.cameraStateChanged(camera.state)
            presentation = next
            if case let .unavailable(message) = camera.state {
                presentRecordingError(message)
            }
        }
        .onChange(of: camera.previewIssueMessage) {
            if let message = camera.previewIssueMessage {
                presentRecordingError(message)
            }
        }
        .onChange(of: session.guidedPhaseRaw) {
            var next = presentation
            next.phaseChanged(session.guidedPhase)
            #if DEBUG
                if session.guidedPhase == .setInProgress,
                   ProcessInfo.processInfo.environment[
                       "SOMA_GUIDED_CAPTURE_PREVIEW"
                   ] == "1"
                {
                    next.expand()
                }
            #endif
            presentation = next
        }
        .sheet(isPresented: $showsActualEditor) {
            GuidedSetActualEditor(
                reps: $actualReps,
                weight: $actualWeight,
                targetText: targetText
            )
        }
        .confirmationDialog(
            "提前结束本次训练？",
            isPresented: $showsEndConfirmation
        ) {
            Button("结束并保留已完成组", role: .destructive) {
                run {
                    try await coordinator.endEarly(in: modelContext)
                    await WorkoutSystemProjectionCoordinator.shared.end(
                        session: session,
                        completedSetCount: completedSetCount,
                        totalSetCount: sessionSets.count
                    )
                    dismiss()
                }
            }
            Button("继续训练", role: .cancel) {}
        }
        .sheet(isPresented: $showsReplacement) {
            NavigationStack {
                List(definitions.filter { !$0.isArchived }) { exercise in
                    Button {
                        replaceCurrentExercise(with: exercise)
                    } label: {
                        HStack(spacing: 12) {
                            ExerciseArtworkView(
                                reference: exercise.preferredActionIllustration
                            )
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(exercise.canonicalName)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .navigationTitle("替换当前动作")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert(item: $presentedAlert) { item in
            if item.offersSettings {
                Alert(
                    title: Text(item.title),
                    message: Text(item.message),
                    primaryButton: .default(Text("打开设置")) {
                        guard let url = URL(
                            string: UIApplication.openSettingsURLString
                        ) else { return }
                        UIApplication.shared.open(url)
                    },
                    secondaryButton: .cancel(Text("好"))
                )
            } else {
                Alert(
                    title: Text(item.title),
                    message: Text(item.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private func compactContent(isLandscape: Bool) -> some View {
        VStack(spacing: 0) {
            GuidedWorkoutChrome(
                session: session,
                completedExerciseCount: performances.count {
                    $0.status == .completed || $0.status == .skipped
                },
                exerciseCount: performances.count,
                onPause: pauseOrResume,
                onEnd: { showsEndConfirmation = true }
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)

            phaseContent(isLandscape: isLandscape)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func phaseContent(isLandscape: Bool) -> some View {
        if session.status == .paused {
            GuidedPausedView(onResume: pauseOrResume)
        } else {
            switch session.guidedPhase {
            case .ready:
                ProgressView("准备训练…")
            case .exerciseIntroduction:
                GuidedExerciseIntroductionView(
                    exercise: currentExerciseDefinition,
                    performance: currentPerformance,
                    onPrepare: prepareCurrentSet,
                    onReplace: { showsReplacement = true },
                    onSkip: skipCurrentExercise
                )
            case .preSetCountdown:
                GuidedSetCountdownView(
                    set: currentSet,
                    targetText: targetText,
                    phaseStartedAt: session.phaseStartedAt,
                    onTick: coordinator.announceCountdown,
                    onFinished: beginCurrentSetAfterCountdown
                )
            case .setInProgress:
                GuidedCompactSetView(
                    camera: camera,
                    exercise: currentExerciseDefinition,
                    performance: currentPerformance,
                    performanceCount: performances.count,
                    set: currentSet,
                    sets: currentPerformanceSets,
                    targetText: targetText,
                    coachingNote: coachingNote,
                    isLandscape: isLandscape,
                    showsCamera: showsCompactCamera,
                    isStartingRecording: coordinator.isStartingRecording,
                    canStartRecording: coordinator.recordingSetID == nil,
                    cameraErrorMessage: coordinator.recordingErrorMessage,
                    onExpandCamera: {
                        var next = presentation
                        next.expand()
                        presentation = next
                    },
                    onRecord: startManualRecording,
                    onEdit: { showsActualEditor = true },
                    onComplete: completeCurrentSet,
                    onSkip: skipCurrentSet
                )
            case .setConfirmation:
                GuidedSetRecoveryView(
                    targetText: targetText,
                    onCompleted: completeCurrentSet,
                    onRedo: redoCurrentSet,
                    onSkip: skipCurrentSet
                )
            case .resting:
                GuidedRestView(
                    nextSet: currentSet,
                    remainingSeconds: {
                        coordinator.remainingRestSeconds(
                            for: session,
                            in: modelContext
                        )
                    },
                    onTick: coordinator.announceCountdown,
                    onAdjust: adjustRest,
                    onFinish: finishRest
                )
            case .sessionReview:
                GuidedSessionReviewView(
                    summary: TrainingPlanStore.summary(
                        for: session.id,
                        in: modelContext
                    ),
                    onFinish: finishSession
                )
            case .completed:
                GuidedSessionReviewView(
                    summary: TrainingPlanStore.summary(
                        for: session.id,
                        in: modelContext
                    ),
                    onFinish: { dismiss() }
                )
            }
        }
    }

    private var targetText: String {
        let reps = Int(actualReps)
        let weight = Double(actualWeight)
        switch (weight, reps) {
        case let (.some(weight), .some(reps)):
            return "\(weight == 0 ? "自重" : "\(weight.formatted()) kg") × \(reps) 次"
        case let (.some(weight), .none):
            return weight == 0 ? "自重" : "\(weight.formatted()) kg"
        case let (.none, .some(reps)):
            return "\(reps) 次"
        case (.none, .none):
            return "按状态完成"
        }
    }

    private var coachingNote: String {
        let note = currentExerciseDefinition?.coachingNotes
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
            ?? "保持动作稳定，在可控范围内完成本组。"
        let boundaries = ["；", "。"].compactMap {
            note.firstIndex(of: Character($0))
        }
        guard let boundary = boundaries.min() else { return note }
        return String(note[..<boundary]) + "。"
    }

    private var showsCompactCamera: Bool {
        if camera.state == .recording,
           coordinator.recordingSetID == currentSet?.id
        {
            return true
        }
        #if DEBUG
            return ProcessInfo.processInfo.environment["SOMA_GUIDED_CAPTURE_PREVIEW"] == "1"
        #else
            return false
        #endif
    }

    private func startManualRecording() {
        run { try await coordinator.startManualRecording(in: modelContext) }
    }

    private func pauseOrResume() {
        if session.status == .paused {
            do {
                try coordinator.resume(in: modelContext)
            } catch {
                presentOperationError(error)
            }
        } else {
            run { try await coordinator.pause(in: modelContext) }
        }
    }

    private func prepareCurrentSet() {
        do {
            try coordinator.prepareCurrentSet(in: modelContext)
        } catch {
            presentOperationError(error)
        }
    }

    @MainActor
    private func beginCurrentSetAfterCountdown() async {
        guard session.guidedPhase == .preSetCountdown else { return }
        do {
            try await coordinator.beginCurrentSet(in: modelContext)
        } catch {
            presentOperationError(error)
        }
    }

    private func completeCurrentSet() {
        run {
            try await coordinator.confirmCurrentSet(
                actualReps: Int(actualReps),
                actualWeightKG: Double(actualWeight),
                in: modelContext
            )
        }
    }

    private func redoCurrentSet() {
        run { try await coordinator.redoCurrentSet(in: modelContext) }
    }

    private func skipCurrentSet() {
        run { try await coordinator.skipCurrentSet(in: modelContext) }
    }

    private func skipCurrentExercise() {
        run { try await coordinator.skipCurrentExercise(in: modelContext) }
    }

    private func adjustRest(_ seconds: Int) {
        do {
            try coordinator.adjustRest(by: seconds, in: modelContext)
        } catch {
            presentOperationError(error)
        }
    }

    private func finishRest() {
        do {
            try coordinator.finishRest(in: modelContext)
        } catch {
            presentOperationError(error)
        }
    }

    private func finishSession() {
        do {
            try coordinator.complete(in: modelContext)
            Task {
                await WorkoutSystemProjectionCoordinator.shared.end(
                    session: session,
                    completedSetCount: completedSetCount,
                    totalSetCount: sessionSets.count
                )
            }
            dismiss()
        } catch {
            presentOperationError(error)
        }
    }

    private func replaceCurrentExercise(with exercise: ExerciseDefinition) {
        do {
            try coordinator.replaceCurrentExercise(
                with: exercise,
                in: modelContext
            )
            showsReplacement = false
        } catch {
            presentOperationError(error)
        }
    }

    private func run(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        Task {
            do {
                try await operation()
            } catch {
                if coordinator.recordingFailure?.message == error.localizedDescription {
                    presentRecordingError(error.localizedDescription)
                } else {
                    presentOperationError(error)
                }
            }
        }
    }

    private func presentOperationError(_ error: Error) {
        presentedAlert = GuidedWorkoutAlertItem(
            kind: .operation,
            message: error.localizedDescription
        )
    }

    private func presentRecordingError(_ message: String) {
        guard !message.isEmpty else { return }
        if presentedAlert?.kind == .recording,
           presentedAlert?.message == message
        {
            return
        }
        presentedAlert = GuidedWorkoutAlertItem(
            kind: .recording,
            message: message
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
