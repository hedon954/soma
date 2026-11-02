import Foundation
import SwiftData

enum SomaStoreOpening {
    static func makeContainer(
        configurationName: String?,
        schema: Schema,
        isStoredInMemoryOnly: Bool,
        url: URL? = nil,
        stepName: String
    ) throws -> ModelContainer {
        do {
            let config = configuration(name: configurationName, schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly, url: url)
            if configurationName == "PersonalData", !isStoredInMemoryOnly {
                try protectPersonalStore(at: config.url)
            }
            let container = try ModelContainer(for: schema, configurations: [config])
            if configurationName == "PersonalData", !isStoredInMemoryOnly {
                try protectPersonalStore(at: config.url)
            }
            return container
        } catch {
            throw DataMigrationError.stepFailed(stepName, error)
        }
    }

    private static func protectPersonalStore(at url: URL) throws {
        let manager = FileManager.default
        var directory = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        try directory.setResourceValues(excluded)
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        for path in [url.path, url.path + "-wal", url.path + "-shm"] where manager.fileExists(atPath: path) {
            try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
            var file = URL(fileURLWithPath: path)
            try file.setResourceValues(excluded)
        }
    }

    private static func configuration(
        name: String?,
        schema: Schema,
        isStoredInMemoryOnly: Bool,
        url: URL?
    ) -> ModelConfiguration {
        if isStoredInMemoryOnly {
            return ModelConfiguration(
                name,
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        }
        if let url {
            return ModelConfiguration(
                name,
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
        }
        return ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
    }
}
