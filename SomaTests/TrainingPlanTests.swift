@testable import Soma
import SwiftData
import XCTest

final class TrainingPlanTests: XCTestCase {
    @MainActor
    func testGUIProgramCreationUsesStableIDsAndKeepsMissingValuesEmpty() throws {
        let (context, defaults) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suite(defaults)) }
        let squat = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "杠铃深蹲",
            in: context
        )
        let row = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "坐姿划船",
            in: context
        )

        let program = try TrainingPlanStore.createProgram(
            name: "全身训练",
            goal: "保持规律训练",
            templateName: "全身训练",
            scheduleHint: "周末",
            prescriptions: [
                TemplateExercisePrescription(
                    exerciseID: row.id,
                    exerciseName: row.canonicalName,
                    order: 1,
                    targetSets: 3,
                    targetReps: 10,
                    targetRestSeconds: 90
                ),
                TemplateExercisePrescription(
                    exerciseID: squat.id,
                    exerciseName: squat.canonicalName,
                    order: 2,
                    firstSetIsWarmup: true
                )
            ],
            source: "gui",
            in: context
        )

        let version = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WorkoutTemplateVersion>())
                .first { $0.id == program.currentTemplateVersionID }
        )
        let values = TrainingPlanStore.prescriptions(
            for: version,
            in: context
        )

        XCTAssertEqual(program.goal, "保持规律训练")
        XCTAssertEqual(version.source, "gui")
        XCTAssertEqual(values.map(\.exerciseID), [row.id, squat.id])
        XCTAssertEqual(values.map(\.order), [1, 2])
        XCTAssertEqual(values.first?.targetSets, 3)
        XCTAssertNil(values.last?.targetSets)
        XCTAssertNil(values.last?.targetReps)
        XCTAssertNil(values.last?.targetWeightKG)
        XCTAssertNil(values.last?.targetRestSeconds)
        XCTAssertTrue(values.last?.firstSetIsWarmup == true)
    }

    @MainActor
    func testStartingSessionFreezesVersionAndCreatesOrderedSets() throws {
        let (context, defaults) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suite(defaults)) }
        let squat = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "杠铃前蹲",
            in: context
        )
        let press = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "单侧哑铃卧推",
            in: context
        )
        let program = try TrainingPlanStore.createProgram(
            name: "力量 A/B",
            templateName: "训练 A",
            prescriptions: [
                prescription(
                    exercise: squat,
                    order: 1,
                    sets: 3,
                    warmup: true
                ),
                prescription(exercise: press, order: 2, sets: 2)
            ],
            in: context
        )

        let session = try TrainingPlanStore.startSession(
            program: program,
            autoRecording: true,
            in: context
        )
        let originalSnapshot = session.prescriptionSnapshot

        _ = try TrainingPlanStore.createNextVersion(
            for: program,
            name: "训练 A 调整",
            scheduleHint: "周一",
            prescriptions: [
                prescription(exercise: press, order: 1, sets: 4)
            ],
            in: context
        )

        XCTAssertEqual(session.prescriptionSnapshot, originalSnapshot)
        XCTAssertEqual(session.sourceTemplateVersion, 1)
        XCTAssertEqual(session.programID, program.id)
        XCTAssertEqual(session.programNameSnapshot, "力量 A/B")
        XCTAssertEqual(
            TrainingPlanStore.programSourceLabel(for: session),
            "力量 A/B · v1"
        )
        let nextVersion = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WorkoutTemplateVersion>())
                .first { $0.version == 2 && $0.programID == program.id }
        )
        XCTAssertEqual(nextVersion.changeSummary?.contains("移除") == true
            || nextVersion.changeSummary?.contains("单侧哑铃卧推") == true, true)
        let performances = try context.fetch(FetchDescriptor<ExercisePerformance>())
            .filter { $0.sessionID == session.id }
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
            .filter { performances.map(\.id).contains($0.performanceID) }
        XCTAssertEqual(performances.count, 2)
        XCTAssertEqual(sets.count, 5)
        let squatPerformance = try XCTUnwrap(
            performances.first { $0.exerciseID == squat.id }
        )
        let squatSets = sets.filter { $0.performanceID == squatPerformance.id }
            .sorted { $0.order < $1.order }
        XCTAssertEqual(squatSets.first?.kind, .warmup)
        XCTAssertEqual(squatSets.dropFirst().first?.kind, .working)
    }

    @MainActor
    func testReadinessReportsRecordingGapWithoutBlockingStart() throws {
        let (context, defaults) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suite(defaults)) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "罗马尼亚硬拉",
            in: context
        )
        let values = [
            prescription(
                exercise: exercise,
                order: 1,
                sets: 1,
                warmup: true
            )
        ]

        let issues = TrainingPlanStore.readiness(
            prescriptions: values,
            autoRecording: true,
            in: context
        )

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.severity, .warning)
        let program = try TrainingPlanStore.createProgram(
            name: "后链",
            templateName: "后链",
            prescriptions: values,
            in: context
        )
        XCTAssertNoThrow(
            try TrainingPlanStore.startSession(
                program: program,
                autoRecording: true,
                in: context
            )
        )
    }

    @MainActor
    func testSummaryUsesOnlyCompletedActualValues() throws {
        let (context, defaults) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suite(defaults)) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "杯式深蹲",
            in: context
        )
        let program = try TrainingPlanStore.createProgram(
            name: "下肢",
            templateName: "下肢",
            prescriptions: [
                prescription(exercise: exercise, order: 1, sets: 3)
            ],
            in: context
        )
        let session = try TrainingPlanStore.startSession(
            program: program,
            in: context
        )
        let performance = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ExercisePerformance>()).first
        )
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
            .filter { $0.performanceID == performance.id }
            .sorted { $0.order < $1.order }
        sets[0].actualReps = 8
        sets[0].actualWeightKG = 20
        sets[0].status = .completed
        sets[1].actualReps = 8
        sets[1].actualWeightKG = nil
        sets[1].status = .completed
        sets[2].status = .skipped
        performance.status = .completed
        try context.save()

        let summary = TrainingPlanStore.summary(
            for: session.id,
            in: context
        )

        XCTAssertEqual(summary.completedSets, 2)
        XCTAssertEqual(summary.skippedSets, 1)
        XCTAssertEqual(summary.completedVolume, 160)
        XCTAssertEqual(summary.exerciseCount, 1)

        let query = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .queryUserData,
                arguments: AgentToolArguments(
                    scope: "sessions",
                    sessionID: session.id.uuidString
                )
            ),
            sourceText: "",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        XCTAssertTrue(query.ok)
        XCTAssertTrue(query.observation.contains(session.id.uuidString))
        XCTAssertTrue(query.observation.contains("杯式深蹲：2组"))
        XCTAssertTrue(query.observation.contains("20kg×8次"))
    }

    @MainActor
    func testSummaryIncludesDurationVideosAndDeleteRemovesSessionGraph() throws {
        let (context, defaults) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suite(defaults)) }
        let path = try MediaStore.saveRestoredMedia(
            Data("虚构带练录像".utf8),
            fileExtension: "mov"
        )
        let startedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "引体向上",
            in: context
        )
        let prescription = prescription(
            exercise: exercise,
            order: 1,
            sets: 1
        )
        let session = WorkoutSession(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(125),
            prescriptionSnapshot: [prescription],
            status: .completed,
            guidedPhase: .completed
        )
        let performance = ExercisePerformance(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            prescriptionSnapshot: prescription,
            status: .completed,
            activeVideoPath: path
        )
        let set = WorkoutSet(
            performanceID: performance.id,
            order: 1,
            actualReps: 5,
            actualWeightKG: 0,
            status: .completed,
            completedAt: startedAt.addingTimeInterval(100),
            recordedVideoPath: path
        )
        let analysis = PerformanceAnalysis(
            performanceID: performance.id,
            sourceMediaPath: path,
            inputFingerprint: "fixture",
            evidence: "虚构证据",
            limitations: "单一视角",
            feedback: "保持稳定"
        )
        context.insert(session)
        context.insert(performance)
        context.insert(set)
        context.insert(analysis)
        try context.save()

        let summary = TrainingPlanStore.summary(
            for: session.id,
            in: context
        )
        XCTAssertEqual(summary.durationSeconds, 125)
        XCTAssertEqual(summary.recordedVideoCount, 1)
        XCTAssertEqual(summary.exercises.first?.name, "引体向上")
        XCTAssertEqual(summary.exercises.first?.completedSets, 1)

        try TrainingPlanStore.deleteSession(session, in: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ExercisePerformance>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSet>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PerformanceAnalysis>()).isEmpty)
        XCTAssertNil(MediaStore.url(at: path))
    }

    @MainActor
    func testValidationDoesNotInventMissingPrescriptionValues() throws {
        let (context, defaults) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suite(defaults)) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "俯卧撑",
            in: context
        )
        let program = try TrainingPlanStore.createProgram(
            name: "自重",
            templateName: "自重",
            prescriptions: [
                TemplateExercisePrescription(
                    exerciseID: exercise.id,
                    exerciseName: exercise.canonicalName,
                    order: 1
                )
            ],
            in: context
        )

        let session = try TrainingPlanStore.startSession(
            program: program,
            in: context
        )

        XCTAssertNil(session.prescriptionSnapshot.first?.targetSets)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<WorkoutSet>()).isEmpty
        )
    }

    @MainActor
    func testAgentToolsCreateVersionQueryAndArchivePlan() throws {
        let (context, defaults) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suite(defaults)) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "站姿推举",
            in: context
        )
        let item = AgentTemplateExerciseInput(
            exerciseID: exercise.id.uuidString,
            order: 1,
            targetSets: 3,
            targetReps: 6,
            targetWeightKG: 25,
            targetRestSeconds: 120,
            firstSetIsWarmup: true
        )
        let create = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .createTrainingProgram,
                arguments: AgentToolArguments(
                    programName: "推举计划",
                    goal: "提升力量",
                    templateName: "推举日",
                    templateExercises: [item]
                )
            ),
            sourceText: "帮我建立推举计划",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let program = try XCTUnwrap(
            try context.fetch(FetchDescriptor<TrainingProgram>()).first
        )
        let update = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .updateWorkoutTemplate,
                arguments: AgentToolArguments(
                    programID: program.id.uuidString,
                    templateName: "推举日调整",
                    templateExercises: [item]
                )
            ),
            sourceText: "调整一下",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let query = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .queryUserData,
                arguments: AgentToolArguments(scope: "programs")
            ),
            sourceText: "",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let archive = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .archiveTrainingProgram,
                arguments: AgentToolArguments(
                    programID: program.id.uuidString
                )
            ),
            sourceText: "归档这个计划",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        XCTAssertTrue(create.ok)
        XCTAssertTrue(update.ok)
        XCTAssertTrue(query.observation.contains(program.id.uuidString))
        XCTAssertTrue(archive.ok)
        XCTAssertEqual(program.status, .archived)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<WorkoutTemplateVersion>()).count,
            2
        )
    }

    @MainActor
    func testAgentToolsListAndStartGuidedWorkout() throws {
        let (context, defaults) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suite(defaults)) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "杠铃深蹲",
            in: context
        )
        let program = try TrainingPlanStore.createProgram(
            name: "深蹲训练",
            templateName: "下肢日",
            prescriptions: [
                TemplateExercisePrescription(
                    exerciseID: exercise.id,
                    exerciseName: exercise.canonicalName,
                    order: 1,
                    targetSets: 3,
                    targetReps: 5
                )
            ],
            in: context
        )
        let listed = ConversationRecorder.executeAgentTool(
            AgentToolCall(name: .listTrainingPrograms, arguments: .init()),
            sourceText: "我有哪些计划？",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        XCTAssertTrue(listed.ok)
        XCTAssertTrue(listed.observation.contains(program.id.uuidString))

        if let route = SomaCaptureRouter.shared.pendingWorkoutSession {
            SomaCaptureRouter.shared.clearWorkoutSession(route.id)
        }
        let started = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .startGuidedWorkout,
                arguments: .init(
                    programID: program.id.uuidString,
                    autoRecordingPolicy: "every_set"
                )
            ),
            sourceText: "开始这个计划带练",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let session = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WorkoutSession>()).first
        )
        XCTAssertTrue(started.ok)
        XCTAssertEqual(session.autoRecordingPolicy, .everySet)
        XCTAssertEqual(SomaCaptureRouter.shared.pendingWorkoutSession?.sessionID, session.id)
        if let route = SomaCaptureRouter.shared.pendingWorkoutSession {
            SomaCaptureRouter.shared.clearWorkoutSession(route.id)
        }

        let detail = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .getTrainingProgram,
                arguments: .init(programID: program.id.uuidString)
            ),
            sourceText: "查看这个计划详情",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        XCTAssertTrue(detail.ok)
        XCTAssertTrue(detail.observation.contains("杠铃深蹲"))

        let deleted = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .deleteTrainingProgram,
                arguments: .init(programID: program.id.uuidString)
            ),
            sourceText: "永久删除这个计划",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        XCTAssertTrue(deleted.ok)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TrainingProgram>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
    }

    @MainActor
    func testPerformanceReviewToolBindsEvidenceToSourceJobIdempotently() throws {
        let (context, defaults) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suite(defaults)) }
        let path = try MediaStore.saveRestoredMedia(
            Data("虚构训练视频字节".utf8),
            fileExtension: "mov"
        )
        defer { _ = MediaStore.removeStoredFile(at: path) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "哑铃卧推",
            in: context
        )
        let session = WorkoutSession(
            prescriptionSnapshot: [],
            status: .completed,
            guidedPhase: .completed
        )
        let performance = ExercisePerformance(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: 1,
            prescriptionSnapshot: TemplateExercisePrescription(
                exerciseID: exercise.id,
                exerciseName: exercise.canonicalName,
                order: 1
            ),
            status: .completed,
            activeVideoPath: path
        )
        let turnID = UUID()
        let job = AgentJob(
            turnID: turnID,
            sessionID: UUID(),
            userMessageID: UUID(),
            dataSpace: .personal,
            backend: .local,
            userText: "复盘虚构视频",
            mediaAttachments: [],
            contextSnapshot: .init(
                structuredContext: "",
                includeLocation: false
            )
        )
        context.insert(exercise)
        context.insert(session)
        context.insert(performance)
        context.insert(job)
        try context.save()
        let fingerprint = try TrainingIntelligenceService
            .performanceFingerprint(for: performance)
        let arguments = AgentToolArguments(
            feedback: "保持肩胛稳定",
            performanceID: performance.id.uuidString,
            inputFingerprint: fingerprint,
            evidence: "下降阶段躯干保持稳定",
            limitations: "只有正面视角"
        )

        let first = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .recordPerformanceAnalysis,
                arguments: arguments
            ),
            sourceText: "复盘",
            sourceTurnID: turnID,
            mediaKind: .video,
            mediaPath: path,
            in: context
        )
        let replay = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .recordPerformanceAnalysis,
                arguments: arguments
            ),
            sourceText: "复盘",
            sourceTurnID: turnID,
            mediaKind: .video,
            mediaPath: path,
            in: context
        )
        let analyses = try context.fetch(
            FetchDescriptor<PerformanceAnalysis>()
        )

        XCTAssertTrue(first.ok)
        XCTAssertTrue(replay.ok)
        XCTAssertEqual(analyses.count, 1)
        XCTAssertEqual(analyses.first?.sourceJobID, job.id)
        XCTAssertEqual(analyses.first?.inputFingerprint, fingerprint)
    }

    @MainActor
    func testStatisticsCombineLegacyRecordsAndCompletedSetsOnce() throws {
        let (context, defaults) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suite(defaults)) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "杠铃硬拉",
            in: context
        )
        let legacy = WorkoutEntry(
            date: Date(timeIntervalSince1970: 1000),
            exercise: exercise.canonicalName,
            exerciseID: exercise.id,
            sets: 2,
            reps: 5,
            weight: 40
        )
        context.insert(legacy)
        let program = try TrainingPlanStore.createProgram(
            name: "后链",
            templateName: "硬拉日",
            prescriptions: [
                prescription(exercise: exercise, order: 1, sets: 2)
            ],
            in: context
        )
        let session = try TrainingPlanStore.startSession(
            program: program,
            in: context
        )
        session.startedAt = Date(timeIntervalSince1970: 1000)
        session.status = .completed
        let performance = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ExercisePerformance>()).first
        )
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
            .sorted { $0.order < $1.order }
        sets[0].actualReps = 5
        sets[0].actualWeightKG = 40
        sets[0].status = .completed
        sets[1].actualReps = 5
        sets[1].actualWeightKG = 40
        sets[1].status = .pending
        try context.save()

        let points = TrainingVolumeAnalytics.dailyPoints(
            from: [legacy],
            sessions: [session],
            performances: [performance],
            sets: sets,
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].volume, 600)
    }

    @MainActor
    func testExerciseContentRevisionsAreVersionedAndRestorable() throws {
        let (context, defaults) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suite(defaults)) }
        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "保加利亚分腿蹲",
            in: context
        )
        let first = ExerciseContentRevision(
            source: .ai,
            coachingNotes: "保持躯干稳定。",
            primaryMuscles: ["股四头肌"],
            secondaryMuscles: ["臀大肌"],
            movementPatterns: ["蹲"]
        )
        exercise.apply(first)
        exercise.apply(ExerciseContentRevision(
            source: .manual,
            coachingNotes: "用户修订。",
            primaryMuscles: ["臀大肌"],
            secondaryMuscles: [],
            movementPatterns: ["单腿蹲"]
        ))
        try context.save()

        XCTAssertEqual(exercise.contentRevisions.count, 2)
        XCTAssertEqual(exercise.contentRevisions.first, first)
        XCTAssertEqual(exercise.coachingNotes, "用户修订。")
    }

    @MainActor
    func testLegacySessionResolvesPlanLabelFromTemplateFamily() throws {
        let (context, defaults) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suite(defaults)) }
        let squat = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "高脚杯深蹲",
            in: context
        )
        let program = try TrainingPlanStore.createProgram(
            name: "下肢力量",
            templateName: "腿日",
            prescriptions: [
                prescription(exercise: squat, order: 1, sets: 3)
            ],
            in: context
        )
        let version = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WorkoutTemplateVersion>())
                .first { $0.id == program.currentTemplateVersionID }
        )

        // Pre-snapshot sessions only kept the template family link.
        let legacy = WorkoutSession(
            sourceTemplateFamilyID: version.familyID,
            sourceTemplateVersion: version.version,
            prescriptionSnapshot: TrainingPlanStore.prescriptions(
                for: version,
                in: context
            ),
            status: .completed
        )
        context.insert(legacy)
        try context.save()

        XCTAssertEqual(
            TrainingPlanStore.programSourceLabel(for: legacy, in: context),
            "下肢力量 · v1"
        )
        XCTAssertTrue(
            TrainingPlanStore.backfillProgramSource(for: legacy, in: context)
        )
        try context.save()
        XCTAssertEqual(legacy.programID, program.id)
        XCTAssertEqual(legacy.programNameSnapshot, "下肢力量")
        XCTAssertEqual(
            TrainingPlanStore.programSourceLabel(for: legacy),
            "下肢力量 · v1"
        )
    }

    @MainActor
    func testOrphanSessionResolvesPlanLabelFromPrescriptionFingerprint() throws {
        let (context, defaults) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suite(defaults)) }
        let squat = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "箱式深蹲",
            in: context
        )
        let program = try TrainingPlanStore.createProgram(
            name: "基础力量训练",
            templateName: "组合 A",
            prescriptions: [
                prescription(exercise: squat, order: 1, sets: 4, warmup: true)
            ],
            in: context
        )
        let version = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WorkoutTemplateVersion>())
                .first { $0.id == program.currentTemplateVersionID }
        )
        let values = TrainingPlanStore.prescriptions(for: version, in: context)

        // Lost every plan link except the frozen prescription snapshot.
        let orphan = WorkoutSession(
            prescriptionSnapshot: values,
            status: .completed
        )
        context.insert(orphan)
        try context.save()

        XCTAssertEqual(
            TrainingPlanStore.programSourceLabel(for: orphan, in: context),
            "基础力量训练 · v1"
        )
    }

    @MainActor
    func testDeletingProgramKeepsPlanNameOnExistingSessions() throws {
        let (context, defaults) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suite(defaults)) }
        let row = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "坐姿划船",
            in: context
        )
        let program = try TrainingPlanStore.createProgram(
            name: "上肢拉力",
            templateName: "拉日",
            prescriptions: [
                prescription(exercise: row, order: 1, sets: 4)
            ],
            in: context
        )
        let session = try TrainingPlanStore.startSession(
            program: program,
            autoRecording: false,
            in: context
        )
        session.status = .completed
        try context.save()

        try TrainingPlanStore.deleteProgram(program, in: context)

        XCTAssertEqual(
            TrainingPlanStore.programSourceLabel(for: session),
            "上肢拉力 · v1"
        )
    }

    private func prescription(
        exercise: ExerciseDefinition,
        order: Int,
        sets: Int,
        warmup: Bool = false
    ) -> TemplateExercisePrescription {
        TemplateExercisePrescription(
            exerciseID: exercise.id,
            exerciseName: exercise.canonicalName,
            order: order,
            targetSets: sets,
            targetReps: 8,
            targetWeightKG: 20,
            targetRestSeconds: 90,
            firstSetIsWarmup: warmup
        )
    }

    @MainActor
    private func makeContext() throws -> (ModelContext, UserDefaults) {
        let name = "TrainingPlanTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.set(name, forKey: "test.suite")
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        return (ModelContext(spaces.personalContainer), defaults)
    }

    private func suite(_ defaults: UserDefaults) -> String {
        defaults.string(forKey: "test.suite") ?? ""
    }
}
