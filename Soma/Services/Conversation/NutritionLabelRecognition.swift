import Foundation
import Vision

enum NutritionLabelRecognition {
    private static let energyPattern = #/(?i)(?:^|[^\d.,])(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d{1,6}(?:[.,]\d{1,2})?)\s*(k\s*j|k\s*cal|千焦|千卡|大卡)/#
    private static let macroPattern = #/(?i)(\d{1,5}(?:[.,]\d{1,2})?)\s*(mg\b|g\b|毫克|克)/#
    private static let servingPattern = #/(?i)(?:每|per)\s*100\s*(ml|毫升|g|克)|每\s*份|per\s+serving/#
    private static let nutrientNames = [("蛋白质", "protein"), ("脂肪", "fat"), ("碳水", "carbohydrate"), ("钠", "sodium")]

    /// Only read images that this request will send. Preserve the original ordinals on historical references.
    static func context(for images: [Data], history: [AgentConversationExchange] = []) async -> String? {
        let current = images.enumerated().map { (title: "第 \($0.offset + 1) 张", data: $0.element) }
        let referenced = history.flatMap { exchange -> [(title: String, data: Data)] in
            guard let id = exchange.turnID else { return [] }
            return exchange.images.enumerated().map { index, data in
                let ordinal = exchange.referencedImageOrdinal ?? (index + 1)
                return ("历史 [TURN \(id.uuidString.lowercased())] 第 \(ordinal) 张", data)
            }
        }
        let inputs = current + referenced
        guard !inputs.isEmpty else { return nil }
        let worker = Task.detached(priority: .utility) {
            let groups = inputs.compactMap { input -> String? in
                guard !Task.isCancelled else { return nil }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                do {
                    try VNImageRequestHandler(data: input.data).perform([request])
                } catch {
                    return nil
                }
                let summary = summarize(observations: request.results ?? [])
                if summary.isEmpty {
                    return nil
                }
                return "\(input.title)：\(summary.joined(separator: "；"))"
            }
            return groups.isEmpty ? nil : (["包装标签的设备文本证据。逐张独立对应，按包装列标题与实际份量核对。"] + groups).joined(separator: "\n")
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private struct RecognizedLine {
        let candidate: VNRecognizedText
        let bounds: CGRect
        let text: String

        func bounds(of range: Range<String.Index>, in text: String) -> CGRect? {
            let original = candidate.string
            guard text.utf16.count == original.utf16.count,
                  let range = Range(NSRange(range, in: text), in: original)
            else { return nil }
            return try? candidate.boundingBox(for: range)?.boundingBox
        }
    }

    private struct Column {
        let title: String
        let bounds: CGRect

        var start: CGFloat {
            bounds.minX
        }

        func contains(_ leading: CGFloat, leftTolerance: CGFloat) -> Bool {
            // Right alignment can put a short number past the heading's center.
            let rightTolerance = max(0.045, bounds.width * 0.4)
            return leading >= start - leftTolerance && leading <= bounds.maxX + rightTolerance
        }
    }

    private static func summarize(observations: [VNRecognizedTextObservation]) -> [String] {
        let lines = observations.compactMap { observation in
            observation.topCandidates(1).first.map { RecognizedLine(candidate: $0, bounds: observation.boundingBox, text: fold($0.string)) }
        }.sorted { $0.bounds.midY > $1.bounds.midY }
        var groups: [[RecognizedLine]] = []
        for line in lines {
            if let index = groups.indices.last, let first = groups[index].first,
               abs(first.bounds.midY - line.bounds.midY) <= min(first.bounds.height, line.bounds.height) * 0.6
            {
                groups[index].append(line)
            } else {
                groups.append([line])
            }
        }
        let rows = groups.map { $0.sorted { $0.bounds.minX < $1.bounds.minX } }
        let headings = rows.enumerated().compactMap { index, row -> (Int, [Column])? in
            let columns = row.flatMap { line in
                let text = line.text
                return text.matches(of: servingPattern).compactMap { match -> Column? in
                    line.bounds(of: match.range, in: text).map { Column(title: servingName(match.1), bounds: $0) }
                }
            }.sorted { $0.start < $1.start }
            return columns.isEmpty ? nil : (index, columns)
        }
        if headings.count == 1, let (headerRow, columns) = headings.first, columns.count <= 3,
           Set(columns.map(\.title)).count == columns.count,
           zip(columns, columns.dropFirst()).allSatisfy({ first, second in second.start - first.start >= 0.1 })
        {
            let bases = columns.map { "包装标有\($0.title)" }
            let measurements = rows.dropFirst(headerRow + 1).prefix(12).map { values(in: $0, columns: columns) }
            let evidence = measurements.flatMap(\.evidence)
            if measurements.contains(where: \.unassigned) {
                return bases + evidence.prefix(16) + ["部分数值无法对应列标题，请核对原图。"]
            }
            return evidence.isEmpty ? bases + ["该列的营养值无法可靠辨认。"] : bases + evidence.prefix(16)
        }
        let fallback = summarize(rows.flatMap { $0.map(\.text) })
        let hasUnresolvedColumns = fallback.filter { $0.hasPrefix("包装标有") }.count > 1
            || headings.count > 1 || headings.contains { $0.1.count > 1 }
        return hasUnresolvedColumns
            ? ["列位置无法核实，按原图分别确认份量与数值。"] + fallback : fallback
    }

    private static func values(in row: [RecognizedLine], columns: [Column]) -> (evidence: [String], unassigned: Bool) {
        let lower = row.map { $0.text.lowercased() }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let energyRow = lower.hasPrefix("能量") || lower.hasPrefix("energy") || lower.hasPrefix("calories")
        let nutrient = lower.hasPrefix("total ") ? String(lower.dropFirst("total ".count)) : lower
        let label = energyRow ? "能量" : nutrientNames.first { nutrient.hasPrefix($0.0) || nutrient.hasPrefix($0.1) }?.0
        guard let label else { return ([], false) }
        let tolerance: CGFloat = columns.count == 1 ? 0.1 : 0.04
        var amounts: [Int: [String]] = [:]
        var energies: [Int: [EnergyAmount]] = [:]
        var unassigned = false
        for line in row {
            let text = line.text
            if energyRow {
                var previous: (column: Int, end: CGFloat, kilojoules: Bool)?
                for match in text.matches(of: energyPattern).prefix(4) {
                    guard let bounds = line.bounds(of: match.1.startIndex ..< match.2.endIndex, in: text),
                          let amount = EnergyAmount(value: match.1, unit: match.2)
                    else {
                        previous = nil
                        unassigned = true
                        continue
                    }
                    let aligned = columns.lastIndex { $0.contains(bounds.minX, leftTolerance: tolerance) }
                    let adjacent = previous.flatMap { preceding in
                        bounds.minX - preceding.end <= 0.035 && amount.kilojoules != preceding.kilojoules
                            ? preceding.column : nil
                    }
                    guard let column = aligned ?? adjacent else {
                        previous = nil
                        unassigned = true
                        continue
                    }
                    energies[column, default: []].append(amount)
                    previous = (column, bounds.maxX, amount.kilojoules)
                }
            } else {
                for match in text.matches(of: macroPattern).prefix(4) {
                    guard let bounds = line.bounds(of: match.range, in: text),
                          let column = columns.lastIndex(where: { $0.contains(bounds.minX, leftTolerance: tolerance) })
                    else {
                        unassigned = true
                        continue
                    }
                    amounts[column, default: []].append("\(match.1) \(match.2)")
                }
            }
        }
        let evidence: [String] = columns.enumerated().compactMap { index, column in
            if let values = energies[index], !values.isEmpty {
                return "\(column.title) \(label) " + energyText(values)
            }
            return amounts[index]?.first.map { "\(column.title) \(label) \($0)" }
        }
        return (evidence, unassigned)
    }

    private struct EnergyAmount {
        let numericText: String
        let value: Double
        let kilojoules: Bool

        init?(value printed: Substring, unit: Substring) {
            let segments = printed.split(separator: ",")
            let grouped = segments.count > 1 && segments.dropFirst().allSatisfy { $0.prefix(while: \.isNumber).count == 3 }
            numericText = printed.replacingOccurrences(of: ",", with: grouped ? "" : ".")
            guard let value = Double(numericText), value.isFinite else { return nil }
            self.value = value
            let normalized = unit.lowercased().replacingOccurrences(of: " ", with: "")
            kilojoules = normalized == "kj" || normalized == "千焦"
        }

        var text: String {
            guard kilojoules else { return "\(numericText) kcal" }
            let converted = (value / 4.184).formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0 ... 2)))
            return "\(numericText) kJ（换算约 \(converted) kcal）"
        }
    }

    private static func energyText(_ values: [EnergyAmount]) -> String {
        let text = values.map(\.text).joined(separator: " / ")
        guard let kj = values.first(where: \.kilojoules)?.value,
              let kcal = values.first(where: { !$0.kilojoules })?.value,
              abs(kj / 4.184 - kcal) > max(1, kcal * 0.02)
        else { return text }
        return text + "（两单位不一致，需核对）"
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func servingName(_ unit: Substring?) -> String {
        switch unit?.lowercased() {
        case "ml", "毫升": "每 100 mL"
        case "g", "克": "每 100 g"
        default: "每份"
        }
    }

    static func summarize(_ lines: [String]) -> [String] {
        let folded = lines.map(fold)
        let headerRun = folded.filter { line in
            let lower = line.lowercased()
            return ["每100", "每 100", "每份", "per 100", "per serving", "营养成分", "nutrition facts"].contains { lower.contains($0) }
        }
        // A standalone number from a gym machine or package front is insufficient as nutrition evidence.
        guard !headerRun.isEmpty || folded.contains(where: { $0.contains("能量") || $0.lowercased().contains("energy") }) else {
            return []
        }
        var basis: [String] = []
        for match in headerRun.prefix(4).flatMap({ $0.matches(of: servingPattern) }) {
            let label = "包装标有" + servingName(match.1)
            if !basis.contains(label) {
                basis.append(label)
            }
        }
        let energies = folded.flatMap { line in
            line.matches(of: energyPattern).prefix(4).compactMap { EnergyAmount(value: $0.1, unit: $0.2)?.text }
        }
        let nutrients = folded.compactMap { line -> String? in
            let lower = line.lowercased()
            guard let name = nutrientNames.first(where: { lower.contains($0.0) || lower.contains($0.1) })?.0 else { return nil }
            let values = line.matches(of: macroPattern).prefix(3).map { String($0.1) + " " + String($0.2) }
            return values.isEmpty ? nil : "\(name) \(values.joined(separator: " / "))"
        }
        return Array((basis + energies + nutrients).prefix(18))
    }
}
