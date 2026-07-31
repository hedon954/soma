import Foundation
@testable import Soma
import SwiftData
import XCTest

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
        XCTAssertEqual(restored.meals.map(\.id), snapshot.meals.map(\.id))
        XCTAssertEqual(
            restored.meals.first?.mediaAttachments.first?.path,
            "PrivateMedia/restored.jpg"
        )
        XCTAssertEqual(restored.mutationReceipts, snapshot.mutationReceipts)
        XCTAssertEqual(restored.traces, snapshot.traces)
        XCTAssertEqual(restored.trainingPrograms, snapshot.trainingPrograms)
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
        XCTAssertEqual(restored.workoutSets, snapshot.workoutSets)
        XCTAssertEqual(
            restored.exercisePerformances?.first?.activeVideoPath,
            "PrivateMedia/restored.mov"
        )
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
}
