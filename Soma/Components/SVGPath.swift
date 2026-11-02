import CoreGraphics
import Foundation

/// Minimal SVG path (`d` attribute) parser for muscle-map assets.
/// Handles concatenated decimals and elliptical-arc flags (`01-.5`).
enum SVGPath {
    /// 受力图路径全部来自固定资产字符串。解析一次后按原文缓存不可变
    /// `CGPath`，Canvas 每次重绘只做字典查找，不再逐帧重新解析长路径。
    /// 输入集固定，缓存大小以资产数量为上限。
    private final class PathCache: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [String: CGPath] = [:]

        func path(
            for data: String,
            make: (String) -> CGPath?
        ) -> CGPath? {
            lock.lock()
            if let cached = paths[data] {
                lock.unlock()
                return cached
            }
            lock.unlock()
            guard let path = make(data) else { return nil }
            lock.lock()
            paths[data] = path
            lock.unlock()
            return path
        }
    }

    private static let cache = PathCache()

    static func cachedCGPath(from data: String) -> CGPath? {
        cache.path(for: data, make: makeCGPath(from:))
    }

    static func makeCGPath(from data: String) -> CGPath? {
        var scanner = Scanner(data)
        let path = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var lastCommand: Character?

        while true {
            scanner.skipSeparators()
            if scanner.isAtEnd {
                break
            }
            let command: Character
            if let next = scanner.peek(), Character(next).isLetter {
                command = scanner.take()
            } else if let lastCommand {
                command = lastCommand
            } else {
                return nil
            }

            let relative = command.isLowercase
            switch Character(command.uppercased()) {
            case "M":
                guard let first = scanner.point(relative: relative, current: current) else {
                    return nil
                }
                path.move(to: first)
                current = first
                start = first
                lastControl = nil
                while scanner.nextIsNumber() {
                    guard let next = scanner.point(relative: relative, current: current) else {
                        return nil
                    }
                    path.addLine(to: next)
                    current = next
                }
                lastCommand = relative ? "l" : "L"

            case "L":
                while scanner.nextIsNumber() {
                    guard let next = scanner.point(relative: relative, current: current) else {
                        return nil
                    }
                    path.addLine(to: next)
                    current = next
                    lastControl = nil
                }
                lastCommand = command

            case "H":
                while scanner.nextIsNumber() {
                    guard let value = scanner.number() else { return nil }
                    let next = CGPoint(
                        x: relative ? current.x + value : value,
                        y: current.y
                    )
                    path.addLine(to: next)
                    current = next
                    lastControl = nil
                }
                lastCommand = command

            case "V":
                while scanner.nextIsNumber() {
                    guard let value = scanner.number() else { return nil }
                    let next = CGPoint(
                        x: current.x,
                        y: relative ? current.y + value : value
                    )
                    path.addLine(to: next)
                    current = next
                    lastControl = nil
                }
                lastCommand = command

            case "C":
                while scanner.nextIsNumber() {
                    guard
                        let control1 = scanner.point(relative: relative, current: current),
                        let control2 = scanner.point(relative: relative, current: current),
                        let end = scanner.point(relative: relative, current: current)
                    else { return nil }
                    path.addCurve(to: end, control1: control1, control2: control2)
                    current = end
                    lastControl = control2
                }
                lastCommand = command

            case "S":
                while scanner.nextIsNumber() {
                    let reflected: CGPoint =
                        if let lastControl,
                        let last = lastCommand,
                        "CS".contains(Character(last.uppercased())) {
                            CGPoint(
                                x: 2 * current.x - lastControl.x,
                                y: 2 * current.y - lastControl.y
                            )
                        } else {
                            current
                        }
                    guard
                        let control2 = scanner.point(relative: relative, current: current),
                        let end = scanner.point(relative: relative, current: current)
                    else { return nil }
                    path.addCurve(to: end, control1: reflected, control2: control2)
                    current = end
                    lastControl = control2
                }
                lastCommand = command

            case "Q":
                while scanner.nextIsNumber() {
                    guard
                        let control = scanner.point(relative: relative, current: current),
                        let end = scanner.point(relative: relative, current: current)
                    else { return nil }
                    path.addQuadCurve(to: end, control: control)
                    current = end
                    lastControl = control
                }
                lastCommand = command

            case "T":
                while scanner.nextIsNumber() {
                    let control: CGPoint =
                        if let lastControl,
                        let last = lastCommand,
                        "QT".contains(Character(last.uppercased())) {
                            CGPoint(
                                x: 2 * current.x - lastControl.x,
                                y: 2 * current.y - lastControl.y
                            )
                        } else {
                            current
                        }
                    guard let end = scanner.point(relative: relative, current: current) else {
                        return nil
                    }
                    path.addQuadCurve(to: end, control: control)
                    current = end
                    lastControl = control
                }
                lastCommand = command

            case "A":
                while scanner.nextIsNumber() {
                    guard
                        let radiusX = scanner.number(),
                        let radiusY = scanner.number(),
                        let rotation = scanner.number(),
                        let large = scanner.flag(),
                        let sweep = scanner.flag(),
                        let end = scanner.point(relative: relative, current: current)
                    else { return nil }
                    addArc(
                        to: path,
                        from: current,
                        to: end,
                        rx: abs(radiusX),
                        ry: abs(radiusY),
                        xAxisRotation: rotation,
                        largeArc: large,
                        sweep: sweep
                    )
                    current = end
                    lastControl = nil
                }
                lastCommand = command

            case "Z":
                path.closeSubpath()
                current = start
                lastControl = nil
                lastCommand = command

            default:
                return nil
            }
        }

        return path
    }

    private struct Scanner {
        private let scalars: [UnicodeScalar]
        private var index = 0

        init(_ string: String) {
            scalars = Array(string.unicodeScalars)
        }

        var isAtEnd: Bool {
            index >= scalars.count
        }

        mutating func nextIsNumber() -> Bool {
            let saved = index
            skipSeparators()
            guard let next = peek() else {
                index = saved
                return false
            }
            let isNumber = next == "+" || next == "-" || next == "." || next.isASCIIDigit
            index = saved
            return isNumber
        }

        mutating func skipSeparators() {
            while let next = peek(), next == "," || Character(next).isWhitespace {
                index += 1
            }
        }

        func peek() -> UnicodeScalar? {
            guard index < scalars.count else { return nil }
            return scalars[index]
        }

        mutating func take() -> Character {
            let value = Character(scalars[index])
            index += 1
            return value
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            guard let next = peek(), next == "+" || next == "-" || next == "." || next.isASCIIDigit else {
                return nil
            }

            var text = ""
            if next == "+" || next == "-" {
                text.append(Character(next))
                index += 1
            }
            while let digit = peek(), digit.isASCIIDigit {
                text.append(Character(digit))
                index += 1
            }
            if let dot = peek(), dot == "." {
                text.append(".")
                index += 1
                while let digit = peek(), digit.isASCIIDigit {
                    text.append(Character(digit))
                    index += 1
                }
            }
            if let exponent = peek(), exponent == "e" || exponent == "E" {
                text.append(Character(exponent))
                index += 1
                if let sign = peek(), sign == "+" || sign == "-" {
                    text.append(Character(sign))
                    index += 1
                }
                while let digit = peek(), digit.isASCIIDigit {
                    text.append(Character(digit))
                    index += 1
                }
            }
            guard let value = Double(text) else { return nil }
            return CGFloat(value)
        }

        mutating func flag() -> Bool? {
            skipSeparators()
            guard let next = peek(), next == "0" || next == "1" else { return nil }
            index += 1
            return next == "1"
        }

        mutating func point(relative: Bool, current: CGPoint) -> CGPoint? {
            guard let posX = number(), let posY = number() else { return nil }
            return relative
                ? CGPoint(x: current.x + posX, y: current.y + posY)
                : CGPoint(x: posX, y: posY)
        }
    }

    private static func addArc(
        to path: CGMutablePath,
        from: CGPoint,
        to end: CGPoint,
        rx inputRX: CGFloat,
        ry inputRY: CGFloat,
        xAxisRotation: CGFloat,
        largeArc: Bool,
        sweep: Bool
    ) {
        if inputRX == 0 || inputRY == 0 || from == end {
            path.addLine(to: end)
            return
        }

        let phi = xAxisRotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx = (from.x - end.x) / 2
        let dy = (from.y - end.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        var rx = inputRX
        var ry = inputRY
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
        }

        let rxSq = rx * rx
        let rySq = ry * ry
        let x1pSq = x1p * x1p
        let y1pSq = y1p * y1p
        var numerator = rxSq * rySq - rxSq * y1pSq - rySq * x1pSq
        let denominator = rxSq * y1pSq + rySq * x1pSq
        if numerator < 0 {
            numerator = 0
        }
        let coef = (largeArc == sweep ? -1.0 : 1.0) * sqrt(numerator / denominator)
        let cxp = coef * (rx * y1p) / ry
        let cyp = coef * -(ry * x1p) / rx
        let center = CGPoint(
            x: cosPhi * cxp - sinPhi * cyp + (from.x + end.x) / 2,
            y: sinPhi * cxp + cosPhi * cyp + (from.y + end.y) / 2
        )

        func vectorAngle(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
            let dot = first.x * second.x + first.y * second.y
            let len = hypot(first.x, first.y) * hypot(second.x, second.y)
            guard len > 0 else { return 0 }
            let clamped = min(1, max(-1, dot / len))
            let ang = acos(clamped)
            return first.x * second.y - first.y * second.x < 0 ? -ang : ang
        }

        let startVector = CGPoint(x: (x1p - cxp) / rx, y: (y1p - cyp) / ry)
        let endVector = CGPoint(x: (-x1p - cxp) / rx, y: (-y1p - cyp) / ry)
        let theta1 = vectorAngle(CGPoint(x: 1, y: 0), startVector)
        var delta = vectorAngle(startVector, endVector)
        if !sweep, delta > 0 {
            delta -= 2 * .pi
        }
        if sweep, delta < 0 {
            delta += 2 * .pi
        }

        let segments = max(1, Int(ceil(abs(delta / (.pi / 2)))))
        let deltaSegment = delta / CGFloat(segments)
        for segment in 0 ..< segments {
            let angle1 = theta1 + CGFloat(segment) * deltaSegment
            let angle2 = angle1 + deltaSegment
            let alpha = 4.0 / 3.0 * tan(deltaSegment / 4)

            let cos1 = cos(angle1)
            let sin1 = sin(angle1)
            let cos2 = cos(angle2)
            let sin2 = sin(angle2)

            let control1Unit = CGPoint(x: cos1 - alpha * sin1, y: sin1 + alpha * cos1)
            let control2Unit = CGPoint(x: cos2 + alpha * sin2, y: sin2 - alpha * cos2)
            let endUnit = CGPoint(x: cos2, y: sin2)

            func mapPoint(_ point: CGPoint) -> CGPoint {
                let mappedX = point.x * rx
                let mappedY = point.y * ry
                return CGPoint(
                    x: cosPhi * mappedX - sinPhi * mappedY + center.x,
                    y: sinPhi * mappedX + cosPhi * mappedY + center.y
                )
            }

            path.addCurve(
                to: mapPoint(endUnit),
                control1: mapPoint(control1Unit),
                control2: mapPoint(control2Unit)
            )
        }
    }
}

private extension UnicodeScalar {
    var isASCIIDigit: Bool {
        self >= "0" && self <= "9"
    }
}
