import Foundation

/// Default model text is shipped as Markdown in the application bundle.
enum SomaPrompt {
    private static let placeholders = /\{\{([a-z][a-z0-9_]*)\}\}/

    private static let templates: [String: String] = {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Prompts", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else {
            preconditionFailure("The Soma bundle is missing its Prompts resources.")
        }
        var result: [String: String] = [:]
        for file in files where file.pathExtension == "md" {
            guard let markdown = try? String(contentsOf: file, encoding: .utf8), markdown.hasSuffix("\n") else {
                preconditionFailure("Cannot read prompt resource \(file.lastPathComponent).")
            }
            result[file.deletingPathExtension().lastPathComponent] = markdown
        }
        return result
    }()

    /// Insert values once so user text containing placeholder syntax stays literal.
    static func text(_ key: String, _ values: [String: String] = [:]) -> String {
        guard let template = templates[key] else {
            preconditionFailure("Missing bundled prompt: \(key)")
        }
        let matches = template.matches(of: placeholders)
        precondition(Set(matches.map { String($0.1) }) == Set(values.keys), "Prompt arguments do not match: \(key)")
        guard !matches.isEmpty else { return template }
        var result = ""
        var start = template.startIndex
        for match in matches {
            result += template[start ..< match.range.lowerBound]
            result += values[String(match.1), default: ""]
            start = match.range.upperBound
        }
        result += template[start...]
        return result
    }
}
