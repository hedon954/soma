import SwiftUI

enum NutritionMacroGlyph {
    case protein
    case carbs
    case fat
}

struct NutritionMacroIcon: View {
    let glyph: NutritionMacroGlyph

    var body: some View {
        Group {
            switch glyph {
            case .protein:
                ProteinMeatGlyph().fill(style: FillStyle(eoFill: false))
            case .carbs:
                WheatEarGlyph().fill(style: FillStyle(eoFill: false))
            case .fat:
                Image(systemName: "drop.fill")
                    .font(.subheadline.weight(.medium))
                    .symbolRenderingMode(.monochrome)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// 带骨肉块：两枚叠圆加短骨，对应蛋白质。
private struct ProteinMeatGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()
        path.addEllipse(in: CGRect(x: width * 0.04, y: height * 0.02, width: width * 0.62, height: height * 0.62))
        path.addEllipse(in: CGRect(x: width * 0.36, y: height * 0.30, width: width * 0.34, height: height * 0.34))
        let bone = CGRect(x: width * 0.58, y: height * 0.56, width: width * 0.14, height: height * 0.30)
        path.addRoundedRect(in: bone, cornerSize: CGSize(width: width * 0.07, height: width * 0.07))
        path.addEllipse(in: CGRect(x: width * 0.50, y: height * 0.78, width: width * 0.18, height: height * 0.18))
        path.addEllipse(in: CGRect(x: width * 0.66, y: height * 0.78, width: width * 0.18, height: height * 0.18))
        return path
    }
}

/// 麦穗：中茎加成对籽粒，对应碳水。
private struct WheatEarGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: width * 0.44, y: height * 0.22, width: width * 0.12, height: height * 0.74),
            cornerSize: CGSize(width: width * 0.06, height: width * 0.06)
        )
        addGrain(&path, center: CGPoint(x: width * 0.50, y: height * 0.12), size: CGSize(width: width * 0.28, height: height * 0.22), angle: .degrees(0))
        addGrain(&path, center: CGPoint(x: width * 0.28, y: height * 0.28), size: CGSize(width: width * 0.30, height: height * 0.20), angle: .degrees(-38))
        addGrain(&path, center: CGPoint(x: width * 0.72, y: height * 0.28), size: CGSize(width: width * 0.30, height: height * 0.20), angle: .degrees(38))
        addGrain(&path, center: CGPoint(x: width * 0.26, y: height * 0.46), size: CGSize(width: width * 0.30, height: height * 0.20), angle: .degrees(-38))
        addGrain(&path, center: CGPoint(x: width * 0.74, y: height * 0.46), size: CGSize(width: width * 0.30, height: height * 0.20), angle: .degrees(38))
        addGrain(&path, center: CGPoint(x: width * 0.30, y: height * 0.62), size: CGSize(width: width * 0.26, height: height * 0.18), angle: .degrees(-32))
        addGrain(&path, center: CGPoint(x: width * 0.70, y: height * 0.62), size: CGSize(width: width * 0.26, height: height * 0.18), angle: .degrees(32))
        return path
    }

    private func addGrain(_ path: inout Path, center: CGPoint, size: CGSize, angle: Angle) {
        let oval = Path(ellipseIn: CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        ))
        let transform = CGAffineTransform.identity
            .translatedBy(x: center.x, y: center.y)
            .rotated(by: CGFloat(angle.radians))
        path.addPath(oval.applying(transform))
    }
}
