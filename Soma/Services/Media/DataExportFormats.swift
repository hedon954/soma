import Foundation

struct PortableExportManifest: Codable, Equatable, Sendable {
    var formatVersion: Int
    var generatedAt: Date
    var timeZone: String
    var mealCount: Int
    var workoutCount: Int
    var copiedMediaCount: Int
    var missingMedia: [PortableExportMissingMedia]
    var records: [PortableExportManifestRecord]
}

struct PortableExportManifestRecord: Codable, Equatable, Sendable {
    var id: UUID
    var type: String
    var date: Date
    var relativeDirectory: String
    var mediaCount: Int
}

struct PortableExportMissingMedia: Codable, Equatable, Sendable {
    var recordID: UUID
    var index: Int
    var kind: String
}

struct PortableExportMedia: Codable, Equatable, Sendable {
    var order: Int
    var kind: String
    var filename: String
}

struct PortableExportMediaIndex: Codable, Equatable, Sendable {
    var sourceIdentifier: String
    var filename: String
}

struct PortableMealAnalysis: Codable, Equatable, Sendable {
    var formatVersion: Int
    var id: UUID
    var date: Date
    var mealType: String
    var title: String
    var calories: Int?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var glycemicSpeed: String?
    var glycemicAssessment: String?
    var recommendedEatingOrder: String?
    var items: [MealItem]?
    var nutritionSource: String?
    var notes: String?
    var sourceTurnID: UUID?
    var sourceSessionID: UUID?
    var sourceText: String?
    var agentAnalysis: String?
    var media: [PortableExportMedia]
}

struct PortableWorkoutAnalysis: Codable, Equatable, Sendable {
    var formatVersion: Int
    var id: UUID
    var date: Date
    var exercise: String
    var setEntries: [WorkoutSetEvidence]?
    var sets: Int?
    var reps: Int?
    var weight: Double?
    var restSeconds: Int?
    var durationMinutes: Int?
    var notes: String?
    var formScore: Int?
    var intensity: String?
    var feedback: String?
    var estimatedCalories: Int?
    var calorieMET: Double?
    var calorieScopeRaw: String?
    var calorieDurationMinutes: Double?
    var calorieDurationEstimated: Bool
    var externalSource: String?
    var externalID: String?
    var sourceTurnID: UUID?
    var sourceSessionID: UUID?
    var sourceWorkoutSessionID: UUID?
    var sourcePerformanceID: UUID?
    var sourceText: String?
    var agentAnalysis: String?
    var media: [PortableExportMedia]
}
