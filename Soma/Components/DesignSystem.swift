import SwiftUI
import UIKit

enum AppTheme {
    static let tint = Color(red: 0.12, green: 0.70, blue: 0.37)
    static let softTint = Color(red: 0.12, green: 0.70, blue: 0.37).opacity(0.12)
    static let warning = Color.orange
    static let cardRadius: CGFloat = 18
    static let pagePadding: CGFloat = 16
}

struct AppCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

struct SectionHeading: View {
    let title: String
    var action: String?
    var onAction: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
            Spacer()
            if let action, let onAction {
                Button(action, action: onAction)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

struct MetricTile: View {
    let icon: String
    let value: String
    let label: String
    var tint: Color = AppTheme.tint

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.bold())
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        AppCard {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 34))
                    .foregroundStyle(AppTheme.tint)
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }
}

struct LoadingButtonLabel: View {
    let title: String
    let isLoading: Bool
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let systemImage {
                Image(systemName: systemImage)
            }
            Text(isLoading ? "AI 正在分析…" : title)
        }
        .fontWeight(.semibold)
        .frame(maxWidth: .infinity)
    }
}

struct LocalImageView: View {
    let path: String?

    var body: some View {
        Group {
            if let image = MediaStore.image(at: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    AppTheme.softTint
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2)
                        .foregroundStyle(AppTheme.tint)
                }
            }
        }
        .clipped()
    }
}

struct MarkdownText: UIViewRepresentable {
    private let markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: UIColor(AppTheme.tint)
        ]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.accessibilityTraits = .staticText
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard textView.attributedText?.string != markdown else { return }
        textView.attributedText = attributedMarkdown
        textView.accessibilityLabel = markdown
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        let width = max(proposal.width ?? 320, 1)
        let height = ceil(uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height)
        return CGSize(width: width, height: height)
    }

    private var attributedMarkdown: NSAttributedString {
        var attributed = (
            try? AttributedString(
                markdown: markdown,
                options: .init(interpretedSyntax: .full)
            )
        ) ?? AttributedString(markdown)
        let runs = attributed.runs.map {
            ($0.range, $0.inlinePresentationIntent)
        }
        for (range, intent) in runs {
            let baseFont = UIFont.preferredFont(forTextStyle: .body)
            let font: UIFont
            if intent?.contains(.code) == true {
                font = UIFont.monospacedSystemFont(
                    ofSize: baseFont.pointSize,
                    weight: .regular
                )
            } else {
                var traits: UIFontDescriptor.SymbolicTraits = []
                if intent?.contains(.stronglyEmphasized) == true {
                    traits.insert(.traitBold)
                }
                if intent?.contains(.emphasized) == true {
                    traits.insert(.traitItalic)
                }
                let descriptor = baseFont.fontDescriptor
                    .withSymbolicTraits(traits)
                    ?? baseFont.fontDescriptor
                font = UIFont(descriptor: descriptor, size: baseFont.pointSize)
            }
            attributed[range].font = font
            attributed[range].foregroundColor = UIColor.label
        }
        return NSAttributedString(attributed)
    }
}

extension View {
    func appPageBackground() -> some View {
        background(Color(uiColor: .systemGroupedBackground))
    }
}
