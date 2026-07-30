import Foundation

enum LocalWorkoutParser {
    static func setEntries(in text: String) -> [WorkoutSetEvidence]? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:kg|公斤)\s*[x×*]\s*(\d+)\s*(?:次)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        let entries = expression.matches(in: text, range: range).compactMap { match -> WorkoutSetEvidence? in
            guard let weightRange = Range(match.range(at: 1), in: text),
                  let repsRange = Range(match.range(at: 2), in: text),
                  let weight = Double(text[weightRange]),
                  let reps = Int(text[repsRange])
            else {
                return nil
            }
            return WorkoutSetEvidence(reps: reps, externalWeightKG: weight)
        }
        return entries.isEmpty ? nil : entries
    }

    static func description(_ workout: ConversationWorkout) -> String {
        var parts = [workout.exercise]
        if let entries = workout.setEntries, !entries.isEmpty {
            parts.append(entries.enumerated().map { index, entry in
                switch (entry.externalWeightKG, entry.reps) {
                case let (.some(weight), .some(reps)):
                    "\(weight.formatted())kg×\(reps)次"
                case let (.some(weight), .none):
                    "第\(index + 1)组 \(weight.formatted())kg"
                case let (.none, .some(reps)):
                    "第\(index + 1)组 \(reps)次"
                case (.none, .none):
                    "第\(index + 1)组"
                }
            }.joined(separator: "，"))
        } else if let sets = workout.sets, let reps = workout.reps {
            parts.append("\(sets)×\(reps)")
        } else {
            if let sets = workout.sets {
                parts.append("\(sets) 组")
            }
            if let reps = workout.reps {
                parts.append("\(reps) 次")
            }
        }
        if workout.setEntries?.isEmpty != false, let weight = workout.weight {
            parts.append(
                weight == 0
                    ? "自重"
                    : "\(weight.formatted(.number.precision(.fractionLength(0 ... 1))))kg"
            )
        }
        if let rest = workout.restSeconds {
            parts.append("间歇 \(rest) 秒")
        }
        return parts.joined(separator: "，")
    }
}
