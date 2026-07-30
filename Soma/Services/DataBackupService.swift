import Foundation

enum DataBackupService {
    static let rootDirectoryName = "Soma Backup"
    static let snapshotFilename = "snapshot.json.enc"
    static let headerFilename = "header.json"
    static let completionFilename = "complete.json"
    static let retainedBackupCount = 2

    static func write(
        snapshot: PersonalDataSnapshot,
        to selectedDirectory: URL,
        credential: DataBackupCredential,
        now: Date = .now,
        mediaURL: (String) -> URL? = MediaStore.url(at:)
    ) throws -> DataBackupWriteResult {
        try snapshot.validate()
        guard credential.keyData.count == DataBackupCrypto.keyByteCount,
              credential.salt.count >= DataBackupCrypto.saltByteCount
        else {
            throw DataArchiveError.invalidBackup
        }

        let fileManager = FileManager.default
        let root = selectedDirectory.appending(
            path: rootDirectoryName,
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let finalURL = uniqueBackupURL(in: root, date: now)
        let partialURL = root.appending(
            path: ".partial-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

        do {
            try fileManager.createDirectory(
                at: partialURL,
                withIntermediateDirectories: false
            )
            let header = DataBackupHeader(
                formatVersion: DataBackupHeader.currentFormatVersion,
                snapshotSchemaVersion: snapshot.schemaVersion,
                createdAt: now,
                kdfAlgorithm: "PBKDF2-HMAC-SHA256",
                salt: credential.salt,
                iterations: credential.iterations,
                keyByteCount: DataBackupCrypto.keyByteCount,
                encryptionAlgorithm: "AES-256-GCM"
            )
            try encode(header).write(
                to: partialURL.appending(path: headerFilename),
                options: .atomic
            )

            let mediaDirectory = partialURL.appending(
                path: "media",
                directoryHint: .isDirectory
            )
            try fileManager.createDirectory(
                at: mediaDirectory,
                withIntermediateDirectories: false
            )
            var mediaDescriptors: [DataBackupMediaDescriptor] = []
            for (offset, logicalPath) in snapshot.referencedMediaPaths.sorted().enumerated() {
                guard let sourceURL = mediaURL(logicalPath),
                      fileManager.fileExists(atPath: sourceURL.path)
                else {
                    throw DataArchiveError.missingMedia
                }
                let plaintext = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
                let encrypted = try DataBackupCrypto.seal(
                    plaintext,
                    keyData: credential.keyData
                )
                let filename = String(format: "%05d.enc", offset + 1)
                try encrypted.write(
                    to: mediaDirectory.appending(path: filename),
                    options: .atomic
                )
                mediaDescriptors.append(DataBackupMediaDescriptor(
                    logicalPath: logicalPath,
                    encryptedFilename: filename,
                    fileExtension: sourceURL.pathExtension,
                    plaintextByteCount: plaintext.count,
                    plaintextSHA256: DataBackupCrypto.sha256(plaintext)
                ))
            }

            let envelope = DataBackupEnvelope(
                snapshot: snapshot,
                media: mediaDescriptors
            )
            let encryptedSnapshot = try DataBackupCrypto.seal(
                encode(envelope),
                keyData: credential.keyData
            )
            try encryptedSnapshot.write(
                to: partialURL.appending(path: snapshotFilename),
                options: .atomic
            )
            let completion = DataBackupCompletion(
                completedAt: now,
                mediaCount: mediaDescriptors.count,
                encryptedSnapshotSHA256: DataBackupCrypto.sha256(encryptedSnapshot)
            )
            try encode(completion).write(
                to: partialURL.appending(path: completionFilename),
                options: .atomic
            )

            try fileManager.moveItem(at: partialURL, to: finalURL)
            rotateBackups(in: root, keeping: retainedBackupCount)
            return DataBackupWriteResult(
                directoryURL: finalURL,
                completedAt: now,
                modelCount: snapshot.modelCount,
                mediaCount: mediaDescriptors.count
            )
        } catch {
            try? fileManager.removeItem(at: partialURL)
            throw error
        }
    }

    static func prepareRestore(
        from selectedDirectory: URL,
        password: String,
        saveMedia: (Data, String) throws -> String = MediaStore.saveRestoredMedia
    ) throws -> PreparedDataRestore {
        let backupURL = try newestCompleteBackup(in: selectedDirectory)
        let header = try decode(
            DataBackupHeader.self,
            from: backupURL.appending(path: headerFilename)
        )
        guard header.formatVersion == DataBackupHeader.currentFormatVersion else {
            throw DataArchiveError.unsupportedBackupFormat(header.formatVersion)
        }
        guard header.snapshotSchemaVersion == PersonalDataSnapshot.currentSchemaVersion else {
            throw DataArchiveError.unsupportedSchema(header.snapshotSchemaVersion)
        }
        guard header.kdfAlgorithm == "PBKDF2-HMAC-SHA256",
              header.encryptionAlgorithm == "AES-256-GCM",
              header.keyByteCount == DataBackupCrypto.keyByteCount
        else {
            throw DataArchiveError.invalidBackup
        }
        let keyData: Data
        do {
            keyData = try DataBackupCrypto.deriveKeyData(
                password: password,
                salt: header.salt,
                iterations: header.iterations,
                outputByteCount: header.keyByteCount
            )
        } catch let error as DataArchiveError {
            throw error
        } catch {
            throw DataArchiveError.invalidPasswordOrCorruptBackup
        }

        let completion = try decode(
            DataBackupCompletion.self,
            from: backupURL.appending(path: completionFilename)
        )
        let encryptedSnapshot = try Data(
            contentsOf: backupURL.appending(path: snapshotFilename)
        )
        guard DataBackupCrypto.sha256(encryptedSnapshot)
            == completion.encryptedSnapshotSHA256
        else {
            throw DataArchiveError.invalidBackup
        }
        let envelopeData = try DataBackupCrypto.open(
            encryptedSnapshot,
            keyData: keyData
        )
        let envelope: DataBackupEnvelope
        do {
            envelope = try decoder().decode(DataBackupEnvelope.self, from: envelopeData)
            try envelope.snapshot.validate()
        } catch let error as DataArchiveError {
            throw error
        } catch {
            throw DataArchiveError.invalidPasswordOrCorruptBackup
        }

        let expectedPaths = envelope.snapshot.referencedMediaPaths
        let describedPaths = Set(envelope.media.map(\.logicalPath))
        guard envelope.media.count == completion.mediaCount,
              describedPaths.count == envelope.media.count,
              describedPaths == expectedPaths
        else {
            throw DataArchiveError.invalidBackup
        }

        var createdPaths = Set<String>()
        var mapping: [String: String] = [:]
        do {
            for descriptor in envelope.media {
                guard descriptor.encryptedFilename
                    == URL(fileURLWithPath: descriptor.encryptedFilename).lastPathComponent
                else {
                    throw DataArchiveError.invalidBackup
                }
                let encryptedURL = backupURL
                    .appending(path: "media", directoryHint: .isDirectory)
                    .appending(path: descriptor.encryptedFilename)
                let encrypted = try Data(contentsOf: encryptedURL)
                let plaintext = try DataBackupCrypto.open(
                    encrypted,
                    keyData: keyData
                )
                guard plaintext.count == descriptor.plaintextByteCount,
                      DataBackupCrypto.sha256(plaintext)
                      == descriptor.plaintextSHA256
                else {
                    throw DataArchiveError.invalidBackup
                }
                let newPath = try saveMedia(plaintext, descriptor.fileExtension)
                mapping[descriptor.logicalPath] = newPath
                createdPaths.insert(newPath)
            }
        } catch {
            createdPaths.forEach { MediaStore.removeStoredFile(at: $0) }
            throw error
        }

        return PreparedDataRestore(
            snapshot: envelope.snapshot,
            mediaPathMapping: mapping,
            createdMediaPaths: createdPaths,
            sourceDirectoryURL: backupURL
        )
    }

    static func newestCompleteBackup(in selectedDirectory: URL) throws -> URL {
        let fileManager = FileManager.default
        if isCompleteBackup(selectedDirectory, fileManager: fileManager) {
            return selectedDirectory
        }
        let rootCandidate = selectedDirectory.lastPathComponent == rootDirectoryName
            ? selectedDirectory
            : selectedDirectory.appending(
                path: rootDirectoryName,
                directoryHint: .isDirectory
            )
        guard let contents = try? fileManager.contentsOfDirectory(
            at: rootCandidate,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw DataArchiveError.noCompleteBackup
        }
        let complete = contents.filter { isCompleteBackup($0, fileManager: fileManager) }
        guard let newest = complete.max(by: {
            backupDate($0) < backupDate($1)
        }) else {
            throw DataArchiveError.noCompleteBackup
        }
        return newest
    }

    private static func isCompleteBackup(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        return url.pathExtension == "somabackup"
            && fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && fileManager.fileExists(
                atPath: url.appending(path: headerFilename).path
            )
            && fileManager.fileExists(
                atPath: url.appending(path: snapshotFilename).path
            )
            && fileManager.fileExists(
                atPath: url.appending(path: completionFilename).path
            )
    }

    private static func rotateBackups(in root: URL, keeping count: Int) {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: []
        ) else {
            return
        }
        let backups = contents
            .filter { isCompleteBackup($0, fileManager: fileManager) }
            .sorted { backupDate($0) > backupDate($1) }
        for url in backups.dropFirst(max(1, count)) {
            try? fileManager.removeItem(at: url)
        }
        for url in contents where url.lastPathComponent.hasPrefix(".partial-") {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func backupDate(_ url: URL) -> Date {
        (
            try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        ) ?? .distantPast
    }

    private static func uniqueBackupURL(in root: URL, date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return root.appending(
            path: "backup-\(formatter.string(from: date))-\(UUID().uuidString.prefix(8)).somabackup",
            directoryHint: .isDirectory
        )
    }

    private static func encode(_ value: some Encodable) throws -> Data {
        try encoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        do {
            return try decoder().decode(type, from: Data(contentsOf: url))
        } catch let error as DataArchiveError {
            throw error
        } catch {
            throw DataArchiveError.invalidBackup
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }
}
