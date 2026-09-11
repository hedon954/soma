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

struct GuidedWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(GuidedWorkoutCoordinator.self) private var coordinator
    @Environment(WorkoutCameraService.self) private var camera
    let sessionID: UUID
    var onFinishedReturnHome: () -> Void = {}
    @State private var snapshot: GuidedWorkoutScreenSnapshot?
    @State private var snapshotErrorMessage: String?
    @State private var snapshotGeneration = 0
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
        sessionID: UUID,
        onFinishedReturnHome: @escaping () -> Void = {}
    ) {
        self.sessionID = sessionID
        self.onFinishedReturnHome = onFinishedReturnHome
        #if DEBUG
            if ProcessInfo.processInfo.environment["SOMA_GUIDED_CAPTURE_PREVIEW"] == "1" {
                _presentation = State(initialValue: GuidedWorkoutPresentationState(
                    mode: .expandedCapture
                ))
            }
        #endif
    }

    private var projectionKey: GuidedProjectionRevision? {
        guard let snapshot else { return nil }
        return GuidedProjectionRevision(
            statusRaw: snapshot.session.statusRaw,
            phaseRaw: snapshot.session.guidedPhaseRaw,
            currentSetID: snapshot.session.currentSetID,
            currentEffortID: snapshot.session.currentEffortID,
            restTargetEndAt: snapshot.session.restTargetEndAt,
            completedSetCount: snapshot.completedSetCount
        )
    }

    private var timelineKey: GuidedTimelineRevision? {
        guard let snapshot else { return nil }
        return GuidedTimelineRevision(
            statusRaw: snapshot.session.statusRaw,
            phaseRaw: snapshot.session.guidedPhaseRaw,
            transitionRevision: snapshot.session.transitionRevision,
            phaseDeadlineAt: snapshot.session.phaseDeadlineAt
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppTheme.pageBackground
                    .ignoresSafeArea()

                if let snapshot,
                   snapshot.session.status == .active,
                   GuidedExpandedCaptureVisibility.isVisible(
                       sessionIsActive: true,
                       mode: presentation.mode,
                       phase: snapshot.session.guidedPhase,
                       cameraState: camera.state,
                       isStartingRecording: coordinator.isStartingRecording
                   )
                {
                    GuidedExpandedCaptureView(
                        camera: camera,
                        sessionStartedAt: snapshot.session.startedAt,
                        exerciseName: snapshot.currentPerformance?.exerciseName,
                        performanceOrder: snapshot.currentPerformance?.order,
                        performanceCount: snapshot.performances.count,
                        currentSetID: snapshot.currentSet?.id,
                        sets: snapshot.currentPerformanceSets,
                        targetText: targetText,
                        effortSide: snapshot.currentEffort?.side ?? .none,
                        isAutomaticDuration: isAutomaticDuration,
                        remainingDurationSeconds: remainingDurationSeconds,
                        durationDeadlineAt: snapshot.session.phaseDeadlineAt,
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
                } else if let snapshot {
                    compactContent(
                        snapshot: snapshot,
                        isLandscape: proxy.size.width > proxy.size.height
                    )
                } else {
                    snapshotUnavailableContent
                }
            }
        }
        .navigationBarBackButtonHidden(snapshot?.session.status == .active)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: coordinator.recordingFailure?.id) {
            if let failure = coordinator.recordingFailure {
                presentRecordingError(failure.message)
            }
        }
        .task(id: sessionID) {
            await refreshSnapshot()
            guard let session = fetchSession() else { return }
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
                    await refreshSnapshot()
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
            guard let snapshot else { return }
            await WorkoutSystemProjectionCoordinator.shared.update(
                sessionID: snapshot.session.id,
                status: snapshot.session.status,
                guidedPhase: snapshot.session.guidedPhase,
                restTargetEndAt: snapshot.session.restTargetEndAt,
                completedSetCount: snapshot.completedSetCount,
                totalSetCount: snapshot.sets.count
            )
        }
        .task(id: snapshot?.session.currentEffortID) {
            guard isCoordinatorActivated else { return }
            await coordinator.preflightAutomaticRecording(in: modelContext)
        }
        .task(id: timelineKey) {
            await advanceTimelineAtDeadline()
        }
        .onDisappear {
            isCoordinatorActivated = false
            snapshotGeneration += 1
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
        .onChange(of: snapshot?.session.currentEffortID, initial: true) {
            effortCompletionErrorMessage = nil
            actualReps = (snapshot?.currentEffort?.actualReps
                ?? snapshot?.currentEffort?.plannedReps).map(String.init) ?? ""
            actualDuration = (snapshot?.currentEffort?.actualDurationSeconds
                ?? snapshot?.currentEffort?.plannedDurationSeconds).map(String.init)
                ?? ""
            actualWeight = (snapshot?.currentEffort?.actualWeightKG
                ?? snapshot?.currentEffort?.plannedWeightKG).map {
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
        .onChange(of: snapshot?.session.guidedPhaseRaw) {
            guard let snapshot else { return }
            var next = presentation
            next.phaseChanged(
                snapshot.session.guidedPhase,
                expandForRecording: shouldCaptureCurrentEffort(snapshot)
            )
            #if DEBUG
                if snapshot.session.guidedPhase == .setInProgress,
                   ProcessInfo.processInfo.environment[
                       "SOMA_GUIDED_CAPTURE_PREVIEW"
                   ] == "1"
                {
                    next.expand()
                }
            #endif
            presentation = next
            if snapshot.session.guidedPhase == .sessionReview
                || snapshot.session.guidedPhase == .completed
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
                targetKind: snapshot?.currentEffort?.targetKind ?? .repetitions,
                side: snapshot?.currentEffort?.side ?? .none,
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
                    await refreshSnapshot()
                    finalizeSessionAndShare()
                }
            }
            Button("继续训练", role: .cancel) {}
        }
        .sheet(isPresented: $showsReplacement) {
            NavigationStack {
                GuidedExerciseReplacementPicker(
                    sessionID: sessionID, onConfirm: replaceCurrentExercise
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

    private var snapshotUnavailableContent: some View {
        ContentUnavailableView {
            Label("训练暂时无法显示", systemImage: "exclamationmark.triangle")
        } description: {
            Text(snapshotErrorMessage ?? "正在载入训练…")
        } actions: {
            if snapshotErrorMessage != nil {
                Button("重试") { Task { await refreshSnapshot() } }
                Button("退出") { dismiss() }
            } else {
                ProgressView()
            }
        }
    }

    private func compactContent(
        snapshot: GuidedWorkoutScreenSnapshot,
        isLandscape: Bool
    ) -> some View {
        VStack(spacing: 0) {
            GuidedWorkoutChrome(
                sessionStartedAt: snapshot.session.startedAt,
                sessionStatus: snapshot.session.status,
                completedExerciseCount: snapshot.completedExerciseCount,
                exerciseCount: snapshot.performances.count,
                progressExercises: snapshot.progressExercises,
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

            phaseContent(snapshot: snapshot, isLandscape: isLandscape)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func phaseContent(
        snapshot: GuidedWorkoutScreenSnapshot,
        isLandscape: Bool
    ) -> some View {
        if snapshot.session.status == .paused {
            GuidedPausedView(onResume: pauseOrResume)
        } else {
            switch snapshot.session.guidedPhase {
            case .ready:
                ProgressView("准备训练…")
            case .exerciseIntroduction:
                GuidedExerciseIntroductionView(
                    exerciseName: snapshot.currentPerformance?.exerciseName,
                    artwork: snapshot.currentPerformance?.artwork
                        ?? BundledExerciseCatalog.fallbackActionIllustration,
                    coachingNotes: snapshot.currentPerformance?.coachingNotes,
                    camera: phasePictureInPictureCamera,
                    isLandscape: isLandscape,
                    cameraErrorMessage: coordinator.recordingErrorMessage,
                    onPrepare: prepareCurrentSet,
                    onReplace: { showsReplacement = true },
                    onSkip: skipCurrentExercise
                )
            case .preSetCountdown:
                GuidedSetCountdownView(
                    targetText: targetText,
                    phaseStartedAt: snapshot.session.phaseStartedAt,
                    deadlineAt: snapshot.session.phaseDeadlineAt,
                    camera: phasePictureInPictureCamera,
                    isLandscape: isLandscape,
                    cameraErrorMessage: coordinator.recordingErrorMessage,
                    onTick: coordinator.announceCountdown,
                    onFinished: beginCurrentSetAfterCountdown
                )
            case .setInProgress:
                GuidedCompactSetView(
                    camera: camera,
                    artwork: snapshot.currentPerformance?.artwork
                        ?? BundledExerciseCatalog.fallbackActionIllustration,
                    exerciseName: snapshot.currentPerformance?.exerciseName,
                    performanceOrder: snapshot.currentPerformance?.order,
                    performanceCount: snapshot.performances.count,
                    setKind: snapshot.currentSet?.kind,
                    targetText: targetText,
                    effortSide: snapshot.currentEffort?.side ?? .none,
                    isAutomaticDuration: isAutomaticDuration,
                    remainingDurationSeconds: remainingDurationSeconds,
                    durationDeadlineAt: snapshot.session.phaseDeadlineAt,
                    completionErrorMessage: effortCompletionErrorMessage,
                    coachingNote: coachingNote,
                    isLandscape: isLandscape,
                    showsCamera: showsCompactCamera,
                    isRecording: coordinator.recordingSetID == snapshot.currentSet?.id,
                    isStartingRecording: coordinator.isStartingRecording,
                    isCompletingEffort: coordinator
                        .isCompletingCurrentEffort,
                    canStartRecording: coordinator.recordingSetID == nil
                        || coordinator.recordingSetID == snapshot.currentSet?.id,
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
                    effortSide: snapshot.currentEffort?.side ?? .none,
                    isCompletingEffort: coordinator
                        .isCompletingCurrentEffort,
                    onCompleted: completeCurrentSet,
                    onRedo: redoCurrentSet,
                    onSkip: skipCurrentSet
                )
            case .resting:
                GuidedRestView(
                    nextTargetText: targetText,
                    nextEffortSide: snapshot.currentEffort?.side ?? .none,
                    remainingSeconds: {
                        guard let target = snapshot.session.restTargetEndAt else {
                            return 0
                        }
                        let reference = snapshot.session.status == .paused
                            ? snapshot.session.phaseStartedAt ?? .now
                            : .now
                        return max(Int(ceil(target.timeIntervalSince(reference))), 0)
                    },
                    isActive: snapshot.session.status == .active,
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
        if let effort = snapshot?.currentEffort, effort.side != .none {
            tokens.append(WorkoutPrescriptionFormatter.sideName(effort.side))
        }
        if let weight {
            tokens.append(weight == 0 ? "自重" : "\(weight.formatted()) kg")
        }
        switch snapshot?.currentEffort?.targetKind
            ?? snapshot?.currentSet?.plannedTargetKind
        {
        case .duration:
            if let remainingDurationSeconds,
               snapshot?.session.guidedPhase == .setInProgress
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
        snapshot?.currentEffort?.targetKind == .duration
    }

    private var remainingDurationSeconds: Int? {
        guard snapshot?.session.guidedPhase == .setInProgress,
              snapshot?.currentEffort?.targetKind == .duration,
              let deadline = snapshot?.session.phaseDeadlineAt
        else { return nil }
        return max(Int(ceil(deadline.timeIntervalSinceNow)), 0)
    }

    private var coachingNote: String {
        let note = snapshot?.currentPerformance?.coachingNotes
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
            phase: snapshot?.session.guidedPhase ?? .ready,
            cameraState: camera.state,
            isStarting: coordinator.isStartingRecording,
            sessionIsActive: snapshot?.session.status == .active,
            isCaptureTarget: snapshot.map(shouldCaptureCurrentEffort) ?? false
        )
    }

    private func shouldCaptureCurrentEffort(
        _ snapshot: GuidedWorkoutScreenSnapshot
    ) -> Bool {
        if coordinator.recordingSetID != nil
            || coordinator.isStartingRecording
            || coordinator.manualRecordingQueued
        {
            return true
        }
        guard !coordinator.automaticRecordingPaused,
              snapshot.session.status == .active
              || snapshot.session.status == .paused,
              let performance = snapshot.currentPerformance
        else { return false }

        func shouldRecord(
            set: GuidedWorkoutSetSnapshot,
            effort: GuidedWorkoutEffortSnapshot
        ) -> Bool {
            guard effort.recordedVideoPath == nil else { return false }
            if snapshot.session.autoRecordingPolicy == .everySet {
                return true
            }
            guard snapshot.session.autoRecordingPolicy == .enabled,
                  let prescription = performance.prescription
            else { return false }
            let firstWorkingOrder = prescription.plannedSets
                .filter { $0.kind == .working }
                .min { $0.order < $1.order }?.order
            return set.kind == .working
                && set.order == (
                    firstWorkingOrder
                        ?? (prescription.firstSetIsWarmup ? 2 : 1)
                )
        }

        if let set = snapshot.currentSet,
           let effort = snapshot.currentEffort,
           shouldRecord(set: set, effort: effort)
        {
            return true
        }
        guard snapshot.session.guidedPhase == .exerciseIntroduction
            || snapshot.session.guidedPhase == .preSetCountdown
        else { return false }
        for set in snapshot.currentPerformanceSets {
            for effort in snapshot.efforts
                where effort.workoutSetID == set.id
                && (effort.status == .pending || effort.status == .inProgress)
            {
                if shouldRecord(set: set, effort: effort) {
                    return true
                }
            }
        }
        return false
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
        if snapshot?.session.status == .paused {
            run { try coordinator.resume(in: modelContext) }
        } else {
            run { try await coordinator.pause(in: modelContext) }
        }
    }

    private func prepareCurrentSet() {
        run { try coordinator.prepareCurrentSet(in: modelContext) }
    }

    @MainActor
    private func beginCurrentSetAfterCountdown() async {
        guard snapshot?.session.guidedPhase == .preSetCountdown else { return }
        if snapshot.map(shouldCaptureCurrentEffort) == true {
            var next = presentation
            next.expand()
            presentation = next
        }
        do {
            try await coordinator.beginCurrentSet(
                in: modelContext,
                afterPhaseTransition: refreshSnapshot
            )
            await refreshSnapshot()
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
                await refreshSnapshot()
            } catch {
                effortCompletionErrorMessage = AppErrorMessage.message(for: error, operation: .save)
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
            Task { await refreshSnapshot() }
        } catch {
            presentOperationError(error)
        }
    }

    @MainActor
    private func advanceTimelineAtDeadline() async {
        guard let session = snapshot?.session,
              session.status == .active,
              let deadline = session.phaseDeadlineAt
        else { return }
        let revision = session.transitionRevision
        do {
            let delay = max(deadline.timeIntervalSinceNow, 0)
            try await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            try await coordinator.advanceTimelineIfDue(
                expectedRevision: revision,
                in: modelContext,
                afterPhaseTransition: refreshSnapshot
            )
            await refreshSnapshot()
        } catch is CancellationError {
            return
        } catch {
            if session.guidedPhase == .setInProgress,
               snapshot?.currentEffort?.targetKind == .duration
            {
                effortCompletionErrorMessage = AppErrorMessage.message(for: error, operation: .save)
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
        run { try coordinator.adjustRest(by: seconds, in: modelContext) }
    }

    private func finishRest() {
        run { try coordinator.finishRest(in: modelContext) }
    }

    private func finalizeSessionAndShare() {
        guard !isFinalizingSession, shareModel == nil else { return }
        isFinalizingSession = true
        finalizationState = .saving
        Task {
            do {
                guard var session = fetchSession() else {
                    throw GuidedWorkoutSnapshotError.missingSession
                }
                if session.status == .active {
                    try coordinator.complete(in: modelContext)
                    guard let reloaded = fetchSession() else {
                        throw GuidedWorkoutSnapshotError.missingSession
                    }
                    session = reloaded
                }
                await WorkoutSystemProjectionCoordinator.shared.end(
                    sessionID: session.id,
                    completedSetCount: snapshot?.completedSetCount ?? 0,
                    totalSetCount: snapshot?.sets.count ?? 0
                )
                shareModel = WorkoutSharePosterBuilder.makeModel(
                    session: session,
                    in: modelContext
                )
            } catch {
                isFinalizingSession = false
                finalizationState = .failed(AppErrorMessage.message(for: error, operation: .general))
                presentOperationError(error)
            }
        }
    }

    private func replaceCurrentExercise(
        with exercise: ExerciseDefinition,
        prescription: TemplateExercisePrescription
    ) throws {
        try coordinator.replaceCurrentExercise(
            with: exercise, prescription: prescription, in: modelContext
        )
        showsReplacement = false
        Task { await refreshSnapshot() }
    }

    private func run(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        Task {
            do {
                try await operation()
                await refreshSnapshot()
            } catch {
                presentOperationError(error)
            }
        }
    }

    private func fetchSession() -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    @MainActor
    private func refreshSnapshot() async {
        snapshotGeneration += 1
        let generation = snapshotGeneration
        do {
            let loaded = try GuidedWorkoutScreenSnapshotLoader.load(
                sessionID: sessionID,
                from: modelContext.container
            )
            guard !Task.isCancelled, generation == snapshotGeneration else {
                return
            }
            snapshot = loaded
            snapshotErrorMessage = nil
        } catch {
            guard !Task.isCancelled, generation == snapshotGeneration else {
                return
            }
            snapshotErrorMessage = AppErrorMessage.message(for: error, operation: .load)
            if snapshot != nil {
                presentedAlert = GuidedWorkoutAlertItem(
                    kind: .operation,
                    message: "训练状态刷新失败，已保留上一次画面。\(AppErrorMessage.message(for: error, operation: .general))"
                )
            }
        }
    }

    private func presentOperationError(_ error: Error) {
        presentedAlert = GuidedWorkoutAlertItem(
            kind: .operation,
            message: AppErrorMessage.message(for: error, operation: .general)
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
