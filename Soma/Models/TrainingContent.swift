import Foundation

/// 动作、课程和计划共用的组合接口。动作带处方，容器引用保持当前内容。
struct TrainingContentSource: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case exercise, course, plan
    }

    var id = UUID()
    var kind: Kind
    var prescription: TemplateExercisePrescription?
    var referenceID: UUID?

    static func exercise(_ value: TemplateExercisePrescription) -> Self {
        Self(kind: .exercise, prescription: value)
    }

    static func course(_ id: UUID) -> Self {
        Self(kind: .course, referenceID: id)
    }

    static func plan(_ id: UUID) -> Self {
        Self(kind: .plan, referenceID: id)
    }
}
