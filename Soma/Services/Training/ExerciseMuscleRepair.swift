#if DEBUG || SOMA_EXERCISE_METADATA_REPAIR
    import Foundation
    import SwiftData

    struct ExerciseMuscleRepair: Decodable {
        struct Entry: Decodable, Equatable, Identifiable {
            let id: Int64
            let name: String
            var newName: String? = nil
            let primary: [MuscleGroup]
            let secondary: [MuscleGroup]

            var isValid: Bool {
                guard id > 0, Set(primary + secondary).count == primary.count + secondary.count else { return false }
                if let newName, ExerciseLibraryStore.canonicalNameKey(newName).isEmpty {
                    return false
                }
                return !primary.isEmpty || (newName != nil && secondary.isEmpty)
            }
        }

        struct Merge: Decodable, Equatable, Identifiable {
            let sourceID: Int64
            let sourceName: String
            let targetID: Int64
            let targetName: String

            var id: Int64 {
                sourceID
            }
        }

        struct Preview: Equatable {
            let pending: [Entry]
            let pendingMerges: [Merge]
            let unresolved: [String]

            var changeCount: Int {
                pending.count + pendingMerges.count
            }
        }

        enum RepairError: LocalizedError {
            case invalidPlan, changedSincePreview

            var errorDescription: String? {
                switch self {
                case .invalidPlan: "修复清单有无效或重复的动作，请重新生成。"
                case .changedSincePreview: "动作库在预览后有变化，请重新核对。"
                }
            }
        }

        let entries: [Entry]
        var merges: [Merge]? = nil

        static var planURL: URL {
            URL.applicationSupportDirectory.appending(path: "exercise-muscle-repair-20261119.json")
        }

        static func load() throws -> Self {
            try JSONDecoder().decode(Self.self, from: Data(contentsOf: planURL))
        }

        @MainActor
        func preview(in context: ModelContext) throws -> Preview {
            let resolved = try resolve(in: context)
            let matchedIDs = Set(resolved.entries.map(\.entry.id) + resolved.merges.map(\.merge.sourceID))
            let unresolved = resolved.definitions.filter {
                !$0.isArchived && $0.needsMuscleMap && !matchedIDs.contains($0.businessID ?? 0)
            }.map(\.canonicalName).sorted()
            return Preview(pending: resolved.entries.map(\.entry), pendingMerges: resolved.merges.map(\.merge), unresolved: unresolved)
        }

        @MainActor
        func apply(_ expected: Preview, in context: ModelContext) throws -> Int {
            let resolved = try resolve(in: context)
            guard resolved.entries.map(\.entry) == expected.pending, resolved.merges.map(\.merge) == expected.pendingMerges else {
                throw RepairError.changedSincePreview
            }
            do {
                for (entry, exercise) in resolved.entries {
                    exercise.fillMissingMuscleMap(primary: entry.primary, secondary: entry.secondary)
                    if let newName = entry.newName {
                        try ExerciseLibraryStore.rename(exercise, to: newName, refreshBundledContent: false, saveChanges: false, in: context)
                    }
                }
                for (_, source, target) in resolved.merges {
                    _ = try ExerciseLibraryStore.merge(source: source, into: target, saveChanges: false, in: context)
                }
                try context.save()
                return expected.changeCount
            } catch {
                context.rollback()
                throw error
            }
        }

        private struct Resolved {
            let definitions: [ExerciseDefinition]
            let entries: [(entry: Entry, exercise: ExerciseDefinition)]
            let merges: [(merge: Merge, source: ExerciseDefinition, target: ExerciseDefinition)]
        }

        @MainActor
        private func resolve(in context: ModelContext) throws -> Resolved {
            let targetKeys = entries.compactMap(\.newName).map(ExerciseLibraryStore.canonicalNameKey)
            let requestedMerges = merges ?? []
            let mergeSources = Set(requestedMerges.map(\.sourceID))
            guard entries.allSatisfy(\.isValid), Set(entries.map(\.id)).count == entries.count,
                  Set(targetKeys).count == targetKeys.count,
                  mergeSources.count == requestedMerges.count,
                  mergeSources.isDisjoint(with: requestedMerges.map(\.targetID)),
                  mergeSources.isDisjoint(with: entries.map(\.id)) else { throw RepairError.invalidPlan }
            let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
            let byID = Dictionary(grouping: definitions, by: \.businessID)
            let byName = Dictionary(grouping: definitions, by: \.canonicalNameKey)
            func match(id: Int64, name: String) -> ExerciseDefinition? {
                guard id > 0, let group = byID[id], group.count == 1, let exercise = group.first,
                      !exercise.isArchived, exercise.canonicalName == name else { return nil }
                return exercise
            }
            let matchingEntries: [(Entry, ExerciseDefinition)] = entries.compactMap { entry in
                guard let exercise = match(id: entry.id, name: entry.name) else { return nil }
                let newName = entry.newName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let rename = newName.flatMap { name -> String? in
                    let key = ExerciseLibraryStore.canonicalNameKey(name)
                    guard name != exercise.canonicalName, byName[key]?.contains(where: { $0.id != exercise.id }) != true else { return nil }
                    return name
                }
                let needsMuscles = exercise.needsMuscleMap && !entry.primary.isEmpty
                guard rename != nil || needsMuscles else { return nil }
                return (.init(id: entry.id, name: entry.name, newName: rename,
                              primary: needsMuscles ? entry.primary : [], secondary: needsMuscles ? entry.secondary : []), exercise)
            }
            let matchingMerges: [(Merge, ExerciseDefinition, ExerciseDefinition)] = requestedMerges.compactMap { merge in
                guard let source = match(id: merge.sourceID, name: merge.sourceName),
                      let target = match(id: merge.targetID, name: merge.targetName) else { return nil }
                return (merge, source, target)
            }
            return Resolved(definitions: definitions, entries: matchingEntries, merges: matchingMerges)
        }
    }
#endif
