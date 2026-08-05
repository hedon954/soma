@testable import Soma
import XCTest

/// ADR 0046：动作建议一步到位，合并规则本地确定、不为缺失历史编造数值。
final class ExerciseInputSuggestionBuilderTests: XCTestCase {
    private let benchID = UUID()
    private let inclineID = UUID()
    private let archivedID = UUID()

    func testSuggestionMergesExerciseAndLatestCapacityInOneRow() {
        let suggestions = ExerciseInputSuggestionBuilder.suggestions(
            query: "卧推",
            exercises: exercises(),
            recentCapacities: [
                capacity(benchID, day: 1, text: "50kg × 10 × 3组"),
                capacity(benchID, day: 5, text: "60kg × 8 × 4组")
            ]
        )

        XCTAssertEqual(suggestions.count, 2)
        let bench = try? XCTUnwrap(suggestions.first { $0.id == benchID })
        XCTAssertEqual(bench?.recentSummary, "60kg × 8 × 4组")
        XCTAssertEqual(bench?.draftText, "卧推：60kg × 8 × 4组")
    }

    func testSuggestionWithoutHistoryOnlyGivesExerciseName() {
        let suggestions = ExerciseInputSuggestionBuilder.suggestions(
            query: "上斜",
            exercises: exercises(),
            recentCapacities: []
        )

        XCTAssertEqual(suggestions.map(\.draftText), ["上斜卧推"])
        XCTAssertNil(suggestions.first?.recentSummary)
        XCTAssertNil(suggestions.first?.recentDate)
    }

    func testEmptyCapacityTextIsIgnored() {
        let suggestions = ExerciseInputSuggestionBuilder.suggestions(
            query: "卧推",
            exercises: exercises(),
            recentCapacities: [
                capacity(benchID, day: 1, text: "50kg × 10 × 3组"),
                capacity(benchID, day: 9, text: "")
            ]
        )

        XCTAssertEqual(
            suggestions.first { $0.id == benchID }?.recentSummary,
            "50kg × 10 × 3组"
        )
    }

    func testArchivedExercisesAndEmptyQueryProduceNoSuggestions() {
        XCTAssertTrue(
            ExerciseInputSuggestionBuilder.suggestions(
                query: "已归档",
                exercises: exercises(),
                recentCapacities: []
            ).isEmpty
        )
        XCTAssertTrue(
            ExerciseInputSuggestionBuilder.suggestions(
                query: "   ",
                exercises: exercises(),
                recentCapacities: []
            ).isEmpty
        )
    }

    func testPrefixMatchesAndRecentHistoryRankFirstWithinLimit() {
        let names = (0 ..< 8).map { index in
            ExerciseInputSuggestionBuilder.ExerciseInput(
                id: UUID(),
                name: "颈前推举\(index)"
            )
        }
        let prefixMatch = ExerciseInputSuggestionBuilder.ExerciseInput(
            id: UUID(),
            name: "推举优先"
        )

        let suggestions = ExerciseInputSuggestionBuilder.suggestions(
            query: "推举",
            exercises: names + [prefixMatch],
            recentCapacities: []
        )

        XCTAssertEqual(suggestions.count, ExerciseInputSuggestionBuilder.defaultLimit)
        XCTAssertEqual(suggestions.first?.id, prefixMatch.id)
    }

    func testSameInputProducesSameOrder() {
        let capacities = [
            capacity(benchID, day: 3, text: "60kg × 8 × 4组"),
            capacity(inclineID, day: 7, text: "40kg × 10 × 3组")
        ]
        let first = ExerciseInputSuggestionBuilder.suggestions(
            query: "卧推",
            exercises: exercises(),
            recentCapacities: capacities
        )
        let second = ExerciseInputSuggestionBuilder.suggestions(
            query: "卧推",
            exercises: exercises(),
            recentCapacities: capacities
        )

        XCTAssertEqual(first, second)
        // 前缀命中优先于更近的训练历史，保证「输入什么就先看到什么」。
        XCTAssertEqual(first.map(\.id), [benchID, inclineID])
    }

    private func exercises() -> [ExerciseInputSuggestionBuilder.ExerciseInput] {
        [
            .init(id: benchID, name: "卧推"),
            .init(id: inclineID, name: "上斜卧推"),
            .init(id: archivedID, name: "已归档卧推", isArchived: true)
        ]
    }

    private func capacity(
        _ exerciseID: UUID,
        day: Int,
        text: String
    ) -> ExerciseInputSuggestionBuilder.RecentCapacityInput {
        ExerciseInputSuggestionBuilder.RecentCapacityInput(
            exerciseID: exerciseID,
            date: Date(timeIntervalSince1970: Double(day) * 86400),
            text: text
        )
    }
}
