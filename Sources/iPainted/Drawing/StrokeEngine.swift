import AppKit
import CoreGraphics

/// Renders freehand strokes into a CGContext, one segment at a time.
/// Each brush kind has its own stamping behavior, approximating Win11 Paint brushes.
struct StrokeEngine {
    let kind: BrushKind?      // nil = plain pencil
    let color: NSColor
    let size: CGFloat
    let isEraser: Bool

    private var deviceColor: NSColor { color.usingColorSpace(.deviceRGB) ?? color }

    /// Deterministic pseudo-random for textured brushes (crayon/airbrush),
    /// seeded by position so re-renders are stable.
    private func jitter(_ p: CGPoint, _ salt: Int) -> CGFloat {
        let n = sin(p.x * 12.9898 + p.y * 78.233 + CGFloat(salt) * 37.719) * 43758.5453
        return n - n.rounded(.down) // 0..1
    }

    func beginStroke(in ctx: CGContext, at point: CGPoint) {
        drawSegment(in: ctx, from: point, to: point)
    }

    func drawSegment(in ctx: CGContext, from a: CGPoint, to b: CGPoint) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        if isEraser {
            ctx.setBlendMode(.clear)
            strokeRound(ctx, a, b, width: size, alpha: 1)
            return
        }

        switch kind {
        case nil:
            // Pencil: hard 1px-ish line at chosen size, no softness.
            ctx.setShouldAntialias(size > 2)
            strokeRound(ctx, a, b, width: max(1, size), alpha: 1)
        case .brush:
            strokeRound(ctx, a, b, width: size, alpha: 1)
        case .marker:
            ctx.setBlendMode(.multiply)
            strokeFlat(ctx, a, b, width: size * 1.6, alpha: 0.55, angle: 0)
        case .calligraphyBrush:
            stampCalligraphy(ctx, a, b, angle: .pi / 4, widthScale: 1.0, alpha: 1)
        case .calligraphyPen:
            stampCalligraphy(ctx, a, b, angle: .pi / 4, widthScale: 0.45, alpha: 1)
        case .airbrush:
            stampAirbrush(ctx, a, b)
        case .oilBrush:
            stampOil(ctx, a, b)
        case .crayon:
            stampCrayon(ctx, a, b)
        case .naturalPencil:
            stampNaturalPencil(ctx, a, b)
        case .watercolor:
            strokeRound(ctx, a, b, width: size * 2.2, alpha: 0.18)
        }
    }

    // MARK: - Primitive stroke styles

    private func strokeRound(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint,
                             width: CGFloat, alpha: CGFloat) {
        ctx.setStrokeColor(deviceColor.withAlphaComponent(alpha).cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
    }

    private func strokeFlat(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint,
                            width: CGFloat, alpha: CGFloat, angle: CGFloat) {
        ctx.setStrokeColor(deviceColor.withAlphaComponent(alpha).cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.square)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
    }

    // MARK: - Stamped brushes

    private func eachStamp(_ a: CGPoint, _ b: CGPoint, spacing: CGFloat,
                           _ body: (CGPoint) -> Void) {
        let dx = b.x - a.x, dy = b.y - a.y
        let dist = max(sqrt(dx * dx + dy * dy), 0.001)
        let steps = max(1, Int(dist / max(spacing, 0.5)))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            body(CGPoint(x: a.x + dx * t, y: a.y + dy * t))
        }
    }

    private func stampCalligraphy(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint,
                                  angle: CGFloat, widthScale: CGFloat, alpha: CGFloat) {
        // Diagonal flat nib: stamp rotated thin ellipses along the path.
        ctx.setFillColor(deviceColor.withAlphaComponent(alpha).cgColor)
        let w = size * 1.4
        let h = max(1.5, size * 0.22) * widthScale / 0.45 * 0.45
        eachStamp(a, b, spacing: max(0.7, h * 0.5)) { p in
            ctx.saveGState()
            ctx.translateBy(x: p.x, y: p.y)
            ctx.rotate(by: angle)
            ctx.fillEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            ctx.restoreGState()
        }
    }

    private func stampAirbrush(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint) {
        // Speckle spray inside a radius; density tied to segment length.
        ctx.setFillColor(deviceColor.withAlphaComponent(0.55).cgColor)
        let radius = size * 1.8
        eachStamp(a, b, spacing: 2.5) { p in
            for s in 0..<14 {
                let r1 = jitter(p, s * 2)
                let r2 = jitter(p, s * 2 + 1)
                let angle = r1 * 2 * .pi
                let dist = sqrt(r2) * radius
                let dot = CGPoint(x: p.x + cos(angle) * dist, y: p.y + sin(angle) * dist)
                let dotSize = 0.8 + jitter(dot, s) * 1.0
                ctx.fillEllipse(in: CGRect(x: dot.x, y: dot.y, width: dotSize, height: dotSize))
            }
        }
    }

    private func stampOil(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint) {
        // Several parallel bristle lines with varying alpha.
        let bristles = 5
        let w = size * 1.5
        for i in 0..<bristles {
            let t = CGFloat(i) / CGFloat(bristles - 1) - 0.5
            let offset = t * w * 0.8
            let alpha = 0.85 - abs(t) * 0.7
            let oa = CGPoint(x: a.x + offset, y: a.y + offset * 0.3)
            let ob = CGPoint(x: b.x + offset, y: b.y + offset * 0.3)
            ctx.setStrokeColor(deviceColor.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(max(1, w / CGFloat(bristles)))
            ctx.setLineCap(.round)
            ctx.move(to: oa)
            ctx.addLine(to: ob)
            ctx.strokePath()
        }
    }

    private func stampCrayon(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint) {
        // Grainy texture: random small rects clustered on the path.
        ctx.setFillColor(deviceColor.withAlphaComponent(0.5).cgColor)
        let w = size * 1.3
        eachStamp(a, b, spacing: 1.2) { p in
            for s in 0..<10 {
                let r1 = jitter(p, s * 3) - 0.5
                let r2 = jitter(p, s * 3 + 1) - 0.5
                if jitter(p, s * 3 + 2) < 0.55 {
                    let dot = CGPoint(x: p.x + r1 * w, y: p.y + r2 * w)
                    ctx.fill(CGRect(x: dot.x, y: dot.y, width: 1.4, height: 1.4))
                }
            }
        }
    }

    private func stampNaturalPencil(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint) {
        // Two slightly offset thin lines + grain, like graphite.
        ctx.setStrokeColor(deviceColor.withAlphaComponent(0.7).cgColor)
        let w = max(1, size * 0.5)
        ctx.setLineWidth(w)
        ctx.setLineCap(.round)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
        ctx.setStrokeColor(deviceColor.withAlphaComponent(0.25).cgColor)
        ctx.setLineWidth(w * 1.8)
        ctx.move(to: CGPoint(x: a.x + 0.7, y: a.y - 0.7))
        ctx.addLine(to: CGPoint(x: b.x + 0.7, y: b.y - 0.7))
        ctx.strokePath()
    }
}
