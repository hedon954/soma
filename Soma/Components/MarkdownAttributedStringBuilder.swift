import Foundation
import UIKit

/// Rebuilds markdown into an `NSAttributedString` that preserves paragraph and list
/// breaks. `AttributedString(markdown:interpretedSyntax: .full)` stores structure in
/// `presentationIntent` and strips newlines from the character buffer; converting that
/// buffer alone collapses coach replies into a single glued block.
enum MarkdownAttributedStringBuilder {
    static func attributedString(from markdown: String) -> NSAttributedString {
        guard let parsed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .full)
        ) else {
            return styledPlainText(markdown)
        }

        var rebuilt = AttributedString()
        var previousParagraphIdentity: Int?
        var previousListItemIdentity: Int?
        var previousWasListItem = false

        for run in parsed.runs {
            let intent = run.attributes.presentationIntent
            let paragraphIdentity = paragraphIdentity(in: intent)
            let listItemIdentity = listItemIdentity(in: intent)
            let listOrdinal = listItemOrdinal(in: intent)
            let isUnordered = containsUnorderedList(in: intent)
            let isListItem = listItemIdentity != nil

            if let previous = previousListItemIdentity,
               let current = listItemIdentity,
               previous != current
            {
                rebuilt.append(AttributedString("\n"))
            } else if let previous = previousParagraphIdentity,
                      let current = paragraphIdentity,
                      previous != current
            {
                rebuilt.append(AttributedString(previousWasListItem && isListItem ? "\n" : "\n\n"))
            }

            if let ordinal = listOrdinal,
               listItemIdentity != previousListItemIdentity
            {
                let prefix = isUnordered ? "• " : "\(ordinal). "
                rebuilt.append(AttributedString(prefix))
            }

            var fragment = AttributedString(parsed[run.range])
            applyInlineStyle(&fragment, intent: run.attributes.inlinePresentationIntent)
            rebuilt.append(fragment)

            if let paragraphIdentity {
                previousParagraphIdentity = paragraphIdentity
            }
            if let listItemIdentity {
                previousListItemIdentity = listItemIdentity
            }
            previousWasListItem = isListItem
        }

        if rebuilt.characters.isEmpty {
            return styledPlainText(markdown)
        }
        return NSAttributedString(rebuilt)
    }

    /// Exposed for deterministic tests that assert reconstructed newlines and list markers.
    static func plainString(from markdown: String) -> String {
        attributedString(from: markdown).string
    }

    private static func styledPlainText(_ text: String) -> NSAttributedString {
        let font = UIFont.preferredFont(forTextStyle: .body)
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: UIColor.label
        ])
    }

    private static func applyInlineStyle(
        _ fragment: inout AttributedString,
        intent: InlinePresentationIntent?
    ) {
        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        let font: UIFont
        if intent?.contains(.code) == true {
            font = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
        } else {
            var traits: UIFontDescriptor.SymbolicTraits = []
            if intent?.contains(.stronglyEmphasized) == true {
                traits.insert(.traitBold)
            }
            if intent?.contains(.emphasized) == true {
                traits.insert(.traitItalic)
            }
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
                ?? baseFont.fontDescriptor
            font = UIFont(descriptor: descriptor, size: baseFont.pointSize)
        }

        let range = fragment.startIndex ..< fragment.endIndex
        fragment[range].font = font
        fragment[range].foregroundColor = UIColor.label
    }

    private static func paragraphIdentity(in intent: PresentationIntent?) -> Int? {
        intent?.components.first(where: {
            if case .paragraph = $0.kind {
                return true
            }
            return false
        })?.identity
    }

    private static func containsUnorderedList(in intent: PresentationIntent?) -> Bool {
        intent?.components.contains(where: {
            if case .unorderedList = $0.kind {
                return true
            }
            return false
        }) == true
    }

    private static func listItemIdentity(in intent: PresentationIntent?) -> Int? {
        intent?.components.first(where: {
            if case .listItem = $0.kind {
                return true
            }
            return false
        })?.identity
    }

    private static func listItemOrdinal(in intent: PresentationIntent?) -> Int? {
        guard let component = intent?.components.first(where: {
            if case .listItem = $0.kind {
                return true
            }
            return false
        }) else {
            return nil
        }
        if case let .listItem(ordinal) = component.kind {
            return ordinal
        }
        return nil
    }
}
