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

private struct GuidedProjectionRevision: Hashable {
    let statusRaw: String
    let phaseRaw: String
    let currentSetID: UUID?
    let currentEffortID: UUID?
    let restTargetEndAt: Date?
    let completedSetCount: Int
}

private struct GuidedTimelineRevision: Hashable {
    let statusRaw: String
    let phaseRaw: String
    let transitionRevision: Int
    let phaseDeadlineAt: Date?
}

private struct GuidedExerciseReplacementList: View {
    @Query private var definitions: [ExerciseDefinition]
    let onSelect: (ExerciseDefinition) -> Void

    init(onSelect: @escaping (ExerciseDefinition) -> Void) {
        self.onSelect = onSelect
        var descriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.canonicalName)]
        )
        descriptor.fetchLimit = 2000
        _definitions = Query(descriptor)
    }

    var body: some View {
        List(definitions) { exercise in
            Button {
                onSelect(exercise)
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

struct GuidedWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(GuidedWorkoutCoordinator.self) private var coordinator
    @Environment(WorkoutCameraService.self) private var camera
    @Query private var allPerformances: [ExercisePerformance]
    @Query private var allSets: [WorkoutSet]
    @Query private var allEfforts: [WorkoutEffort]

    let session: WorkoutSession
    var onFinishedReturnHome: () -> Void = {}
    @State private var actualReps = ""
    @State private var actualDuration = ""
    @State private var actualWeight = ""
    @State private var presentation = GuidedWorkoutPresentationState()
    @State private var showsActualEditor = false
    @State private var showsEndConfirmation = false
    @State private var showsReplacement = false
    @State private var presentedAlert: GuidedWorkoutAlertItem?
    @State private var shareModel: WorkoutSharePosterModel?
    @State private var isFinalizingSession = false
    @State private var finalizationState = GuidedSessionFinalizationState.saving
    @State private var effortCompletionErrorMessage: String?
    @State private var isCoordinatorActivated = false
    @State private var sessionOwner: WorkoutCameraSessionOwnerToken?

    init(
        session: WorkoutSession,
        onFinishedReturnHome: @escaping () -> Void = {}
    ) {
        self.session = session
        self.onFinishedReturnHome = onFinishedReturnHome
        let sessionID = session.id
        _allPerformances = Query(
            FetchDescriptor<ExercisePerformance>(
                predicate: #Predicate { $0.sessionID == sessionID },
                sortBy: [SortDescriptor(\.order)]
            )
        )
        _allSets = Query(
            FetchDescriptor<WorkoutSet>(
                predicate: #Predicate {
                    $0.performance?.sessionID == sessionID
                },
                sortBy: [SortDescriptor(\.order)]
            )
        )
        _allEfforts = Query(
            FetchDescriptor<WorkoutEffort>(
                predicate: #Predicate {
                    $0.workoutSet?.performance?.sessionID == sessionID
                },
                sortBy: [SortDescriptor(\.order)]
            )
        )
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
    }

    private var currentPerformance: ExercisePerformance? {
        guard let id = session.currentPerformanceID else { return nil }
        return performances.first { $0.id == id }
    }

    private var currentSet: WorkoutSet? {
        guard let id = session.currentSetID else { return nil }
        return allSets.first { $0.id == id }
    }

    private var currentEffort: WorkoutEffort? {
        guard let id = session.currentEffortID else { return nil }
        return allEfforts.first { $0.id == id }
    }

    private var currentPerformanceSets: [WorkoutSet] {
        guard let id = currentPerformance?.id else { return [] }
        return allSets.filter { $0.performanceID == id }
    }

    private var sessionSets: [WorkoutSet] {
        allSets
    }

    private var completedSetCount: Int {
        sessionSets.count { $0.status == .completed }
    }

    private var workoutProgressExercises: [GuidedWorkoutProgressExercise] {
        let setsByPerformanceID = Dictionary(
            grouping: allSets,
            by: \.performanceID
        )
        let effortsBySetID = Dictionary(
            grouping: allEfforts,
            by: \.workoutSetID
        )
        return performances.map { performance in
            let sets = (setsByPerformanceID[performance.id] ?? [])
                .map { set in
                    let efforts = effortsBySetID[set.id] ?? []
                    let state: GuidedWorkoutProgressSetState = switch set.status {
                    case .completed:
                        .completed
                    case .partial:
                        .partial
                    case .skipped:
                        .skipped
                    case .failed:
                        .failed
                    case .inProgress:
                        .current
                    case .pending:
                        set.id == session.currentSetID ? .current : .pending
                    }
                    return GuidedWorkoutProgressExercise.SetSegment(
                        id: set.id,
                        state: state,
                        completionFraction: GuidedWorkoutProgressExercise
                            .completionFraction(
                                set: set,
                                efforts: efforts
                            )
                    )
                }
            return GuidedWorkoutProgressExercise(
                id: performance.id,
                sets: sets
            )
        }
    }

    private var projectionKey: GuidedProjectionRevision {
        GuidedProjectionRevision(
            statusRaw: session.statusRaw,
            phaseRaw: session.guidedPhaseRaw,
            currentSetID: session.currentSetID,
            currentEffortID: session.currentEffortID,
            restTargetEndAt: session.restTargetEndAt,
            completedSetCount: completedSetCount
        )
    }

    private var timelineKey: GuidedTimelineRevision {
        GuidedTimelineRevision(
            statusRaw: session.statusRaw,
            phaseRaw: session.guidedPhaseRaw,
            transitionRevision: session.transitionRevision,
            phaseDeadlineAt: session.phaseDeadlineAt
        )
    }

    private var currentExerciseDefinition: ExerciseDefinition? {
        currentPerformance?.exerciseDefinition
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppTheme.pageBackground
                    .ignoresSafeArea()

                if session.status == .active,
                   GuidedExpandedCaptureVisibility.isVisible(
                       sessionIsActive: true,
                       mode: presentation.mode,
                       phase: session.guidedPhase,
                       cameraState: camera.state,
                       isStartingRecording: coordinator.isStartingRecording
                   )
                {
                    GuidedExpandedCaptureView(
                        camera: camera,
                        sessionStartedAt: session.startedAt,
                        performance: currentPerformance,
                        performanceCount: performances.count,
                        set: currentSet,
                        sets: currentPerformanceSets,
                        targetText: targetText,
                        effortSide: currentEffort?.side ?? .none,
                        isAutomaticDuration: isAutomaticDuration,
                        remainingDurationSeconds: remainingDurationSeconds,
                        durationDeadlineAt: session.phaseDeadlineAt,
                        isCompletingEffort: coordinator
                            .isCompletingCurrentEffort,
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
            isCoordinatorActivated = false
            WorkoutInterfaceOrientationPolicy.shared
                .setGuidedWorkoutActive(true)
            let owner = await coordinator.activate(session, in: modelContext)
            guard !Task.isCancelled, coordinator.isActive(owner: owner) else {
                let didDeactivate = await coordinator.deactivate(owner: owner)
                if didDeactivate {
                    WorkoutInterfaceOrientationPolicy.shared
                        .setGuidedWorkoutActive(false)
                }
                return
            }
            sessionOwner = owner
            isCoordinatorActivated = true
            if session.guidedPhase == .ready {
                do {
                    try coordinator.introduceCurrentExercise(in: modelContext)
                } catch {
                    presentOperationError(error)
                }
            } else if session.guidedPhase == .sessionReview
                || session.status == .completed
            {
                finalizeSessionAndShare()
            }
        }
        .task(id: projectionKey) {
            await WorkoutSystemProjectionCoordinator.shared.update(
                session: session,
                completedSetCount: completedSetCount,
                totalSetCount: sessionSets.count
            )
        }
        .task(id: session.currentEffortID) {
            guard isCoordinatorActivated else { return }
            await coordinator.preflightAutomaticRecording(in: modelContext)
        }
        .task(id: timelineKey) {
            await advanceTimelineAtDeadline()
        }
        .onDisappear {
            isCoordinatorActivated = false
            let owner = sessionOwner
            sessionOwner = nil
            Task {
                guard let owner else { return }
                let didDeactivate = await coordinator.deactivate(owner: owner)
                if didDeactivate {
                    WorkoutInterfaceOrientationPolicy.shared
                        .setGuidedWorkoutActive(false)
                }
            }
        }
        .onChange(of: session.currentEffortID, initial: true) {
            effortCompletionErrorMessage = nil
            actualReps = (currentEffort?.actualReps
                ?? currentEffort?.plannedReps).map(String.init) ?? ""
            actualDuration = (currentEffort?.actualDurationSeconds
                ?? currentEffort?.plannedDurationSeconds).map(String.init)
                ?? ""
            actualWeight = (currentEffort?.actualWeightKG
                ?? currentEffort?.plannedWeightKG).map {
                $0.formatted()
            } ?? ""
        }
        .onChange(of: camera.state) {
            var next = presentation
            next.cameraStateChanged(
                camera.state,
                isStartingRecording: coordinator.isStartingRecording
            )
            presentation = next
        }
        .onChange(of: session.guidedPhaseRaw) {
            var next = presentation
            next.phaseChanged(
                session.guidedPhase,
                expandForRecording: coordinator.shouldCaptureCurrentEffort(
                    in: modelContext
                )
            )
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
            if session.guidedPhase == .sessionReview
                || session.guidedPhase == .completed
            {
                finalizeSessionAndShare()
            }
        }
        .sheet(isPresented: $showsActualEditor) {
            GuidedSetActualEditor(
                reps: $actualReps,
                duration: $actualDuration,
                weight: $actualWeight,
                targetText: targetText,
                targetKind: currentEffort?.targetKind ?? .repetitions,
                side: currentEffort?.side ?? .none,
                onSave: saveActualDraft
            )
        }
        .confirmationDialog(
            "提前结束本次训练？",
            isPresented: $showsEndConfirmation
        ) {
            Button("结束并保留已完成组", role: .destructive) {
                run {
                    try await coordinator.endEarly(in: modelContext)
                    finalizeSessionAndShare()
                }
            }
            Button("继续训练", role: .cancel) {}
        }
        .sheet(isPresented: $showsReplacement) {
            NavigationStack {
                GuidedExerciseReplacementList(
                    onSelect: replaceCurrentExercise
                )
            }
        }
        .sheet(item: $shareModel, onDismiss: {
            onFinishedReturnHome()
            dismiss()
        }) { model in
            WorkoutShareSheet(model: model)
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
                progressExercises: workoutProgressExercises,
                isRecording: coordinator.recordingSetID != nil,
                isStartingRecording: coordinator.isStartingRecording,
                isRecordingQueued: coordinator.manualRecordingQueued,
                automaticRecordingPaused: coordinator.automaticRecordingPaused,
                cameraState: camera.state,
                recordingStatusMessage: coordinator.recordingStatusMessage,
                onRecord: toggleManualRecording,
                onOpenCameraSettings: openCameraSettings,
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
                    camera: phasePictureInPictureCamera,
                    isLandscape: isLandscape,
                    cameraErrorMessage: coordinator.recordingErrorMessage,
                    onPrepare: prepareCurrentSet,
                    onReplace: { showsReplacement = true },
                    onSkip: skipCurrentExercise
                )
            case .preSetCountdown:
                GuidedSetCountdownView(
                    set: currentSet,
                    targetText: targetText,
                    phaseStartedAt: session.phaseStartedAt,
                    deadlineAt: session.phaseDeadlineAt,
                    camera: phasePictureInPictureCamera,
                    isLandscape: isLandscape,
                    cameraErrorMessage: coordinator.recordingErrorMessage,
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
                    effortSide: currentEffort?.side ?? .none,
                    isAutomaticDuration: isAutomaticDuration,
                    remainingDurationSeconds: remainingDurationSeconds,
                    durationDeadlineAt: session.phaseDeadlineAt,
                    completionErrorMessage: effortCompletionErrorMessage,
                    coachingNote: coachingNote,
                    isLandscape: isLandscape,
                    showsCamera: showsCompactCamera,
                    isRecording: coordinator.recordingSetID == currentSet?.id,
                    isStartingRecording: coordinator.isStartingRecording,
                    isCompletingEffort: coordinator
                        .isCompletingCurrentEffort,
                    canStartRecording: coordinator.recordingSetID == nil
                        || coordinator.recordingSetID == currentSet?.id,
                    cameraErrorMessage: coordinator.recordingErrorMessage,
                    onExpandCamera: {
                        var next = presentation
                        next.expand()
                        presentation = next
                    },
                    onRecord: toggleManualRecording,
                    onEdit: { showsActualEditor = true },
                    onComplete: completeCurrentSet,
                    onSkip: skipCurrentSet
                )
            case .setConfirmation:
                GuidedSetRecoveryView(
                    targetText: targetText,
                    effortSide: currentEffort?.side ?? .none,
                    isCompletingEffort: coordinator
                        .isCompletingCurrentEffort,
                    onCompleted: completeCurrentSet,
                    onRedo: redoCurrentSet,
                    onSkip: skipCurrentSet
                )
            case .resting:
                GuidedRestView(
                    nextSet: currentSet,
                    nextEffort: currentEffort,
                    remainingSeconds: {
                        coordinator.remainingRestSeconds(
                            for: session,
                            in: modelContext
                        )
                    },
                    camera: phasePictureInPictureCamera,
                    isLandscape: isLandscape,
                    cameraErrorMessage: coordinator.recordingErrorMessage,
                    onTick: coordinator.announceCountdown,
                    onAdjust: adjustRest,
                    onFinish: finishRest
                )
            case .sessionReview, .completed:
                GuidedSessionFinalizationView(
                    state: finalizationState,
                    onRetry: finalizeSessionAndShare
                )
            }
        }
    }

    private var targetText: String {
        let reps = Int(actualReps)
        let duration = Int(actualDuration)
        let weight = Double(actualWeight)
        var tokens: [String] = []
        if let effort = currentEffort, effort.side != .none {
            tokens.append(WorkoutPrescriptionFormatter.sideName(effort.side))
        }
        if let weight {
            tokens.append(weight == 0 ? "自重" : "\(weight.formatted()) kg")
        }
        switch currentEffort?.targetKind ?? currentSet?.plannedTargetKind {
        case .duration:
            if let remainingDurationSeconds,
               session.guidedPhase == .setInProgress
            {
                tokens.append("剩余 \(remainingDurationSeconds) 秒")
            } else if let duration {
                tokens.append("\(duration) 秒")
            }
        case .repetitions, .none:
            if let reps {
                tokens.append("\(reps) 次")
            }
        }
        return tokens.isEmpty ? "按状态完成" : tokens.joined(separator: " · ")
    }

    private var isAutomaticDuration: Bool {
        currentEffort?.targetKind == .duration
    }

    private var remainingDurationSeconds: Int? {
        coordinator.remainingEffortSeconds(
            for: session,
            in: modelContext
        )
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
        if cameraSurfacePlacement == .setHero {
            return true
        }
        #if DEBUG
            return ProcessInfo.processInfo.environment["SOMA_GUIDED_CAPTURE_PREVIEW"] == "1"
        #else
            return false
        #endif
    }

    private var phasePictureInPictureCamera: WorkoutCameraService? {
        cameraSurfacePlacement == .phasePictureInPicture ? camera : nil
    }

    private var cameraSurfacePlacement: GuidedCameraSurfacePlacement {
        GuidedCameraSurfacePlacement.resolve(
            phase: session.guidedPhase,
            cameraState: camera.state,
            isStarting: coordinator.isStartingRecording,
            sessionIsActive: session.status == .active,
            isCaptureTarget: coordinator.shouldCaptureCurrentEffort(
                in: modelContext
            )
        )
    }

    private func toggleManualRecording() {
        run { try await coordinator.toggleManualRecording(in: modelContext) }
    }

    private func openCameraSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
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
        if coordinator.shouldCaptureCurrentEffort(in: modelContext) {
            var next = presentation
            next.expand()
            presentation = next
        }
        do {
            try await coordinator.beginCurrentSet(in: modelContext)
        } catch {
            presentOperationError(error)
        }
    }

    private func completeCurrentSet() {
        Task {
            do {
                try await coordinator.completeCurrentEffort(
                    actualReps: Int(actualReps),
                    actualDurationSeconds: Int(actualDuration),
                    actualWeightKG: Double(actualWeight),
                    in: modelContext
                )
                effortCompletionErrorMessage = nil
            } catch {
                effortCompletionErrorMessage = error.localizedDescription
                presentOperationError(error)
            }
        }
    }

    private func saveActualDraft() {
        do {
            try coordinator.updateCurrentEffortDraft(
                actualReps: Int(actualReps),
                actualDurationSeconds: Int(actualDuration),
                actualWeightKG: Double(actualWeight),
                in: modelContext
            )
        } catch {
            presentOperationError(error)
        }
    }

    @MainActor
    private func advanceTimelineAtDeadline() async {
        guard session.status == .active,
              let deadline = session.phaseDeadlineAt
        else { return }
        let revision = session.transitionRevision
        do {
            let delay = max(deadline.timeIntervalSinceNow, 0)
            try await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            try await coordinator.advanceTimelineIfDue(
                expectedRevision: revision,
                in: modelContext
            )
        } catch is CancellationError {
            return
        } catch {
            if session.guidedPhase == .setInProgress,
               currentEffort?.targetKind == .duration
            {
                effortCompletionErrorMessage = error.localizedDescription
            }
            presentOperationError(error)
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

    private func finalizeSessionAndShare() {
        guard !isFinalizingSession, shareModel == nil else { return }
        isFinalizingSession = true
        finalizationState = .saving
        Task {
            do {
                if session.status == .active {
                    try coordinator.complete(in: modelContext)
                }
                await WorkoutSystemProjectionCoordinator.shared.end(
                    session: session,
                    completedSetCount: completedSetCount,
                    totalSetCount: sessionSets.count
                )
                shareModel = WorkoutSharePosterBuilder.makeModel(
                    session: session,
                    in: modelContext
                )
            } catch {
                isFinalizingSession = false
                finalizationState = .failed(error.localizedDescription)
                presentOperationError(error)
            }
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
                presentOperationError(error)
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
