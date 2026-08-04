@testable import Soma
import SwiftData
import XCTest

final class ExerciseLibraryTests: XCTestCase {
    @MainActor
    func testBundledCatalogStaysSilentUntilUserExerciseIsCreated() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)

        ExerciseLibraryStore.activateBundledContent(in: context)

        XCTAssertGreaterThanOrEqual(BundledExerciseCatalog.entryCount, 40)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<ExerciseDefinition>()).isEmpty
        )
        XCTAssertTrue(ExerciseLibraryStore.nameReferences(in: context).isEmpty)
    }

    @MainActor
    func testCreatingKnownExerciseActivatesBundledContentOnlyForThatExercise() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)

        let squat = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "杠铃深蹲",
            in: context
        )

        XCTAssertFalse(squat.coachingNotes.isEmpty)
        XCTAssertEqual(squat.primaryMuscles, ["股四头肌", "臀大肌"])
        XCTAssertEqual(squat.actionIllustrations.count, 1)
        XCTAssertEqual(squat.actionIllustrations.first?.source, .bundled)
        XCTAssertEqual(squat.muscleMaps.count, 1)
        XCTAssertEqual(
            ExerciseLibraryStore.nameReferences(in: context).map(\.name),
            ["杠铃深蹲"]
        )
    }

    @MainActor
    func testBundledActivationFillsMissingFieldsWithoutOverwritingUserContent() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)
        let exercise = ExerciseDefinition(
            canonicalName: "高脚杯深蹲",
            coachingNotes: "我的提示",
            primaryMuscles: ["自定义主要肌群"]
        )
        context.insert(exercise)
        try context.save()

        ExerciseLibraryStore.activateBundledContent(in: context)

        XCTAssertEqual(exercise.coachingNotes, "我的提示")
        XCTAssertEqual(exercise.primaryMuscles, ["自定义主要肌群"])
        XCTAssertFalse(exercise.secondaryMuscles.isEmpty)
        XCTAssertEqual(exercise.actionIllustrations.count, 1)
        XCTAssertEqual(exercise.muscleMaps.count, 1)
    }

    @MainActor
    func testAmbiguousSquatAliasUsesBodyweightIllustrationNotBarbell() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)

        let exercise = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "深蹲",
            in: context
        )

        XCTAssertEqual(
            exercise.actionIllustrations.first?.resourceName,
            "soma_bodyweight_squat.png"
        )
    }

    @MainActor
    func testCatalogRefreshesItsOwnImageWithoutOverwritingUserImage() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)
        let exercise = ExerciseDefinition(canonicalName: "深蹲")
        let userImage = ExerciseImageReference(
            kind: .actionIllustration,
            source: .user,
            title: "我的动作图",
            localPath: "PrivateMedia/my-squat.jpg"
        )
        exercise.imageReferences = [
            ExerciseImageReference(
                kind: .actionIllustration,
                source: .bundled,
                title: "内置动作示意图",
                resourceName: "soma_barbell_squat.png",
                createdAt: .distantPast
            ),
            userImage
        ]
        context.insert(exercise)
        try context.save()

        ExerciseLibraryStore.activateBundledContent(in: context)

        XCTAssertTrue(exercise.imageReferences.contains(userImage))
        XCTAssertEqual(
            exercise.imageReferences.filter {
                $0.kind == .actionIllustration && $0.source == .bundled
            }.map(\.resourceName),
            ["soma_bodyweight_squat.png"]
        )
    }

    func testEveryCatalogResourceExistsInAppBundle() {
        for resourceName in BundledExerciseCatalog.resourceNames {
            XCTAssertNotNil(
                Bundle.main.url(forResource: resourceName, withExtension: nil),
                "Missing bundled exercise resource: \(resourceName)"
            )
        }
    }

    @MainActor
    func testListToolReturnsCompleteStableIDAndNamePairs() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)
        let squat = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "杠铃深蹲",
            in: context
        )
        let press = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "单侧哑铃卧推",
            in: context
        )

        let result = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .listExerciseNames,
                arguments: AgentToolArguments()
            ),
            sourceText: "",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.observation.contains(squat.id.uuidString))
        XCTAssertTrue(result.observation.contains(press.id.uuidString))
        XCTAssertTrue(result.observation.contains("杠铃深蹲"))
        XCTAssertTrue(result.observation.contains("单侧哑铃卧推"))
    }

    @MainActor
    func testRecordWorkoutUsesExistingIDOrCreatesOnlyFromExerciseName() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)
        let squat = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "杠铃深蹲",
            in: context
        )

        let existingResult = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .recordWorkout,
                arguments: AgentToolArguments(
                    exerciseID: squat.id.uuidString,
                    setEntries: [
                        AgentWorkoutSetInput(
                            reps: 5,
                            externalWeightKG: 60
                        )
                    ]
                )
            ),
            sourceText: "杠铃深蹲 60kg 5次",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )
        let newResult = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .recordWorkout,
                arguments: AgentToolArguments(
                    exerciseName: "单侧哑铃弓步前蹲",
                    setEntries: [
                        AgentWorkoutSetInput(
                            reps: 8,
                            externalWeightKG: 20
                        )
                    ]
                )
            ),
            sourceText: "单侧哑铃弓步前蹲",
            sourceDate: .now.addingTimeInterval(3600),
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        XCTAssertTrue(existingResult.ok)
        XCTAssertTrue(newResult.ok)
        let workouts = try context.fetch(FetchDescriptor<WorkoutEntry>())
        XCTAssertEqual(workouts.count, 2)
        XCTAssertTrue(workouts.contains { $0.exerciseID == squat.id })
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ExerciseDefinition>()).count,
            2
        )
    }

    @MainActor
    func testInvalidExerciseIDRequiresFreshListAndDoesNotWrite() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)
        let missingID = UUID()

        let result = ConversationRecorder.executeAgentTool(
            AgentToolCall(
                name: .recordWorkout,
                arguments: AgentToolArguments(
                    exerciseID: missingID.uuidString
                )
            ),
            sourceText: "训练",
            mediaKind: .none,
            mediaPath: nil,
            in: context
        )

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.observation.contains("重新读取动作列表"))
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutEntry>()).isEmpty)
    }

    @MainActor
    func testMergeAndUndoPreserveWorkoutHistory() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)
        let source = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "杠铃蹲",
            in: context
        )
        let target = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "杠铃深蹲",
            in: context
        )
        let workout = WorkoutEntry(
            exercise: source.canonicalName,
            exerciseID: source.id,
            sets: 4,
            reps: 5,
            weight: 60
        )
        let templateExercise = TemplateExercise(
            templateVersionID: UUID(),
            exerciseID: source.id,
            order: 1
        )
        let prescription = TemplateExercisePrescription(
            exerciseID: source.id,
            exerciseName: source.canonicalName,
            order: 1
        )
        let performance = ExercisePerformance(
            sessionID: UUID(),
            exerciseID: source.id,
            exerciseName: source.canonicalName,
            order: 1,
            prescriptionSnapshot: prescription
        )
        let analysis = PerformanceAnalysis(
            performanceID: performance.id,
            sourceMediaPath: "PrivateMedia/performance.mov",
            inputFingerprint: "fingerprint",
            evidence: "膝盖轨迹可见",
            limitations: "只有正面视角",
            feedback: "保持稳定"
        )
        let recommendation = RecommendationSnapshot(
            targetKind: "exercise",
            targetID: source.id,
            inputFingerprint: "exercise-fingerprint",
            advice: "保持当前负荷"
        )
        let sourceRevision = ExerciseContentRevision(
            source: .manual,
            coachingNotes: "保持躯干稳定",
            primaryMuscles: ["股四头肌"],
            secondaryMuscles: ["核心"],
            movementPatterns: ["蹲"]
        )
        source.apply(sourceRevision)
        let sourceVideo = MediaAttachmentReference(
            kind: .video,
            path: "PrivateMedia/source.mov"
        )
        let targetVideo = MediaAttachmentReference(
            kind: .video,
            path: "PrivateMedia/target.mov"
        )
        let guidance = ExerciseVideoSource(
            title: "授权示范",
            kind: .authorized,
            url: URL(string: "https://example.com/demo")
        )
        let sourceImage = ExerciseImageReference(
            kind: .actionIllustration,
            source: .generated,
            title: "来源动作图",
            localPath: "PrivateMedia/source-action.jpg"
        )
        let targetImage = ExerciseImageReference(
            kind: .actionIllustration,
            source: .user,
            title: "目标动作图",
            localPath: "PrivateMedia/target-action.jpg"
        )
        source.userDemoVideos = [sourceVideo]
        source.guidanceVideos = [guidance]
        source.imageReferences = [sourceImage]
        target.userDemoVideos = [targetVideo]
        target.imageReferences.append(targetImage)
        let targetImagesBeforeMerge = target.imageReferences
        context.insert(workout)
        context.insert(templateExercise)
        context.insert(performance)
        context.insert(analysis)
        context.insert(recommendation)
        try context.save()

        let record = try ExerciseLibraryStore.merge(
            source: source,
            into: target,
            in: context
        )

        XCTAssertTrue(source.isArchived)
        XCTAssertEqual(workout.exerciseID, target.id)
        XCTAssertEqual(workout.exercise, target.canonicalName)
        XCTAssertEqual(templateExercise.exerciseID, target.id)
        XCTAssertEqual(performance.exerciseID, target.id)
        XCTAssertEqual(performance.prescriptionSnapshot?.exerciseID, target.id)
        XCTAssertTrue(target.userDemoVideos.contains(sourceVideo))
        XCTAssertTrue(target.userDemoVideos.contains(targetVideo))
        XCTAssertTrue(target.guidanceVideos.contains(guidance))
        XCTAssertTrue(target.imageReferences.contains(sourceImage))
        XCTAssertTrue(target.imageReferences.contains(targetImage))
        XCTAssertTrue(source.imageReferences.isEmpty)
        XCTAssertTrue(source.userDemoVideos.isEmpty)
        XCTAssertEqual(analysis.performanceID, performance.id)
        XCTAssertEqual(recommendation.targetID, target.id)
        XCTAssertTrue(target.contentRevisions.contains {
            $0.id == sourceRevision.id
        })

        try ExerciseLibraryStore.undo(record, in: context)

        XCTAssertFalse(source.isArchived)
        XCTAssertNil(source.mergedIntoID)
        XCTAssertEqual(workout.exerciseID, source.id)
        XCTAssertEqual(workout.exercise, source.canonicalName)
        XCTAssertEqual(templateExercise.exerciseID, source.id)
        XCTAssertEqual(performance.exerciseID, source.id)
        XCTAssertEqual(performance.prescriptionSnapshot?.exerciseID, source.id)
        XCTAssertEqual(source.userDemoVideos, [sourceVideo])
        XCTAssertEqual(source.guidanceVideos, [guidance])
        XCTAssertEqual(source.imageReferences, [sourceImage])
        XCTAssertEqual(target.userDemoVideos, [targetVideo])
        XCTAssertEqual(target.imageReferences, targetImagesBeforeMerge)
        XCTAssertEqual(recommendation.targetID, source.id)
        XCTAssertFalse(target.contentRevisions.contains {
            $0.id == sourceRevision.id
        })
    }

    @MainActor
    func testLegacyMigrationOnlyGroupsExactNormalizedNames() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)
        context.insert(WorkoutEntry(exercise: "杠铃深蹲"))
        context.insert(WorkoutEntry(exercise: "杠铃深蹲 "))
        context.insert(WorkoutEntry(exercise: "杠铃前蹲"))
        try context.save()

        ExerciseLibraryStore.migrateLegacyWorkoutNames(in: context)

        let workouts = try context.fetch(FetchDescriptor<WorkoutEntry>())
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        XCTAssertEqual(definitions.count, 2)
        XCTAssertEqual(
            Set(
                workouts
                    .filter { $0.exercise == "杠铃深蹲" }
                    .compactMap(\.exerciseID)
            ).count,
            1
        )
        XCTAssertEqual(Set(workouts.compactMap(\.exerciseID)).count, 2)
    }

    @MainActor
    func testLinkedExercisePersistsIDWithoutCreatingUnknownNames() throws {
        let (spaces, defaults) = try makeSpaces()
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        let context = ModelContext(spaces.personalContainer)
        let squat = try ExerciseLibraryStore.resolveOrCreateExact(
            canonicalName: "杠铃深蹲",
            in: context
        )
        let known = WorkoutEntry(exercise: "杠铃深蹲 ")
        let unknown = WorkoutEntry(exercise: "从未见过的动作XYZ")
        context.insert(known)
        context.insert(unknown)
        try context.save()

        ExerciseLibraryStore.linkExistingExercises(
            for: [known, unknown],
            in: context
        )

        XCTAssertEqual(known.exerciseID, squat.id)
        XCTAssertEqual(known.exercise, "杠铃深蹲")
        XCTAssertNil(unknown.exerciseID)

        let created = try ExerciseLibraryStore.linkedExercise(
            for: unknown,
            in: context,
            persist: true,
            allowCreate: true
        )
        XCTAssertEqual(created?.canonicalName, "从未见过的动作XYZ")
        XCTAssertEqual(unknown.exerciseID, created?.id)
    }

    func testQuickFillUsesLatestRecordedCapacityWithoutInventingValues() {
        let workout = WorkoutEntry(
            exercise: "杠铃前蹲",
            setEntries: [
                WorkoutSetEvidence(reps: 5, externalWeightKG: 30),
                WorkoutSetEvidence(reps: 5, externalWeightKG: 30),
                WorkoutSetEvidence(reps: 5, externalWeightKG: 30),
                WorkoutSetEvidence(reps: 5, externalWeightKG: 30)
            ],
            restSeconds: 120
        )
        let incomplete = WorkoutEntry(
            exercise: "单侧哑铃卧推",
            sets: 3
        )

        XCTAssertEqual(
            ExerciseQuickFill.text(for: workout),
            "30kg × 5 × 4组，间歇 2min"
        )
        XCTAssertEqual(ExerciseQuickFill.text(for: incomplete), "3组")
    }

    func testQuickFillUsesCompletedGuidedSetsAndRecordedRest() {
        let performanceID = UUID()
        let completed = (1 ... 4).map { order in
            WorkoutSet(
                performanceID: performanceID,
                order: order,
                actualReps: 5,
                actualWeightKG: 30,
                actualRestSeconds: 120,
                status: .completed
            )
        }
        let pending = WorkoutSet(
            performanceID: performanceID,
            order: 5,
            plannedReps: 8,
            plannedWeightKG: 40,
            plannedRestSeconds: 180
        )

        XCTAssertEqual(
            ExerciseQuickFill.text(for: completed + [pending]),
            "30kg × 5 × 4组，间歇 2min"
        )
    }

    @MainActor
    private func makeSpaces() throws -> (DataSpaceController, UserDefaults) {
        let suite = "ExerciseLibraryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(suite, forKey: "test.suite")
        return (
            DataSpaceController(
                defaults: defaults,
                isStoredInMemoryOnly: true
            ),
            defaults
        )
    }

    private func defaultsSuite(_ defaults: UserDefaults) -> String {
        defaults.string(forKey: "test.suite") ?? ""
    }
}
