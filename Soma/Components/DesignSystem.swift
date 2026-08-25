import SwiftUI
import UIKit

enum AppAppearancePreference: String, CaseIterable, Identifiable {
    static let defaultsKey = "ui.appearance"

    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func stored(_ rawValue: String) -> AppAppearancePreference {
        AppAppearancePreference(rawValue: rawValue) ?? .system
    }
}

enum AppAppearancePolicy {
    static func rootColorScheme(storedRawValue: String) -> ColorScheme? {
        AppAppearancePreference.stored(storedRawValue).preferredColorScheme
    }

    static let mediaViewerColorScheme: ColorScheme = .dark
}

/// 可测试的 sRGB 色值。主题颜色先以纯数值定义，再映射到 SwiftUI，避免
/// 业务 View 自己拼颜色，也让对比度门禁不依赖运行时 trait collection。
struct AppThemeRGB: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

/// Soma 的双主题色板。黑白承担页面、导航和主操作；彩色只用于业务类别、
/// 指标与状态等少量语义图标或数据标记，不能扩张成页面主色。
enum AppThemePalette {
    // Surfaces
    static let lightPage = AppThemeRGB(hex: 0xFFFFFF)
    static let darkPage = AppThemeRGB(hex: 0x000000)
    static let lightCard = AppThemeRGB(hex: 0xF7F7F7)
    static let darkCard = AppThemeRGB(hex: 0x191919)
    static let lightInset = AppThemeRGB(hex: 0xEFEFEF)
    static let darkInset = AppThemeRGB(hex: 0x232323)
    static let lightSeparator = AppThemeRGB(hex: 0xDCDCDC)
    static let darkSeparator = AppThemeRGB(hex: 0x303030)

    // Interaction
    static let lightAccent = AppThemeRGB(hex: 0x000000)
    static let darkAccent = AppThemeRGB(hex: 0xFFFFFF)
    static let lightAccentEmphasis = AppThemeRGB(hex: 0x000000)
    static let darkAccentEmphasis = AppThemeRGB(hex: 0xFFFFFF)
    static let lightOnAccent = AppThemeRGB(hex: 0xFFFFFF)
    static let darkOnAccent = AppThemeRGB(hex: 0x000000)
    static let lightAccentSoft = AppThemeRGB(hex: 0xF0F0F0)
    static let darkAccentSoft = AppThemeRGB(hex: 0x262626)

    // Record categories. Pure-white light surfaces use higher-chroma accents so
    // small icons stay crisp without lowering normal-text contrast below 4.5:1.
    // Dark accents already gain visual brightness from the black surface and stay unchanged.
    static let lightTraining = AppThemeRGB(hex: 0xC65000)
    static let darkTraining = AppThemeRGB(hex: 0xFF922B)
    static let lightTrainingEmphasis = AppThemeRGB(hex: 0x843A00)
    static let darkTrainingEmphasis = AppThemeRGB(hex: 0x843A00)
    static let lightTrainingSoft = AppThemeRGB(hex: 0xFFEFE0)
    static let darkTrainingSoft = AppThemeRGB(hex: 0x352315)
    static let lightMeal = AppThemeRGB(hex: 0x00854A)
    static let darkMeal = AppThemeRGB(hex: 0x24D77A)
    static let lightMealSoft = AppThemeRGB(hex: 0xE4F8ED)
    static let darkMealSoft = AppThemeRGB(hex: 0x173025)
    static let lightBody = AppThemeRGB(hex: 0x0072C6)
    static let darkBody = AppThemeRGB(hex: 0x66B8F0)
    static let lightBodySoft = AppThemeRGB(hex: 0xE6F3FC)
    static let darkBodySoft = AppThemeRGB(hex: 0x182B38)
    static let lightTrend = AppThemeRGB(hex: 0x753DB8)
    static let darkTrend = AppThemeRGB(hex: 0xB58CFF)
    static let lightTrendSoft = AppThemeRGB(hex: 0xF2EAFB)
    static let darkTrendSoft = AppThemeRGB(hex: 0x2C2138)

    // Metrics. A record category answers “what is this”; a metric answers
    // “what is being measured”. Training metrics therefore do not all inherit orange.
    static let lightConsistency = AppThemeRGB(hex: 0x00838B)
    static let darkConsistency = AppThemeRGB(hex: 0x31C9D1)
    static let lightConsistencySoft = AppThemeRGB(hex: 0xE2F7F8)
    static let darkConsistencySoft = AppThemeRGB(hex: 0x163033)
    static let lightRecovery = AppThemeRGB(hex: 0x27803B)
    static let darkRecovery = AppThemeRGB(hex: 0x6FD47A)
    static let lightRecoverySoft = AppThemeRGB(hex: 0xE7F7E9)
    static let darkRecoverySoft = AppThemeRGB(hex: 0x1A3020)
    static let lightVital = AppThemeRGB(hex: 0xB43F34)
    static let darkVital = AppThemeRGB(hex: 0xFF6B5B)
    static let lightVitalSoft = AppThemeRGB(hex: 0xFCE9E7)
    static let darkVitalSoft = AppThemeRGB(hex: 0x38201D)

    // Feedback states
    static let lightWarning = AppThemeRGB(hex: 0x835A00)
    static let darkWarning = AppThemeRGB(hex: 0xF2C94C)
    static let warningEmphasis = AppThemeRGB(hex: 0x80601F)
    static let lightWarningSoft = AppThemeRGB(hex: 0xFFF5D3)
    static let darkWarningSoft = AppThemeRGB(hex: 0x332C17)
}

enum AppTheme {
    /// 主交互始终是黑白。类别、指标与状态分别使用自己的语义色。
    static let accent = adaptiveColor(
        light: AppThemePalette.lightAccent,
        dark: AppThemePalette.darkAccent
    )
    static let tint = accent
    /// 白色前景的实心控件必须使用强调底色，不能直接把较亮的深色主题 `accent`
    /// 当作按钮底色，否则会失去对比度。
    static let accentEmphasis = adaptiveColor(
        light: AppThemePalette.lightAccentEmphasis,
        dark: AppThemePalette.darkAccentEmphasis
    )
    static let onAccent = adaptiveColor(
        light: AppThemePalette.lightOnAccent,
        dark: AppThemePalette.darkOnAccent
    )
    static let softTint = adaptiveColor(
        light: AppThemePalette.lightAccentSoft,
        dark: AppThemePalette.darkAccentSoft
    )
    static let trainingAccent = adaptiveColor(
        light: AppThemePalette.lightTraining,
        dark: AppThemePalette.darkTraining
    )
    static let trainingEmphasis = adaptiveColor(
        light: AppThemePalette.lightTrainingEmphasis,
        dark: AppThemePalette.darkTrainingEmphasis
    )
    static let trainingSoftTint = adaptiveColor(
        light: AppThemePalette.lightTrainingSoft,
        dark: AppThemePalette.darkTrainingSoft
    )
    static let mealAccent = adaptiveColor(
        light: AppThemePalette.lightMeal,
        dark: AppThemePalette.darkMeal
    )
    static let mealSoftTint = adaptiveColor(
        light: AppThemePalette.lightMealSoft,
        dark: AppThemePalette.darkMealSoft
    )
    static let bodyAccent = adaptiveColor(
        light: AppThemePalette.lightBody,
        dark: AppThemePalette.darkBody
    )
    static let bodySoftTint = adaptiveColor(
        light: AppThemePalette.lightBodySoft,
        dark: AppThemePalette.darkBodySoft
    )
    static let trendAccent = adaptiveColor(
        light: AppThemePalette.lightTrend,
        dark: AppThemePalette.darkTrend
    )
    static let trendSoftTint = adaptiveColor(
        light: AppThemePalette.lightTrendSoft,
        dark: AppThemePalette.darkTrendSoft
    )
    static let consistencyAccent = adaptiveColor(
        light: AppThemePalette.lightConsistency,
        dark: AppThemePalette.darkConsistency
    )
    static let consistencySoftTint = adaptiveColor(
        light: AppThemePalette.lightConsistencySoft,
        dark: AppThemePalette.darkConsistencySoft
    )
    static let recoveryAccent = adaptiveColor(
        light: AppThemePalette.lightRecovery,
        dark: AppThemePalette.darkRecovery
    )
    static let recoverySoftTint = adaptiveColor(
        light: AppThemePalette.lightRecoverySoft,
        dark: AppThemePalette.darkRecoverySoft
    )
    static let vitalAccent = adaptiveColor(
        light: AppThemePalette.lightVital,
        dark: AppThemePalette.darkVital
    )
    static let vitalSoftTint = adaptiveColor(
        light: AppThemePalette.lightVitalSoft,
        dark: AppThemePalette.darkVitalSoft
    )
    static let success = mealAccent
    static let warning = adaptiveColor(
        light: AppThemePalette.lightWarning,
        dark: AppThemePalette.darkWarning
    )
    static let warningEmphasis = Color(uiColor: AppThemePalette.warningEmphasis.uiColor)
    static let warningSoftTint = adaptiveColor(
        light: AppThemePalette.lightWarningSoft,
        dark: AppThemePalette.darkWarningSoft
    )
    static let destructive = Color.red

    static let pageBackground = adaptiveColor(
        light: AppThemePalette.lightPage,
        dark: AppThemePalette.darkPage
    )
    static let cardBackground = adaptiveColor(
        light: AppThemePalette.lightCard,
        dark: AppThemePalette.darkCard
    )
    static let insetBackground = adaptiveColor(
        light: AppThemePalette.lightInset,
        dark: AppThemePalette.darkInset
    )
    static let separator = adaptiveColor(
        light: AppThemePalette.lightSeparator,
        dark: AppThemePalette.darkSeparator
    )

    // MARK: - 圆角 token（PRD 020）

    /// 卡片、画廊大图与浮层容器。
    static let cardRadius: CGFloat = 18
    /// 行内缩略图、小控件与胶囊以外的次级容器。
    static let controlRadius: CGFloat = 12

    static let pagePadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let groupSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 20
    static let minimumTapTarget: CGFloat = 44
    /// 输入和编辑表面需要比普通卡片边界更明确，尤其是在纯白浅色页面上。
    static let inputBorderWidth: CGFloat = 1
    /// 阅读与编辑表面在 iPad 上保持合适行宽，避免卡片横向无限拉伸。
    static let readableContentMaxWidth: CGFloat = 720

    // MARK: - 列表密度规范（PRD 020）

    /// 列表行缩略图统一尺寸；副文案一行截断，行上下 padding 用
    /// `listRowVerticalPadding`。低频操作统一收进工具栏 `ellipsis.circle` 菜单。
    static let listThumbnailSize = CGSize(width: 48, height: 54)
    static let listRowVerticalPadding: CGFloat = 4

    private static func adaptiveColor(light: AppThemeRGB, dark: AppThemeRGB) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark.uiColor : light.uiColor
        })
    }
}

/// 系统 `borderedProminent` 会从根 `tint` 推导实心底色，却不保证在自适应
/// 黑白主题下同步切换前景。所有 Soma 实心主操作都通过这里明确绑定反色前景，
/// 避免深色模式出现白底白字。
private struct AppFilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.72))
            .padding(.horizontal, 16)
            .frame(minHeight: AppTheme.minimumTapTarget)
            .background(
                background.opacity(isEnabled ? 1 : 0.34),
                in: RoundedRectangle(
                    cornerRadius: AppTheme.controlRadius,
                    style: .continuous
                )
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: AppTheme.controlRadius,
                    style: .continuous
                )
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func appPrimaryButtonStyle() -> some View {
        buttonStyle(AppFilledButtonStyle(
            background: AppTheme.accent,
            foreground: AppTheme.onAccent
        ))
    }

    func appDestructivePrimaryButtonStyle() -> some View {
        buttonStyle(AppFilledButtonStyle(
            background: AppTheme.destructive,
            foreground: .white
        ))
    }
}

/// 业务语义颜色的唯一入口。黑白只负责导航、文字、选择与主操作；
/// 训练、饮食、身体和趋势等数据标记必须显式声明角色。
enum AppSemanticRole: String, CaseIterable, Sendable {
    case training
    case meal
    case body
    case trend
    case warning

    var accent: Color {
        switch self {
        case .training: AppTheme.trainingAccent
        case .meal: AppTheme.mealAccent
        case .body: AppTheme.bodyAccent
        case .trend: AppTheme.trendAccent
        case .warning: AppTheme.warning
        }
    }

    var softTint: Color {
        switch self {
        case .training: AppTheme.trainingSoftTint
        case .meal: AppTheme.mealSoftTint
        case .body: AppTheme.bodySoftTint
        case .trend: AppTheme.trendSoftTint
        case .warning: AppTheme.warningSoftTint
        }
    }
}

/// 数据可视化角色。它独立于记录类别：训练记录可以同时包含青色频率、
/// 橙色容量、绿色恢复、紫色表现和珊瑚色生命体征。
enum AppMetricRole: String, CaseIterable, Sendable {
    case consistency
    case trainingLoad
    case recovery
    case performance
    case body
    case vital

    var accent: Color {
        switch self {
        case .consistency: AppTheme.consistencyAccent
        case .trainingLoad: AppTheme.trainingAccent
        case .recovery: AppTheme.recoveryAccent
        case .performance: AppTheme.trendAccent
        case .body: AppTheme.bodyAccent
        case .vital: AppTheme.vitalAccent
        }
    }

    var softTint: Color {
        switch self {
        case .consistency: AppTheme.consistencySoftTint
        case .trainingLoad: AppTheme.trainingSoftTint
        case .recovery: AppTheme.recoverySoftTint
        case .performance: AppTheme.trendSoftTint
        case .body: AppTheme.bodySoftTint
        case .vital: AppTheme.vitalSoftTint
        }
    }

    var systemImage: String {
        switch self {
        case .consistency: "calendar.badge.checkmark"
        case .trainingLoad: "chart.bar.xaxis.ascending"
        case .recovery: "heart.circle"
        case .performance: "trophy"
        case .body: "scalemass"
        case .vital: "waveform.path.ecg"
        }
    }
}

/// 状态色只表达结果，不替代指标色。具有确定阈值时，状态色可以覆盖单个
/// 数据点或区间；没有阈值时，图表保持单一指标色。
enum AppStatusRole: String, CaseIterable, Sendable {
    case positive
    case attention
    case critical
    case neutral

    var accent: Color {
        switch self {
        case .positive: AppTheme.recoveryAccent
        case .attention: AppTheme.warning
        case .critical: AppTheme.vitalAccent
        case .neutral: Color.secondary
        }
    }

    var softTint: Color {
        switch self {
        case .positive: AppTheme.recoverySoftTint
        case .attention: AppTheme.warningSoftTint
        case .critical: AppTheme.vitalSoftTint
        case .neutral: AppTheme.softTint
        }
    }

    var systemImage: String {
        switch self {
        case .positive: "checkmark.circle"
        case .attention: "exclamationmark.circle"
        case .critical: "exclamationmark.triangle"
        case .neutral: "minus.circle"
        }
    }
}

/// 统一业务入口图标的颜色、底色和尺寸，避免列表重新退化成一排黑色 logo。
struct SemanticIconBadge: View {
    let systemImage: String
    let role: AppSemanticRole
    var size: CGFloat = 36
    var cornerRadius: CGFloat?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: max(14, size * 0.4), weight: .semibold))
            .foregroundStyle(role.accent)
            .frame(width: size, height: size)
            .background {
                if let cornerRadius {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(role.softTint)
                } else {
                    Circle().fill(role.softTint)
                }
            }
            .accessibilityHidden(true)
    }
}

/// 指标标题保持文字中性，仅让图标与数据轨迹承载指标色。
struct MetricHeading: View {
    let title: String
    let role: AppMetricRole
    var font: Font = .headline

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: role.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(role.accent)
                .frame(width: 22)
            Text(title)
                .font(font)
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatusIconBadge: View {
    let role: AppStatusRole
    var size: CGFloat = 46

    var body: some View {
        Image(systemName: role.systemImage)
            .font(.system(size: max(16, size * 0.42), weight: .semibold))
            .foregroundStyle(role.accent)
            .frame(width: size, height: size)
            .background(role.softTint, in: Circle())
            .accessibilityHidden(true)
    }
}

struct AppCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(AppTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(AppTheme.separator, lineWidth: 0.5)
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
                    .frame(minHeight: AppTheme.minimumTapTarget)
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
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

struct LocalImageView: View {
    let path: String?
    var maxPixelSize = 1024

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    AppTheme.trainingSoftTint
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2)
                        .foregroundStyle(AppTheme.trainingAccent)
                }
            }
        }
        .clipped()
        .task(id: path) {
            image = nil
            let loaded = await ImagePipeline.shared.image(
                atStoredPath: path,
                maxPixelSize: maxPixelSize
            )
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

struct PendingImagePreview: View {
    let id: UUID
    let data: Data

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.12)
            }
        }
        .task(id: id) {
            let loaded = await ImagePipeline.shared.image(
                data: data,
                cacheKey: id.uuidString,
                maxPixelSize: 256
            )
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

struct MarkdownText: UIViewRepresentable {
    private let markdown: String
    private let textStyle: UIFont.TextStyle
    private let weight: UIFont.Weight

    init(
        _ markdown: String,
        textStyle: UIFont.TextStyle = .body,
        weight: UIFont.Weight = .regular
    ) {
        self.markdown = markdown
        self.textStyle = textStyle
        self.weight = weight
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
        guard context.coordinator.renderedMarkdown != markdown else { return }
        let attributed = MarkdownAttributedStringBuilder.attributedString(
            from: markdown,
            textStyle: textStyle,
            weight: weight
        )
        textView.attributedText = attributed
        textView.accessibilityLabel = attributed.string
        context.coordinator.renderedMarkdown = markdown
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
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

    final class Coordinator {
        var renderedMarkdown: String?
    }
}

extension View {
    func appToggleStyle() -> some View {
        toggleStyle(.switch)
            .tint(AppStatusRole.positive.accent)
    }

    func appPageBackground() -> some View {
        background(AppTheme.pageBackground.ignoresSafeArea())
    }

    func somaCardSurface(
        radius: CGFloat = AppTheme.cardRadius
    ) -> some View {
        background(
            AppTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(AppTheme.separator, lineWidth: 0.5)
        }
    }
}
