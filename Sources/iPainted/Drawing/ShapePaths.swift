import CoreGraphics

/// Builds CGPaths for every shape, fitted to a bounding rect.
/// For .line and .curve the start/end points are used directly.
enum ShapePaths {

    static func path(for kind: ShapeKind, in rect: CGRect,
                     start: CGPoint, end: CGPoint,
                     curveControl: CGPoint? = nil) -> CGPath {
        switch kind {
        case .line:
            let p = CGMutablePath()
            p.move(to: start)
            p.addLine(to: end)
            return p
        case .curve:
            let p = CGMutablePath()
            p.move(to: start)
            let c = curveControl ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            p.addQuadCurve(to: end, control: c)
            return p
        case .oval:
            return CGPath(ellipseIn: rect, transform: nil)
        case .rectangle:
            return CGPath(rect: rect, transform: nil)
        case .roundedRectangle:
            let r = min(rect.width, rect.height) * 0.2
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        case .triangle:
            return polygonPath(points: [
                CGPoint(x: rect.midX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY)])
        case .rightTriangle:
            return polygonPath(points: [
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY)])
        case .diamond:
            return polygonPath(points: [
                CGPoint(x: rect.midX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.midY),
                CGPoint(x: rect.midX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.midY)])
        case .pentagon:
            return regularPolygon(sides: 5, in: rect)
        case .hexagon:
            return regularPolygon(sides: 6, in: rect)
        case .polygon:
            return regularPolygon(sides: 7, in: rect)
        case .arrowRight, .arrowLeft, .arrowUp, .arrowDown:
            return arrowPath(kind: kind, in: rect)
        case .star4:
            return starPath(points: 4, in: rect, innerRatio: 0.30)
        case .star5:
            return starPath(points: 5, in: rect, innerRatio: 0.42)
        case .star6:
            return starPath(points: 6, in: rect, innerRatio: 0.55)
        case .calloutRect:
            return calloutRectPath(in: rect)
        case .calloutOval:
            return calloutOvalPath(in: rect)
        case .calloutCloud:
            return cloudPath(in: rect)
        case .heart:
            return heartPath(in: rect)
        case .lightning:
            return lightningPath(in: rect)
        }
    }

    private static func polygonPath(points: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        guard let first = points.first else { return p }
        p.move(to: first)
        points.dropFirst().forEach { p.addLine(to: $0) }
        p.closeSubpath()
        return p
    }

    private static func regularPolygon(sides: Int, in rect: CGRect) -> CGPath {
        var pts: [CGPoint] = []
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        for i in 0..<sides {
            let angle = .pi / 2 + 2 * .pi * CGFloat(i) / CGFloat(sides)
            pts.append(CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle)))
        }
        return polygonPath(points: pts)
    }

    private static func starPath(points n: Int, in rect: CGRect, innerRatio: CGFloat) -> CGPath {
        var pts: [CGPoint] = []
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        for i in 0..<(n * 2) {
            let outer = i % 2 == 0
            let r: CGFloat = outer ? 1 : innerRatio
            let angle = .pi / 2 + .pi * CGFloat(i) / CGFloat(n)
            pts.append(CGPoint(x: cx + rx * r * cos(angle), y: cy + ry * r * sin(angle)))
        }
        return polygonPath(points: pts)
    }

    private static func arrowPath(kind: ShapeKind, in rect: CGRect) -> CGPath {
        // Build a right-pointing arrow in unit space, then rotate as needed.
        let unit: [CGPoint] = [
            CGPoint(x: 0.0, y: 0.30), CGPoint(x: 0.6, y: 0.30),
            CGPoint(x: 0.6, y: 0.00), CGPoint(x: 1.0, y: 0.50),
            CGPoint(x: 0.6, y: 1.00), CGPoint(x: 0.6, y: 0.70),
            CGPoint(x: 0.0, y: 0.70)
        ]
        let rotated: [CGPoint]
        switch kind {
        case .arrowRight: rotated = unit
        case .arrowLeft: rotated = unit.map { CGPoint(x: 1 - $0.x, y: $0.y) }
        case .arrowUp: rotated = unit.map { CGPoint(x: $0.y, y: $0.x) }
        case .arrowDown: rotated = unit.map { CGPoint(x: $0.y, y: 1 - $0.x) }
        default: rotated = unit
        }
        let pts = rotated.map { CGPoint(x: rect.minX + $0.x * rect.width,
                                        y: rect.minY + $0.y * rect.height) }
        return polygonPath(points: pts)
    }

    private static func calloutRectPath(in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        let bodyHeight = rect.height * 0.72
        let body = CGRect(x: rect.minX, y: rect.minY + rect.height - bodyHeight,
                          width: rect.width, height: bodyHeight)
        let r = min(body.width, body.height) * 0.18
        p.addRoundedRect(in: body, cornerWidth: r, cornerHeight: r)
        // Tail
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.22, y: body.minY + 1))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.40, y: body.minY + 1))
        p.closeSubpath()
        return p
    }

    private static func calloutOvalPath(in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        let bodyHeight = rect.height * 0.72
        let body = CGRect(x: rect.minX, y: rect.minY + rect.height - bodyHeight,
                          width: rect.width, height: bodyHeight)
        p.addEllipse(in: body)
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.26, y: body.minY + bodyHeight * 0.08))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: body.minY + bodyHeight * 0.04))
        p.closeSubpath()
        return p
    }

    private static func cloudPath(in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        let bodyHeight = rect.height * 0.72
        let body = CGRect(x: rect.minX, y: rect.minY + rect.height - bodyHeight,
                          width: rect.width, height: bodyHeight)
        // Cloud body: overlapping ellipses around the perimeter.
        let bumps = 8
        for i in 0..<bumps {
            let angle = 2 * .pi * CGFloat(i) / CGFloat(bumps)
            let cx = body.midX + cos(angle) * body.width * 0.30
            let cy = body.midY + sin(angle) * body.height * 0.28
            let w = body.width * 0.42
            let h = body.height * 0.5
            p.addEllipse(in: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
        }
        // Tail bubbles
        p.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.12,
                                width: rect.width * 0.08, height: rect.height * 0.08))
        p.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.20,
                                width: rect.width * 0.11, height: rect.height * 0.10))
        return p
    }

    private static func heartPath(in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        let w = rect.width, h = rect.height
        let x = rect.minX, y = rect.minY
        p.move(to: CGPoint(x: x + w / 2, y: y))
        p.addCurve(to: CGPoint(x: x, y: y + h * 0.78),
                   control1: CGPoint(x: x + w * 0.20, y: y + h * 0.25),
                   control2: CGPoint(x: x, y: y + h * 0.50))
        p.addCurve(to: CGPoint(x: x + w / 2, y: y + h * 0.78),
                   control1: CGPoint(x: x, y: y + h * 1.08),
                   control2: CGPoint(x: x + w * 0.32, y: y + h * 1.02))
        p.addCurve(to: CGPoint(x: x + w, y: y + h * 0.78),
                   control1: CGPoint(x: x + w * 0.68, y: y + h * 1.02),
                   control2: CGPoint(x: x + w, y: y + h * 1.08))
        p.addCurve(to: CGPoint(x: x + w / 2, y: y),
                   control1: CGPoint(x: x + w, y: y + h * 0.50),
                   control2: CGPoint(x: x + w * 0.80, y: y + h * 0.25))
        p.closeSubpath()
        return p
    }

    private static func lightningPath(in rect: CGRect) -> CGPath {
        let pts: [(CGFloat, CGFloat)] = [
            (0.62, 1.00), (0.18, 0.42), (0.42, 0.42),
            (0.30, 0.00), (0.80, 0.55), (0.55, 0.55)
        ]
        let points = pts.map { CGPoint(x: rect.minX + $0.0 * rect.width,
                                       y: rect.minY + $0.1 * rect.height) }
        return polygonPath(points: points)
    }
}
