import SwiftUI

struct MuscleMapView: View {
    var intensities: [MuscleGroup: Double]
    var showsBothSides: Bool = true
    var showsLabels: Bool = true
    var height: CGFloat = 280
    /// When true, tapping opens a full-screen enlarged map.
    var allowsExpansion: Bool = false
    var labelFontSize: CGFloat = 6
    var presentation: Presentation = .card

    enum Presentation {
        case card
        case poster
    }

    @State private var isExpanded = false

    /// SVG artboard includes empty margin; crop so the figure fills the card
    /// like the pre-label layout. Keep side insets below arm extremities (~49).
    private static let contentInsets = EdgeInsets(
        top: 140,
        leading: 35,
        bottom: 30,
        trailing: 35
    )

    private var normalized: [MuscleGroup: Double] {
        MuscleGroupMapping.normalized(intensities)
    }

    var body: some View {
        if allowsExpansion {
            Button {
                isExpanded = true
            } label: {
                mapContent
            }
            .buttonStyle(.plain)
            .accessibilityHint("轻点放大查看")
            .fullScreenCover(isPresented: $isExpanded) {
                MuscleMapExpandedViewer(intensities: intensities)
            }
        } else {
            mapContent
        }
    }

    private var mapContent: some View {
        Group {
            if showsBothSides {
                HStack(alignment: .top, spacing: 8) {
                    sideCard(.anterior)
                    sideCard(.posterior)
                }
            } else {
                sideCard(preferredSide)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var preferredSide: MuscleMapSide {
        let anteriorScore = normalized
            .filter { $0.key.side == .anterior }
            .map(\.value)
            .reduce(0, +)
        let posteriorScore = normalized
            .filter { $0.key.side == .posterior }
            .map(\.value)
            .reduce(0, +)
        return posteriorScore > anteriorScore ? .posterior : .anterior
    }

    private func sideCard(_ side: MuscleMapSide) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let layout = layoutMetrics(in: geo.size, side: side)
                ZStack {
                    bodyCanvas(side: side, layout: layout)
                    if showsLabels {
                        labelOverlay(side: side, layout: layout)
                    }
                }
            }
            Text(side == .anterior ? "正面" : "背面")
                .font(presentation == .poster ? .system(size: 14) : .caption2.weight(.semibold))
                .foregroundStyle(presentation == .poster ? WorkoutSharePalette.ink : Color.secondary)
        }
        .padding(presentation == .poster ? 0 : 6)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(presentation == .poster ? Color.clear : Color.secondary.opacity(0.07))
        )
        .accessibilityLabel(side == .anterior ? "正面肌群图" : "背面肌群图")
    }

    private struct LayoutMetrics {
        var canvasSize: CGSize
        var scale: CGFloat
        var offset: CGPoint
        var originShiftX: CGFloat
        var contentOrigin: CGPoint
    }

    private func layoutMetrics(in size: CGSize, side: MuscleMapSide) -> LayoutMetrics {
        let viewSize = MuscleMapPathData.viewSize(for: side)
        let insets = Self.contentInsets
        let contentSize = CGSize(
            width: viewSize.width - insets.leading - insets.trailing,
            height: viewSize.height - insets.top - insets.bottom
        )
        // Fill the card; labels overlay the edges with a tiny font.
        let scale = min(size.width / contentSize.width, size.height / contentSize.height)
        let drawn = CGSize(
            width: contentSize.width * scale,
            height: contentSize.height * scale
        )
        let offset = CGPoint(
            x: (size.width - drawn.width) / 2,
            y: (size.height - drawn.height) / 2
        )
        let shift: CGFloat = side == .posterior ? MuscleMapPathData.posteriorOriginX : 0
        return LayoutMetrics(
            canvasSize: size,
            scale: scale,
            offset: offset,
            originShiftX: shift,
            contentOrigin: CGPoint(x: insets.leading, y: insets.top)
        )
    }

    private func mapPoint(_ point: CGPoint, layout: LayoutMetrics) -> CGPoint {
        CGPoint(
            x: layout.offset.x + (point.x - layout.contentOrigin.x) * layout.scale,
            y: layout.offset.y + (point.y - layout.contentOrigin.y) * layout.scale
        )
    }

    private func bodyCanvas(side: MuscleMapSide, layout: LayoutMetrics) -> some View {
        Canvas { context, _ in
            let transform = CGAffineTransform.identity
                .translatedBy(x: layout.offset.x, y: layout.offset.y)
                .scaledBy(x: layout.scale, y: layout.scale)
                .translatedBy(
                    x: -layout.originShiftX - layout.contentOrigin.x,
                    y: -layout.contentOrigin.y
                )

            if let outline = SVGPath.cachedCGPath(
                from: MuscleMapPathData.outline(for: side)
            ) {
                var outlinePath = Path(outline)
                outlinePath = outlinePath.applying(transform)
                context.fill(
                    outlinePath,
                    with: .color(presentation == .poster ? Color.white.opacity(0.45) : Color.secondary.opacity(0.10))
                )
            }

            for part in MuscleMapPathData.parts(for: side) {
                let intensity = part.isStructural
                    ? 0
                    : intensity(forPathKey: part.muscleRaw, side: side)
                let fill = fillColor(intensity: intensity, structural: part.isStructural)
                for data in part.pathData {
                    guard let cgPath = SVGPath.cachedCGPath(from: data) else { continue }
                    let path = Path(cgPath).applying(transform)
                    context.fill(path, with: .color(fill))
                    if presentation == .poster {
                        context.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 0.6)
                    }
                }
            }
        }
    }

    private func labelOverlay(side: MuscleMapSide, layout: LayoutMetrics) -> some View {
        let fontSize = labelFontSize
        return Canvas { context, _ in
            // Only label lit muscles so text stays sparse and the figure stays large.
            let anchors = MuscleMapLabels.anchors(for: side).filter {
                (normalized[$0.group] ?? 0) > 0
            }
            for anchor in anchors {
                let muscle = mapPoint(anchor.musclePoint, layout: layout)
                let labelY = layout.offset.y
                    + (anchor.labelY - layout.contentOrigin.y) * layout.scale
                let edgePad: CGFloat = fontSize > 8 ? 6 : 2
                let labelX: CGFloat = anchor.edge == .leading
                    ? edgePad
                    : layout.canvasSize.width - edgePad
                let label = CGPoint(x: labelX, y: labelY)
                let elbowX = anchor.edge == .leading
                    ? max(edgePad + 14, muscle.x - 10)
                    : min(layout.canvasSize.width - edgePad - 14, muscle.x + 10)

                var leader = Path()
                leader.move(to: muscle)
                leader.addLine(to: CGPoint(x: elbowX, y: labelY))
                leader.addLine(to: label)
                context.stroke(
                    leader,
                    with: .color(AppTheme.trainingAccent.opacity(0.42)),
                    lineWidth: fontSize > 8 ? 0.8 : 0.5
                )

                let text = Text(anchor.group.displayName)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(AppTheme.trainingAccent)
                let textAnchor: UnitPoint = anchor.edge == .leading ? .leading : .trailing
                context.draw(context.resolve(text), at: label, anchor: textAnchor)
            }
        }
        .allowsHitTesting(false)
    }

    private func intensity(forPathKey key: String, side: MuscleMapSide) -> Double {
        guard let group = MuscleGroup.group(forPathKey: key, side: side) else {
            return 0
        }
        return normalized[group] ?? 0
    }

    private func fillColor(intensity: Double, structural: Bool) -> Color {
        if presentation == .poster {
            if structural || intensity <= 0 {
                return Color.white.opacity(structural ? 0.6 : 0.4)
            }
            return WorkoutSharePalette.activeMuscle.opacity(intensity < 0.55 ? 0.48 : 1)
        }
        if structural {
            return Color.secondary.opacity(0.16)
        }
        if intensity <= 0 {
            return Color.secondary.opacity(0.20)
        }
        if intensity < 0.55 {
            return AppTheme.trainingAccent.opacity(0.48)
        }
        return AppTheme.trainingAccent.opacity(0.92)
    }

    private var accessibilityDescription: String {
        let lit = normalized
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map(\.key.displayName)
        if lit.isEmpty {
            return "肌群受力图，暂无已映射肌群"
        }
        return "肌群受力图，点亮：\(lit.joined(separator: "、"))"
    }
}

private struct MuscleMapExpandedViewer: View {
    @Environment(\.dismiss) private var dismiss
    let intensities: [MuscleGroup: Double]

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let mapHeight = max(360, geo.size.height - 48)
                MuscleMapView(
                    intensities: intensities,
                    showsBothSides: true,
                    showsLabels: true,
                    height: mapHeight,
                    allowsExpansion: false,
                    labelFontSize: 11
                )
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .appPageBackground()
            .navigationTitle("肌群受力图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityLabel("关闭放大的肌群受力图")
                }
            }
        }
    }
}

extension MuscleMapView {
    static func intensities(
        for definition: ExerciseDefinition
    ) -> [MuscleGroup: Double] {
        MuscleGroupMapping.intensityMap(
            primary: definition.primaryMuscles,
            secondary: definition.secondaryMuscles
        )
    }

    static func intensities(
        exercises: [(primary: [String], secondary: [String], sets: Int)]
    ) -> [MuscleGroup: Double] {
        let maps = exercises.map { item in
            let weight = Double(max(item.sets, 1))
            return MuscleGroupMapping.intensityMap(
                primary: item.primary,
                secondary: item.secondary,
                primaryWeight: weight,
                secondaryWeight: weight * 0.45
            )
        }
        return MuscleGroupMapping.merge(maps)
    }
}
