import Foundation
@testable import Soma
import SwiftData
import XCTest

private protocol ArchivedBusinessIDDTO {
    var id: UUID { get }
    var businessID: Int64? { get }
}

extension UserProfileDTO: ArchivedBusinessIDDTO {}
extension GymProfileDTO: ArchivedBusinessIDDTO {}
extension GymEquipmentDTO: ArchivedBusinessIDDTO {}
extension MealEntryDTO: ArchivedBusinessIDDTO {}
extension BodyEntryDTO: ArchivedBusinessIDDTO {}
extension WorkoutEntryDTO: ArchivedBusinessIDDTO {}
extension ExerciseDefinitionDTO: ArchivedBusinessIDDTO {}
extension ExerciseMergeRecordDTO: ArchivedBusinessIDDTO {}
extension TrainingProgramDTO: ArchivedBusinessIDDTO {}
extension WorkoutTemplateVersionDTO: ArchivedBusinessIDDTO {}
extension TemplateExerciseDTO: ArchivedBusinessIDDTO {}
extension TemplateSetPrescriptionDTO: ArchivedBusinessIDDTO {}
extension WorkoutSessionDTO: ArchivedBusinessIDDTO {}
extension ExercisePerformanceDTO: ArchivedBusinessIDDTO {}
extension WorkoutSetDTO: ArchivedBusinessIDDTO {}
extension WorkoutEffortDTO: ArchivedBusinessIDDTO {}
extension RecommendationSnapshotDTO: ArchivedBusinessIDDTO {}
extension PerformanceAnalysisDTO: ArchivedBusinessIDDTO {}

final class DataBackupServiceTests: XCTestCase {
    func testPBKDF2MatchesKnownSHA256Vector() throws {
        let derived = try DataBackupCrypto.deriveKeyData(
            password: "password",
            salt: Data("salt-salt-salt-1".utf8),
            iterations: 2
        )

        XCTAssertEqual(
            derived.map { String(format: "%02x", $0) }.joined(),
            "7270a491dc8fd1e7f86666f235aed04df51826daca0ecc9027c7f6bdb733acdc"
        )
    }

    func testAESGCMRejectsTamperedCiphertext() throws {
        let key = Data(repeating: 7, count: DataBackupCrypto.keyByteCount)
        let plaintext = Data("private-health-data".utf8)
        var encrypted = try DataBackupCrypto.seal(plaintext, keyData: key)
        encrypted[encrypted.startIndex] ^= 0x01

        XCTAssertThrowsError(try DataBackupCrypto.open(encrypted, keyData: key))
    }

    @MainActor
    func testBackupFingerprintIgnoresCaptureTimeButDetectsDataChange() throws {
        let snapshot = try DataArchiveTestSupport.makeSnapshot()
        var recaptured = snapshot
        recaptured.createdAt = snapshot.createdAt.addingTimeInterval(600)

        let originalFingerprint = try snapshot.contentFingerprint()
        let recapturedFingerprint = try recaptured.contentFingerprint()
        XCTAssertEqual(originalFingerprint, recapturedFingerprint)
        recaptured.meals[0].title = "修改后的午餐"
        let changedFingerprint = try recaptured.contentFingerprint()
        XCTAssertNotEqual(originalFingerprint, changedFingerprint)
    }

    @MainActor
    func testBackupIsEncryptedAndPreparesCompleteRestore() throws {
        let snapshot = try DataArchiveTestSupport.makeSnapshot()
        let root = try DataArchiveTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appending(path: "source.jpg")
        let exerciseImage = root.appending(path: "exercise.jpg")
        let video = root.appending(path: "source.mov")
        try Data("image-content".utf8).write(to: image)
        try Data("exercise-image-content".utf8).write(to: exerciseImage)
        try Data("video-content".utf8).write(to: video)
        let sources = [
            DataArchiveTestSupport.mealMediaPath: image,
            DataArchiveTestSupport.exerciseImagePath: exerciseImage,
            DataArchiveTestSupport.workoutMediaPath: video
        ]
        let credential = try makeCredential()

        let result = try DataBackupService.write(
            snapshot: snapshot,
            to: root,
            credential: credential,
            now: DataArchiveTestSupport.fixedDate,
            mediaURL: { sources[$0] }
        )

        let encryptedSnapshot = try Data(
            contentsOf: result.directoryURL.appending(
                path: DataBackupService.snapshotFilename
            )
        )
        XCTAssertFalse(
            String(data: encryptedSnapshot, encoding: .utf8)?
                .contains("测试午餐") ?? false
        )
        var savedMedia: [(Data, String)] = []
        let prepared = try DataBackupService.prepareRestore(
            from: root,
            password: "password",
            saveMedia: { data, ext in
                savedMedia.append((data, ext))
                return "PrivateMedia/restored-\(savedMedia.count).\(ext)"
            }
        )
        XCTAssertEqual(prepared.snapshot, snapshot)
        XCTAssertEqual(prepared.mediaPathMapping.count, 3)
        XCTAssertEqual(savedMedia.map(\.0), [
            Data("exercise-image-content".utf8),
            Data("image-content".utf8),
            Data("video-content".utf8)
        ])
        XCTAssertEqual(Set(savedMedia.map(\.1)), Set(["jpg", "mov"]))
    }

    @MainActor
    func testWrongPasswordDoesNotPrepareMediaOrData() throws {
        let snapshot = try DataArchiveTestSupport.makeSnapshot()
        let root = try DataArchiveTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appending(path: "source.bin")
        try Data("same-content".utf8).write(to: media)
        let credential = try makeCredential()
        _ = try DataBackupService.write(
            snapshot: snapshot,
            to: root,
            credential: credential,
            mediaURL: { _ in media }
        )
        var saveCount = 0

        XCTAssertThrowsError(try DataBackupService.prepareRestore(
            from: root,
            password: "wrong-pass",
            saveMedia: { _, _ in
                saveCount += 1
                return "PrivateMedia/unexpected.bin"
            }
        ))
        XCTAssertEqual(saveCount, 0)
    }

    @MainActor
    func testSnapshotRoundTripReplacesAllModelTypesAndMediaPaths() throws {
        let snapshot = try DataArchiveTestSupport.makeSnapshot()
        let suiteName = "DataBackupRoundTrip.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let context = spaces.personalContainer.mainContext
        context.insert(MealEntry(
            mealType: .snack,
            title: "将被替换",
            calories: 100,
            protein: 1,
            carbs: 1,
            fat: 1
        ))
        try context.save()
        let mapping = [
            DataArchiveTestSupport.mealMediaPath: "PrivateMedia/restored.jpg",
            DataArchiveTestSupport.exerciseImagePath:
                "PrivateMedia/restored-exercise.jpg",
            DataArchiveTestSupport.workoutMediaPath: "PrivateMedia/restored.mov"
        ]

        try snapshot.replace(in: context, mediaPathMapping: mapping)

        let restored = try PersonalDataSnapshot.capture(
            from: context,
            now: snapshot.createdAt
        )
        XCTAssertEqual(restored.modelCount, snapshot.modelCount)
        XCTAssertEqual(
            businessIDsByNamespace(in: restored),
            businessIDsByNamespace(in: snapshot)
        )
        XCTAssertEqual(restored.meals.map(\.id), snapshot.meals.map(\.id))
        XCTAssertEqual(
            restored.meals.first?.mediaAttachments.first?.path,
            "PrivateMedia/restored.jpg"
        )
        XCTAssertEqual(restored.mutationReceipts, snapshot.mutationReceipts)
        XCTAssertEqual(restored.traces, snapshot.traces)
        XCTAssertEqual(restored.trainingPrograms, snapshot.trainingPrograms)
        XCTAssertNotNil(restored.trainingPrograms?.first?.businessID)
        XCTAssertEqual(
            restored.exerciseMergeRecords?.first?.affectedPerformanceIDs,
            snapshot.exerciseMergeRecords?.first?.affectedPerformanceIDs
        )
        XCTAssertEqual(
            restored.exerciseMergeRecords?.first?
                .transferredUserDemoVideos?.first?.path,
            "PrivateMedia/restored.mov"
        )
        XCTAssertEqual(
            restored.exerciseDefinitions?.first(where: {
                $0.canonicalName == "杠铃前蹲"
            })?.imageReferences?.first(where: {
                $0.source == .generated
            })?.localPath,
            "PrivateMedia/restored-exercise.jpg"
        )
        XCTAssertEqual(
            restored.exerciseDefinitions?.first(where: {
                $0.canonicalName == "杠铃前蹲"
            })?.imageReferences?.first(where: {
                $0.source == .bundled
            })?.resourceName,
            "soma_muscle_squat.png"
        )
        XCTAssertEqual(restored.workoutSessions, snapshot.workoutSessions)
        XCTAssertNotNil(restored.workoutSessions?.first?.businessID)
        XCTAssertNotNil(restored.workoutSessions?.first?.queuedRecordingEffortID)
        XCTAssertEqual(restored.workoutSessions?.first?.automaticRecordingPaused, true)
        XCTAssertEqual(
            restored.workoutSessions?.first?.automaticRecordingPauseCodeRaw,
            WorkoutRecordingPauseCode.permissionDenied.rawValue
        )
        XCTAssertTrue(
            restored.workoutSessions?.first?.automaticRecordingPauseReason?
                .contains("系统设置") == true
        )
        var expectedWorkoutSets = snapshot.workoutSets
        expectedWorkoutSets?[0].recordedVideoPath = "PrivateMedia/restored.mov"
        XCTAssertEqual(restored.workoutSets, expectedWorkoutSets)
        XCTAssertNotNil(restored.workoutSets?.first?.businessID)
        XCTAssertEqual(
            restored.workoutSets?.first?.recordedVideoKindRaw,
            WorkoutRecordingEvidenceKind.partial.rawValue
        )
        XCTAssertEqual(
            restored.workouts.first?.sourceWorkoutSessionID,
            snapshot.workouts.first?.sourceWorkoutSessionID
        )
        XCTAssertEqual(
            restored.workouts.first?.sourcePerformanceID,
            snapshot.workouts.first?.sourcePerformanceID
        )
        XCTAssertEqual(
            restored.exercisePerformances?.first?.workoutProjectionSuppressed,
            snapshot.exercisePerformances?.first?.workoutProjectionSuppressed
        )
        XCTAssertEqual(
            restored.exercisePerformances?.first?.activeVideoPath,
            "PrivateMedia/restored.mov"
        )
        XCTAssertEqual(
            restored.exercisePerformances?.first?.activeVideoKindRaw,
            WorkoutRecordingEvidenceKind.partial.rawValue
        )
        XCTAssertEqual(
            restored.workoutEfforts?.first?.recordedVideoKindRaw,
            WorkoutRecordingEvidenceKind.partial.rawValue
        )
        XCTAssertEqual(
            restored.workoutEfforts?.first?.recordedVideoPath,
            "PrivateMedia/restored.mov"
        )
        let restoredSession = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkoutSession>()).first
        )
        let restoredPerformance = try XCTUnwrap(restoredSession.performances.first)
        let restoredSet = try XCTUnwrap(restoredPerformance.workoutSets.first)
        XCTAssertEqual(restoredPerformance.session?.id, restoredSession.id)
        XCTAssertEqual(restoredSet.performance?.id, restoredPerformance.id)
    }

    @MainActor
    func testRestorePreservesBusinessIDsAndContinuesEveryNamespace() throws {
        var snapshot = try DataArchiveTestSupport.makeSnapshot()
        snapshot.userProfiles[0].businessID = 101
        snapshot.gymProfiles[0].businessID = 201
        snapshot.gymEquipment[0].businessID = 301
        snapshot.meals[0].businessID = 401
        snapshot.bodyEntries[0].businessID = 501
        snapshot.workouts[0].businessID = 601
        if var values = snapshot.exerciseDefinitions {
            for index in values.indices {
                values[index].businessID = 701 + Int64(index * 8)
            }
            snapshot.exerciseDefinitions = values
        }
        snapshot.exerciseMergeRecords?[0].businessID = 801
        snapshot.trainingPrograms?[0].businessID = 901
        snapshot.workoutTemplateVersions?[0].businessID = 1001
        snapshot.templateExercises?[0].businessID = 1101
        snapshot.templateSetPrescriptions?[0].businessID = 1201
        snapshot.workoutSessions?[0].businessID = 1301
        snapshot.exercisePerformances?[0].businessID = 1401
        snapshot.workoutSets?[0].businessID = 1501
        snapshot.workoutEfforts?[0].businessID = 1601
        snapshot.recommendationSnapshots?[0].businessID = 1701
        snapshot.performanceAnalyses?[0].businessID = 1801

        let expected = businessIDsByNamespace(in: snapshot)
        XCTAssertEqual(expected.count, 18)
        XCTAssertTrue(expected.values.allSatisfy { !$0.isEmpty })

        let suiteName = "DataBackupBusinessIDs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let spaces = DataSpaceController(
            defaults: defaults,
            isStoredInMemoryOnly: true
        )
        let context = spaces.personalContainer.mainContext

        try snapshot.replace(in: context, mediaPathMapping: [:])
        let restored = try PersonalDataSnapshot.capture(
            from: context,
            now: snapshot.createdAt
        )

        XCTAssertEqual(businessIDsByNamespace(in: restored), expected)
        for namespace in expected.keys.sorted() {
            let maximum = try XCTUnwrap(expected[namespace]?.values.max())
            XCTAssertEqual(
                try BusinessIDAllocator.next(namespace: namespace, in: context),
                maximum + 1,
                namespace
            )
        }
    }

    @MainActor
    func testSnapshotWithoutBusinessIDFieldsRemainsDecodable() throws {
        let snapshot = try DataArchiveTestSupport.makeSnapshot()
        let encoded = try JSONEncoder().encode(snapshot)
        let object = try JSONSerialization.jsonObject(with: encoded)
        let legacyData = try JSONSerialization.data(
            withJSONObject: removingBusinessIDFields(from: object)
        )

        let decoded = try JSONDecoder().decode(
            PersonalDataSnapshot.self,
            from: legacyData
        )

        XCTAssertEqual(decoded.modelCount, snapshot.modelCount)
        let restoredIDs = businessIDsByNamespace(in: decoded)
        XCTAssertEqual(restoredIDs.count, 18)
        XCTAssertTrue(restoredIDs.values.allSatisfy(\.isEmpty))
    }

    @MainActor
    func testInvalidTrainingSnapshotsDoNotReplaceExistingDatabase() throws {
        let valid = try DataArchiveTestSupport.makeSnapshot()
        for invalidKind in ["session", "performance"] {
            var invalid = valid
            if invalidKind == "session" {
                var sessions = try XCTUnwrap(invalid.workoutSessions)
                sessions[0].prescriptionSnapshotData = Data("{".utf8)
                invalid.workoutSessions = sessions
            } else {
                var performances = try XCTUnwrap(invalid.exercisePerformances)
                performances[0].prescriptionSnapshotData = Data("{".utf8)
                invalid.exercisePerformances = performances
            }

            let suiteName = "DataBackupAtomicRestore.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let spaces = DataSpaceController(
                defaults: defaults,
                isStoredInMemoryOnly: true
            )
            let context = spaces.personalContainer.mainContext
            context.insert(MealEntry(
                mealType: .snack,
                title: "恢复前哨兵",
                calories: 123
            ))
            try context.save()
            let capturedAt = Date(timeIntervalSince1970: 42000)
            let before = try PersonalDataSnapshot.capture(
                from: context,
                now: capturedAt
            )

            XCTAssertThrowsError(try invalid.replace(
                in: context,
                mediaPathMapping: [:]
            ))

            let after = try PersonalDataSnapshot.capture(
                from: context,
                now: capturedAt
            )
            XCTAssertEqual(after, before, invalidKind)
            XCTAssertEqual(
                try context.fetch(FetchDescriptor<MealEntry>()).map(\.title),
                ["恢复前哨兵"]
            )
        }
    }

    @MainActor
    func testBackupKeepsTwoLatestCompleteSnapshotsAndRemovesPartialWork() throws {
        let snapshot = try DataArchiveTestSupport.makeSnapshot()
        let root = try DataArchiveTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appending(path: "source.bin")
        try Data("content".utf8).write(to: media)
        let credential = try makeCredential()
        let backupRoot = root.appending(
            path: DataBackupService.rootDirectoryName,
            directoryHint: .isDirectory
        )

        for offset in 0 ..< 3 {
            _ = try DataBackupService.write(
                snapshot: snapshot,
                to: root,
                credential: credential,
                now: DataArchiveTestSupport.fixedDate
                    .addingTimeInterval(Double(offset)),
                mediaURL: { _ in media }
            )
            if offset == 1 {
                let partial = backupRoot.appending(
                    path: ".partial-interrupted",
                    directoryHint: .isDirectory
                )
                try FileManager.default.createDirectory(
                    at: partial,
                    withIntermediateDirectories: false
                )
            }
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(contents.filter { $0.pathExtension == "somabackup" }.count, 2)
        XCTAssertFalse(contents.contains {
            $0.lastPathComponent == ".partial-interrupted"
        })
    }

    private func makeCredential() throws -> DataBackupCredential {
        let salt = Data("salt-salt-salt-1".utf8)
        return try DataBackupCredential(
            salt: salt,
            iterations: 2,
            keyData: DataBackupCrypto.deriveKeyData(
                password: "password",
                salt: salt,
                iterations: 2
            )
        )
    }

    private func businessIDsByNamespace(
        in snapshot: PersonalDataSnapshot
    ) -> [String: [UUID: Int64]] {
        [
            "user_profile": indexedBusinessIDs(snapshot.userProfiles),
            "gym": indexedBusinessIDs(snapshot.gymProfiles),
            "gym_equipment": indexedBusinessIDs(snapshot.gymEquipment),
            "meal": indexedBusinessIDs(snapshot.meals),
            "body": indexedBusinessIDs(snapshot.bodyEntries),
            "workout": indexedBusinessIDs(snapshot.workouts),
            "exercise": indexedBusinessIDs(snapshot.exerciseDefinitions ?? []),
            "exercise_merge": indexedBusinessIDs(snapshot.exerciseMergeRecords ?? []),
            "training_program": indexedBusinessIDs(snapshot.trainingPrograms ?? []),
            "template_version": indexedBusinessIDs(
                snapshot.workoutTemplateVersions ?? []
            ),
            "template_exercise": indexedBusinessIDs(snapshot.templateExercises ?? []),
            "template_set_prescription": indexedBusinessIDs(
                snapshot.templateSetPrescriptions ?? []
            ),
            "workout_session": indexedBusinessIDs(snapshot.workoutSessions ?? []),
            "performance": indexedBusinessIDs(snapshot.exercisePerformances ?? []),
            "workout_set": indexedBusinessIDs(snapshot.workoutSets ?? []),
            "workout_effort": indexedBusinessIDs(snapshot.workoutEfforts ?? []),
            "recommendation": indexedBusinessIDs(
                snapshot.recommendationSnapshots ?? []
            ),
            "performance_analysis": indexedBusinessIDs(
                snapshot.performanceAnalyses ?? []
            )
        ]
    }

    private func indexedBusinessIDs(
        _ values: [some ArchivedBusinessIDDTO]
    ) -> [UUID: Int64] {
        var result: [UUID: Int64] = [:]
        for value in values {
            result[value.id] = value.businessID
        }
        return result
    }

    private func removingBusinessIDFields(from value: Any) -> Any {
        if var object = value as? [String: Any] {
            object.removeValue(forKey: "businessID")
            return object.mapValues(removingBusinessIDFields(from:))
        }
        if let values = value as? [Any] {
            return values.map(removingBusinessIDFields(from:))
        }
        return value
    }
}
