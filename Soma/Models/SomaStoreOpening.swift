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
            return try ModelContainer(
                for: schema,
                configurations: [configuration(
                    name: configurationName,
                    schema: schema,
                    isStoredInMemoryOnly: isStoredInMemoryOnly,
                    url: url
                )]
            )
        } catch {
            throw DataMigrationError.stepFailed(stepName, error)
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
