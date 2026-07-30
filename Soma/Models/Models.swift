import Foundation
import SwiftData

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast = "早餐"
    case lunch = "午餐"
    case dinner = "晚餐"
    case snack = "加餐"
    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "cup.and.saucer.fill"
        }
    }
}

enum MediaKind: String, Codable, Hashable, Sendable {
    case none, image, video
}

struct MediaAttachmentReference: Codable, Hashable, Identifiable, Sendable {
    var kind: MediaKind
    var path: String

    var id: String {
        "\(kind.rawValue):\(path)"
    }
}

private enum MediaAttachmentStorage {
    static func encode(_ attachments: [MediaAttachmentReference]) -> Data {
        (try? JSONEncoder().encode(attachments)) ?? Data()
    }

    static func decode(
        _ data: Data,
        legacyKind: MediaKind = .none,
        legacyPath: String? = nil
    ) -> [MediaAttachmentReference] {
        let decoded = (try? JSONDecoder().decode(
            [MediaAttachmentReference].self,
            from: data
        )) ?? []
        if !decoded.isEmpty {
            return decoded
        }
        guard legacyKind != .none, let legacyPath else { return [] }
        return [MediaAttachmentReference(kind: legacyKind, path: legacyPath)]
    }
}

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case unspecified = "未填写"
    case female = "女性"
    case male = "男性"
    case other = "其他或不愿填写"

    var id: String {
        rawValue
    }
}

@Model
final class ExternalSyncCursor {
    var id: UUID
    var source: String
    var stream: String
    var cursorData: Data?
    var updatedAt: Date

    init(
        source: String,
        stream: String,
        cursorData: Data? = nil,
        updatedAt: Date = .now
    ) {
        id = UUID()
        self.source = source
        self.stream = stream
        self.cursorData = cursorData
        self.updatedAt = updatedAt
    }
}

@Model
final class UserProfile {
    var id: UUID
    var updatedAt: Date
    var displayName: String
    var biologicalSexRaw: String
    var birthDate: Date?
    // 仅用于兼容早期本地数据；界面与 Agent 均使用 birthDate 动态计算年龄。
    var age: Int?
    var height: Double?
    var referenceWeight: Double?
    var fitnessGoal: String
    var healthNotes: String

    var biologicalSex: BiologicalSex {
        get { BiologicalSex(rawValue: biologicalSexRaw) ?? .unspecified }
        set { biologicalSexRaw = newValue.rawValue }
    }

    var currentAge: Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: .now).year
    }

    init(
        updatedAt: Date = .now,
        displayName: String = "",
        biologicalSex: BiologicalSex = .unspecified,
        birthDate: Date? = nil,
        age: Int? = nil,
        height: Double? = nil,
        referenceWeight: Double? = nil,
        fitnessGoal: String = "",
        healthNotes: String = ""
    ) {
        id = UUID()
        self.updatedAt = updatedAt
        self.displayName = displayName
        biologicalSexRaw = biologicalSex.rawValue
        self.birthDate = birthDate
        self.age = age
        self.height = height
        self.referenceWeight = referenceWeight
        self.fitnessGoal = fitnessGoal
        self.healthNotes = healthNotes
    }
}

@Model
final class GymProfile {
    var id: UUID
    var name: String
    var createdAt: Date
    var notes: String
    var coverImagePath: String?
    var isCurrent: Bool = false
    var latitude: Double?
    var longitude: Double?
    var locationLabel: String?
    var locationAccuracy: Double?
    var locationUpdatedAt: Date?
    var matchRadiusMeters: Double = 180

    init(
        name: String,
        notes: String = "",
        coverImagePath: String? = nil,
        isCurrent: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationLabel: String? = nil,
        locationAccuracy: Double? = nil,
        locationUpdatedAt: Date? = nil,
        matchRadiusMeters: Double = 180
    ) {
        id = UUID()
        self.name = name
        createdAt = .now
        self.notes = notes
        self.coverImagePath = coverImagePath
        self.isCurrent = isCurrent
        self.latitude = latitude
        self.longitude = longitude
        self.locationLabel = locationLabel
        self.locationAccuracy = locationAccuracy
        self.locationUpdatedAt = locationUpdatedAt
        self.matchRadiusMeters = matchRadiusMeters
    }
}

enum GymSelection {
    static func current(in gyms: [GymProfile]) -> GymProfile? {
        gyms.first(where: \.isCurrent) ?? gyms.first
    }

    static func activate(_ target: GymProfile, among gyms: [GymProfile]) {
        gyms.forEach { $0.isCurrent = $0.id == target.id }
    }

    static func ensureCurrent(in gyms: [GymProfile]) {
        guard !gyms.isEmpty, !gyms.contains(where: \.isCurrent), let first = gyms.first else { return }
        activate(first, among: gyms)
    }
}

@MainActor
enum StructuredDataStore {
    static func deleteGym(
        _ gym: GymProfile,
        gyms: [GymProfile],
        equipment: [GymEquipment],
        media: [GymMedia],
        in context: ModelContext
    ) {
        equipment
            .filter { $0.gymID == gym.id }
            .forEach(context.delete)
        media
            .filter { $0.gymID == gym.id }
            .forEach(context.delete)

        let remainingGyms = gyms.filter { $0.id != gym.id }
        context.delete(gym)
        if gym.isCurrent, let nextGym = remainingGyms.first {
            GymSelection.activate(nextGym, among: remainingGyms)
        }
        try? context.save()
    }
}

@Model
final class GymEquipment {
    var id: UUID
    var gymID: UUID
    var name: String
    var category: String
    var capabilities: String
    var confidence: Double
    var imagePath: String?
    var createdAt: Date

    init(
        gymID: UUID,
        name: String,
        category: String,
        capabilities: String,
        confidence: Double = 0.9,
        imagePath: String? = nil
    ) {
        id = UUID()
        self.gymID = gymID
        self.name = name
        self.category = category
        self.capabilities = capabilities
        self.confidence = confidence
        self.imagePath = imagePath
        createdAt = .now
    }
}

@Model
final class GymMedia {
    var id: UUID
    var gymID: UUID
    var path: String
    var createdAt: Date

    init(gymID: UUID, path: String, createdAt: Date = .now) {
        id = UUID()
        self.gymID = gymID
        self.path = path
        self.createdAt = createdAt
    }
}

@Model
final class MealEntry {
    var id: UUID
    var date: Date
    var mealTypeRaw: String
    var title: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var notes: String
    var imagePath: String?
    var mediaAttachmentsData: Data = Data()
    var confidence: Double
    var sourceTurnID: UUID?
    var sourceSessionID: UUID?

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .lunch }
        set { mealTypeRaw = newValue.rawValue }
    }

    init(
        date: Date = .now,
        mealType: MealType,
        title: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        notes: String = "",
        imagePath: String? = nil,
        mediaAttachments: [MediaAttachmentReference] = [],
        confidence: Double = 0.9,
        sourceTurnID: UUID? = nil,
        sourceSessionID: UUID? = nil
    ) {
        id = UUID()
        self.date = date
        mealTypeRaw = mealType.rawValue
        self.title = title
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.notes = notes
        self.imagePath = imagePath
        mediaAttachmentsData = MediaAttachmentStorage.encode(mediaAttachments)
        self.confidence = confidence
        self.sourceTurnID = sourceTurnID
        self.sourceSessionID = sourceSessionID
    }

    var mediaAttachments: [MediaAttachmentReference] {
        get {
            MediaAttachmentStorage.decode(
                mediaAttachmentsData,
                legacyKind: imagePath == nil ? .none : .image,
                legacyPath: imagePath
            )
        }
        set {
            mediaAttachmentsData = MediaAttachmentStorage.encode(newValue)
            imagePath = newValue.first(where: { $0.kind == .image })?.path
        }
    }
}

@Model
final class BodyEntry {
    var id: UUID
    var date: Date
    var weight: Double?
    var bodyFat: Double?
    var waist: Double?
    var notes: String
    var imagePath: String?
    var mediaAttachmentsData: Data = Data()
    var analysis: String
    var externalSource: String?
    var externalID: String?
    var sourceTurnID: UUID?
    var sourceSessionID: UUID?

    init(
        date: Date = .now,
        weight: Double? = nil,
        bodyFat: Double? = nil,
        waist: Double? = nil,
        notes: String = "",
        imagePath: String? = nil,
        mediaAttachments: [MediaAttachmentReference] = [],
        analysis: String = "",
        externalSource: String? = nil,
        externalID: String? = nil,
        sourceTurnID: UUID? = nil,
        sourceSessionID: UUID? = nil
    ) {
        id = UUID()
        self.date = date
        self.weight = weight
        self.bodyFat = bodyFat
        self.waist = waist
        self.notes = notes
        self.imagePath = imagePath
        mediaAttachmentsData = MediaAttachmentStorage.encode(mediaAttachments)
        self.analysis = analysis
        self.externalSource = externalSource
        self.externalID = externalID
        self.sourceTurnID = sourceTurnID
        self.sourceSessionID = sourceSessionID
    }

    var mediaAttachments: [MediaAttachmentReference] {
        get {
            MediaAttachmentStorage.decode(
                mediaAttachmentsData,
                legacyKind: imagePath == nil ? .none : .image,
                legacyPath: imagePath
            )
        }
        set {
            mediaAttachmentsData = MediaAttachmentStorage.encode(newValue)
            imagePath = newValue.first(where: { $0.kind == .image })?.path
        }
    }
}

@Model
final class WorkoutEntry {
    var id: UUID
    var date: Date
    var exercise: String
    var sets: Int?
    var reps: Int?
    var weight: Double?
    var restSeconds: Int?
    var durationMinutes: Int?
    var notes: String
    var mediaKindRaw: String
    var mediaPath: String?
    var mediaAttachmentsData: Data = Data()
    var formScore: Int?
    var intensity: String?
    var feedback: String?
    var estimatedCalories: Int?
    var calorieMET: Double?
    var calorieDurationMinutes: Double?
    var calorieDurationEstimated: Bool = false
    var externalSource: String?
    var externalID: String?
    var sourceTurnID: UUID?
    var sourceSessionID: UUID?
    var estimatedVolume: Double? {
        guard let sets, let reps, let weight else { return nil }
        return Double(sets * reps) * weight
    }

    var mediaKind: MediaKind {
        get { MediaKind(rawValue: mediaKindRaw) ?? .none }
        set { mediaKindRaw = newValue.rawValue }
    }

    var mediaAttachments: [MediaAttachmentReference] {
        get {
            MediaAttachmentStorage.decode(
                mediaAttachmentsData,
                legacyKind: mediaKind,
                legacyPath: mediaPath
            )
        }
        set {
            mediaAttachmentsData = MediaAttachmentStorage.encode(newValue)
            mediaKind = newValue.first?.kind ?? .none
            mediaPath = newValue.first?.path
        }
    }

    init(
        date: Date = .now,
        exercise: String,
        sets: Int? = nil,
        reps: Int? = nil,
        weight: Double? = nil,
        restSeconds: Int? = nil,
        durationMinutes: Int? = nil,
        notes: String = "",
        mediaKind: MediaKind = .none,
        mediaPath: String? = nil,
        mediaAttachments: [MediaAttachmentReference] = [],
        formScore: Int? = nil,
        intensity: String? = nil,
        feedback: String? = nil,
        estimatedCalories: Int? = nil,
        calorieMET: Double? = nil,
        calorieDurationMinutes: Double? = nil,
        calorieDurationEstimated: Bool = false,
        externalSource: String? = nil,
        externalID: String? = nil,
        sourceTurnID: UUID? = nil,
        sourceSessionID: UUID? = nil
    ) {
        id = UUID()
        self.date = date
        self.exercise = exercise
        self.sets = sets
        self.reps = reps
        self.weight = weight
        self.restSeconds = restSeconds
        self.durationMinutes = durationMinutes
        self.notes = notes
        mediaKindRaw = mediaKind.rawValue
        self.mediaPath = mediaPath
        mediaAttachmentsData = MediaAttachmentStorage.encode(mediaAttachments)
        self.formScore = formScore
        self.intensity = intensity
        self.feedback = feedback
        self.estimatedCalories = estimatedCalories
        self.calorieMET = calorieMET
        self.calorieDurationMinutes = calorieDurationMinutes
        self.calorieDurationEstimated = calorieDurationEstimated
        self.externalSource = externalSource
        self.externalID = externalID
        self.sourceTurnID = sourceTurnID
        self.sourceSessionID = sourceSessionID
    }
}

@Model
final class CoachMessage {
    var id: UUID
    var date: Date
    var sessionID: UUID?
    var isFromCoach: Bool
    var text: String
    var mediaKindRaw: String = MediaKind.none.rawValue
    var mediaPath: String?
    var mediaAttachmentsData: Data = Data()
    var recordTypeRaw: String?
    var agentTraceID: UUID?
    var agentStatusRaw: String?
    var agentEventsData: Data = Data()
    var agentTurnItemsData: Data = Data()
    var turnID: UUID?
    var attemptNumber: Int = 0
    var locationData: Data = Data()
    var effectiveGymID: UUID?

    init(
        date: Date = .now,
        sessionID: UUID? = nil,
        isFromCoach: Bool,
        text: String,
        mediaKind: MediaKind = .none,
        mediaPath: String? = nil,
        mediaAttachments: [MediaAttachmentReference] = [],
        recordType: ConversationIntent? = nil,
        agentTraceID: UUID? = nil,
        agentStatus: AgentTraceStatus? = nil,
        agentEvents: [AgentTraceSpan] = [],
        agentTurnItems: [AgentTurnItem] = [],
        turnID: UUID? = nil,
        attemptNumber: Int = 0,
        location: LocationSnapshot? = nil,
        effectiveGymID: UUID? = nil
    ) {
        id = UUID()
        self.date = date
        self.sessionID = sessionID
        self.isFromCoach = isFromCoach
        self.text = text
        mediaKindRaw = mediaKind.rawValue
        self.mediaPath = mediaPath
        mediaAttachmentsData = MediaAttachmentStorage.encode(mediaAttachments)
        recordTypeRaw = recordType?.rawValue
        self.agentTraceID = agentTraceID
        agentStatusRaw = agentStatus?.rawValue
        agentEventsData = (try? JSONEncoder().encode(agentEvents)) ?? Data()
        agentTurnItemsData = (try? JSONEncoder().encode(agentTurnItems)) ?? Data()
        self.turnID = turnID
        self.attemptNumber = attemptNumber
        locationData = (try? location.map { try JSONEncoder().encode($0) }) ?? Data()
        self.effectiveGymID = effectiveGymID
    }

    var mediaKind: MediaKind {
        MediaKind(rawValue: mediaKindRaw) ?? .none
    }

    var recordType: ConversationIntent? {
        get { recordTypeRaw.flatMap(ConversationIntent.init(rawValue:)) }
        set { recordTypeRaw = newValue?.rawValue }
    }

    var location: LocationSnapshot? {
        get {
            guard !locationData.isEmpty else { return nil }
            return try? JSONDecoder().decode(LocationSnapshot.self, from: locationData)
        }
        set {
            locationData = (try? newValue.map { try JSONEncoder().encode($0) }) ?? Data()
        }
    }

    var mediaAttachments: [MediaAttachmentReference] {
        get {
            MediaAttachmentStorage.decode(
                mediaAttachmentsData,
                legacyKind: mediaKind,
                legacyPath: mediaPath
            )
        }
        set {
            mediaAttachmentsData = MediaAttachmentStorage.encode(newValue)
            mediaKindRaw = (newValue.first?.kind ?? .none).rawValue
            mediaPath = newValue.first?.path
        }
    }

    var agentStatus: AgentTraceStatus? {
        get { agentStatusRaw.flatMap(AgentTraceStatus.init(rawValue:)) }
        set { agentStatusRaw = newValue?.rawValue }
    }

    var agentEvents: [AgentTraceSpan] {
        (try? JSONDecoder().decode([AgentTraceSpan].self, from: agentEventsData)) ?? []
    }

    var agentTurnItems: [AgentTurnItem] {
        (
            try? JSONDecoder().decode(
                [AgentTurnItem].self,
                from: agentTurnItemsData
            )
        ) ?? []
    }

    func applyAgentEvent(_ event: AgentTraceEvent) {
        var items = agentTurnItems

        switch event {
        case let .assistantTextDelta(itemID, delta):
            if let index = items.firstIndex(where: { $0.id == itemID }) {
                items[index].appendTextDelta(delta)
            } else {
                items.append(AgentTurnItem(
                    id: itemID,
                    sequence: items.count + 1,
                    kind: .text,
                    status: .running,
                    text: delta
                ))
            }
        case let .assistantTextCompleted(itemID, date):
            if let index = items.firstIndex(where: { $0.id == itemID }) {
                items[index].finishText(at: date)
            }
        case let .span(span):
            guard span.kind == .skill || span.kind == .tool else { break }
            if let index = items.firstIndex(where: { $0.id == span.id }) {
                items[index] = AgentTurnItem(
                    span: span,
                    sequence: items[index].sequence
                )
            } else {
                items.append(AgentTurnItem(span: span, sequence: items.count + 1))
            }
            applyLegacyAgentEvent(span)
        case let .completed(_, date):
            for index in items.indices
                where items[index].kind == .text && items[index].status == .running
            {
                items[index].finishText(at: date)
            }
        case let .failed(message, _, date):
            for index in items.indices where items[index].status == .running {
                items[index].fail(message: message, at: date)
            }
            if !items.contains(where: {
                $0.kind == .error && $0.errorMessage == message
            }) {
                items.append(AgentTurnItem(
                    sequence: items.count + 1,
                    kind: .error,
                    status: .failed,
                    title: "执行失败",
                    text: message,
                    startedAt: date,
                    endedAt: date,
                    errorMessage: message
                ))
            }
        }

        agentTurnItemsData = (try? JSONEncoder().encode(items)) ?? agentTurnItemsData
    }

    func applyAgentEvent(_ span: AgentTraceSpan) {
        applyAgentEvent(.span(span))
    }

    private func applyLegacyAgentEvent(_ span: AgentTraceSpan) {
        var current = agentEvents
        if let index = current.firstIndex(where: { $0.id == span.id }) {
            current[index] = span
        } else {
            current.append(span)
        }
        agentEventsData = (try? JSONEncoder().encode(current)) ?? agentEventsData
    }

    func replaceAgentEvents(_ events: [AgentTraceSpan]) {
        agentEventsData = (try? JSONEncoder().encode(events)) ?? agentEventsData
    }

    func replaceAgentTurnItems(_ items: [AgentTurnItem]) {
        var normalized = items
        for index in normalized.indices {
            normalized[index].sequence = index + 1
        }
        agentTurnItemsData = (try? JSONEncoder().encode(normalized)) ?? agentTurnItemsData
    }
}

enum AgentTraceStatus: String, Codable, CaseIterable, Sendable {
    case running
    case succeeded
    case failed
    case cancelled

    var title: String {
        switch self {
        case .running: "执行中"
        case .succeeded: "成功"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
    }
}

enum AgentTraceSpanKind: String, Codable, Hashable, Sendable {
    case model
    case skill
    case tool
    case output

    var title: String {
        switch self {
        case .model: "模型"
        case .skill: "Skill"
        case .tool: "工具"
        case .output: "结果"
        }
    }
}

struct AgentTraceSpan: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var sequence: Int
    var step: Int?
    var kindRaw: String
    var title: String
    var statusRaw: String
    var startedAt: Date
    var endedAt: Date
    var input: String?
    var output: String?
    var metadata: String?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        sequence: Int = 0,
        step: Int? = nil,
        kind: AgentTraceSpanKind,
        title: String,
        status: AgentTraceStatus,
        startedAt: Date,
        endedAt: Date,
        input: String? = nil,
        output: String? = nil,
        metadata: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.step = step
        kindRaw = kind.rawValue
        self.title = title
        statusRaw = status.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.input = input
        self.output = output
        self.metadata = metadata
        self.errorMessage = errorMessage
    }

    var kind: AgentTraceSpanKind {
        AgentTraceSpanKind(rawValue: kindRaw) ?? .output
    }

    var status: AgentTraceStatus {
        AgentTraceStatus(rawValue: statusRaw) ?? .failed
    }

    var durationMilliseconds: Double {
        max(0, endedAt.timeIntervalSince(startedAt) * 1000)
    }
}

enum AgentTraceEvent: Equatable, Sendable {
    case span(AgentTraceSpan)
    case assistantTextDelta(itemID: UUID, delta: String)
    case assistantTextCompleted(itemID: UUID, at: Date)
    case completed(answer: String, at: Date)
    case failed(message: String, cancelled: Bool, at: Date)
}

@Model
final class AgentTrace {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var statusRaw: String
    var provider: String
    var model: String
    var endpoint: String
    var dataSpaceRaw: String
    var userInput: String
    var contextSnapshot: String
    var mediaKindRaw: String
    var imageCount: Int
    var imageAttachmentCount: Int = 0
    var videoAttachmentCount: Int = 0
    var finalAnswer: String?
    var errorMessage: String?
    var spansData: Data
    var turnID: UUID?
    var attemptNumber: Int = 1

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        provider: String,
        model: String,
        endpoint: String,
        dataSpaceRaw: String,
        userInput: String,
        contextSnapshot: String,
        mediaKind: MediaKind,
        imageCount: Int,
        imageAttachmentCount: Int? = nil,
        videoAttachmentCount: Int? = nil,
        turnID: UUID? = nil,
        attemptNumber: Int = 1
    ) {
        self.id = id
        self.startedAt = startedAt
        statusRaw = AgentTraceStatus.running.rawValue
        self.provider = provider
        self.model = model
        self.endpoint = endpoint
        self.dataSpaceRaw = dataSpaceRaw
        self.userInput = userInput
        self.contextSnapshot = contextSnapshot
        mediaKindRaw = mediaKind.rawValue
        self.imageCount = imageCount
        self.imageAttachmentCount = imageAttachmentCount
            ?? (mediaKind == .image ? 1 : 0)
        self.videoAttachmentCount = videoAttachmentCount
            ?? (mediaKind == .video ? 1 : 0)
        self.turnID = turnID
        self.attemptNumber = attemptNumber
        spansData = (try? JSONEncoder().encode([AgentTraceSpan]())) ?? Data()
    }

    var status: AgentTraceStatus {
        get { AgentTraceStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var mediaKind: MediaKind {
        MediaKind(rawValue: mediaKindRaw) ?? .none
    }

    var spans: [AgentTraceSpan] {
        (try? JSONDecoder().decode([AgentTraceSpan].self, from: spansData)) ?? []
    }

    var durationMilliseconds: Double? {
        endedAt.map { max(0, $0.timeIntervalSince(startedAt) * 1000) }
    }

    func apply(_ event: AgentTraceEvent) {
        switch event {
        case var .span(span):
            var current = spans
            if let index = current.firstIndex(where: { $0.id == span.id }) {
                span.sequence = current[index].sequence
                current[index] = span
            } else {
                span.sequence = current.count + 1
                current.append(span)
            }
            spansData = (try? JSONEncoder().encode(current)) ?? spansData
        case .assistantTextDelta, .assistantTextCompleted:
            break
        case let .completed(answer, date):
            status = .succeeded
            endedAt = date
            finalAnswer = answer
            errorMessage = nil
        case let .failed(message, cancelled, date):
            status = cancelled ? .cancelled : .failed
            endedAt = date
            errorMessage = message
        }
    }

    func replaceSpans(_ newSpans: [AgentTraceSpan]) {
        var normalized = newSpans
        for index in normalized.indices {
            normalized[index].sequence = index + 1
        }
        spansData = (try? JSONEncoder().encode(normalized)) ?? spansData
    }
}

struct EquipmentSuggestion: Codable, Identifiable {
    var id = UUID()
    var name: String
    var category: String
    var capabilities: String
    var confidence: Double

    private enum CodingKeys: String, CodingKey {
        case name, category, capabilities, confidence
    }
}

struct GymAnalysis: Codable {
    var summary: String
    var equipment: [EquipmentSuggestion]
}

struct MealAnalysis: Codable {
    var title: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var confidence: Double
    var note: String
}

struct BodyAnalysis: Codable {
    var estimatedWeight: Double?
    var estimatedBodyFat: Double?
    var postureNote: String
    var safetyNote: String

    init(
        estimatedWeight: Double? = nil,
        estimatedBodyFat: Double? = nil,
        postureNote: String,
        safetyNote: String
    ) {
        self.estimatedWeight = estimatedWeight
        self.estimatedBodyFat = estimatedBodyFat
        self.postureNote = postureNote
        self.safetyNote = safetyNote
    }
}

struct WorkoutAnalysis: Codable {
    var exercise: String
    var formScore: Int
    var intensity: String
    var feedback: String
    var safetyNote: String
}

enum ConversationIntent: String, Codable {
    case gym
    case meal
    case body
    case workout
    case switchGym
    case coach

    var recordedLabel: String? {
        switch self {
        case .gym: "已更新健身房"
        case .meal: "已记录饮食"
        case .body: "已记录身体数据"
        case .workout: "已记录训练"
        case .switchGym: "已切换健身房"
        case .coach: nil
        }
    }
}

struct ConversationWorkout: Codable {
    var exercise: String
    var sets: Int?
    var reps: Int?
    var weight: Double?
    var restSeconds: Int?
    var durationMinutes: Int?
    var formScore: Int?
    var intensity: String?
    var feedback: String?
}

struct ConversationResult: Codable {
    var intent: ConversationIntent
    var reply: String
    var gymName: String? = nil
    var gym: GymAnalysis? = nil
    var meal: MealAnalysis? = nil
    var body: BodyAnalysis? = nil
    var workout: ConversationWorkout? = nil
}
