import AppKit

/// The drawing surface. Lives inside an NSScrollView; its frame is the canvas
/// size times zoom plus padding for the resize handles.
final class CanvasNSView: NSView {
    unowned let state: AppState
    var document: CanvasDocument { state.document }

    static let pad: CGFloat = 12
    static let handleSize: CGFloat = 7

    // Freehand stroke state
    var isStroking = false
    var lastStrokePoint: CGPoint = .zero
    var strokeUsesSecondary = false

    // Shape state
    var shapeStart: CGPoint?
    var shapeCurrent: CGPoint?
    var curveControl: CGPoint?
    var curvePhase = 0          // 0 = drawing line, 1 = adjusting curve
    var pendingCurve: (start: CGPoint, end: CGPoint)?

    // Canvas-resize handle state
    enum ResizeHandle { case right, bottom, corner }
    var draggingHandle: ResizeHandle?
    var proposedCanvasSize: CGSize?

    // Selection state (see CanvasNSView+Selection)
    var selectionPath: CGPath?          // image coords (CG bottom-left)
    var selectionRect: CGRect?          // bounding rect in image coords
    var floatingImage: CGImage?
    var floatingOrigin: CGPoint = .zero // image coords of floating image bottom-left
    var draggingSelection = false
    var dragAnchor: CGPoint = .zero
    var lassoPoints: [CGPoint] = []
    var isDraggingOutSelection = false

    // Text state
    var textEditor: NSTextView?
    var textOrigin: CGPoint = .zero     // image coords (top-left of text, CG bottom-left of first line box handled at commit)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(state: AppState) {
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
        updateFrameSize()
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Geometry

    var zoom: CGFloat { state.zoom }

    var canvasFrame: CGRect {
        CGRect(x: Self.pad, y: Self.pad,
               width: document.canvasSize.width * zoom,
               height: document.canvasSize.height * zoom)
    }

    func updateFrameSize() {
        let size = proposedCanvasSize ?? document.canvasSize
        let w = max(size.width, document.canvasSize.width) * zoom + Self.pad * 2 + 40
        let h = max(size.height, document.canvasSize.height) * zoom + Self.pad * 2 + 40
        setFrameSize(NSSize(width: w, height: h))
    }

    /// View (flipped) point -> image point in CG bottom-left coords.
    func toImage(_ p: NSPoint) -> CGPoint {
        let ix = (p.x - Self.pad) / zoom
        let iyTop = (p.y - Self.pad) / zoom
        return CGPoint(x: ix, y: document.canvasSize.height - iyTop)
    }

    /// Image point (CG bottom-left) -> view point (flipped).
    func toView(_ p: CGPoint) -> NSPoint {
        NSPoint(x: Self.pad + p.x * zoom,
                y: Self.pad + (document.canvasSize.height - p.y) * zoom)
    }

    /// Image rect (CG coords) -> view rect.
    func toViewRect(_ r: CGRect) -> NSRect {
        let origin = toView(CGPoint(x: r.minX, y: r.maxY))
        return NSRect(x: origin.x, y: origin.y, width: r.width * zoom, height: r.height * zoom)
    }

    func clampToCanvas(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), document.canvasSize.width),
                y: min(max(p.y, 0), document.canvasSize.height))
    }

    // MARK: - Resize handles

    func handleRects() -> [(ResizeHandle, NSRect)] {
        let f = canvasFrame
        let s = Self.handleSize
        return [
            (.right, NSRect(x: f.maxX + 2, y: f.midY - s / 2, width: s, height: s)),
            (.bottom, NSRect(x: f.midX - s / 2, y: f.maxY + 2, width: s, height: s)),
            (.corner, NSRect(x: f.maxX + 2, y: f.maxY + 2, width: s, height: s)),
        ]
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Pasteboard background
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()

        let frame = canvasFrame

        // Canvas shadow + white base
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 4,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
        NSColor.white.setFill()
        ctx.fill(frame)
        ctx.restoreGState()

        // Checkerboard for transparency
        drawCheckerboard(ctx, in: frame)

        // Layers (bottom to top), drawn flipped-correct
        ctx.saveGState()
        ctx.translateBy(x: frame.minX, y: frame.maxY)
        ctx.scaleBy(x: zoom, y: -zoom)
        ctx.interpolationQuality = zoom >= 4 ? .none : .high
        let csize = document.canvasSize
        for layer in document.layers where layer.isVisible {
            if let img = layer.cgImage {
                ctx.setAlpha(layer.opacity)
                ctx.draw(img, in: CGRect(origin: .zero, size: csize))
            }
        }
        ctx.setAlpha(1)

        // Floating selection rides on top
        if let floating = floatingImage {
            let r = CGRect(x: floatingOrigin.x, y: floatingOrigin.y,
                           width: CGFloat(floating.width), height: CGFloat(floating.height))
            ctx.draw(floating, in: r)
        }

        // Shape preview (in image space)
        drawShapePreview(ctx)
        ctx.restoreGState()

        // Grid overlay
        if state.showGrid { drawGrid(ctx, in: frame) }

        // Selection marching ants
        drawSelectionOutline(ctx)

        // Lasso in-progress
        drawLassoPreview(ctx)

        // Canvas border
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(rect: frame.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()

        // Resize handles
        for (_, rect) in handleRects() {
            NSColor.white.setFill()
            rect.fill()
            NSColor.systemBlue.setStroke()
            NSBezierPath(rect: rect).stroke()
        }

        // Resize drag preview
        if let proposed = proposedCanvasSize {
            let r = NSRect(x: frame.minX, y: frame.minY,
                           width: proposed.width * zoom, height: proposed.height * zoom)
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: r)
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawCheckerboard(_ ctx: CGContext, in frame: NSRect) {
        // Only visible through transparent pixels of non-opaque documents.
        ctx.saveGState()
        ctx.clip(to: frame)
        let tile: CGFloat = 8
        NSColor(white: 0.92, alpha: 1).setFill()
        ctx.fill(frame)
        NSColor(white: 0.82, alpha: 1).setFill()
        var y = frame.minY
        var row = 0
        while y < frame.maxY {
            var x = frame.minX + (row % 2 == 0 ? 0 : tile)
            while x < frame.maxX {
                ctx.fill(CGRect(x: x, y: y, width: tile, height: tile)
                    .intersection(frame))
                x += tile * 2
            }
            y += tile
            row += 1
        }
        ctx.restoreGState()
    }

    private func drawGrid(_ ctx: CGContext, in frame: NSRect) {
        ctx.saveGState()
        ctx.clip(to: frame)
        ctx.setStrokeColor(NSColor.gridColor.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(0.5)
        // Pixel grid at >=4x, else 10px grid.
        let stepImage: CGFloat = zoom >= 4 ? 1 : 10
        let step = stepImage * zoom
        guard step >= 4 else { ctx.restoreGState(); return }
        var x = frame.minX
        while x <= frame.maxX { ctx.move(to: CGPoint(x: x, y: frame.minY)); ctx.addLine(to: CGPoint(x: x, y: frame.maxY)); x += step }
        var y = frame.minY
        while y <= frame.maxY { ctx.move(to: CGPoint(x: frame.minX, y: y)); ctx.addLine(to: CGPoint(x: frame.maxX, y: y)); y += step }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawShapePreview(_ ctx: CGContext) {
        guard case .shape(let kind) = state.tool else { return }
        var path: CGPath?
        if curvePhase == 1, let pc = pendingCurve {
            path = ShapePaths.path(for: .curve, in: rectFrom(pc.start, pc.end),
                                   start: pc.start, end: pc.end, curveControl: curveControl)
        } else if let s = shapeStart, let c = shapeCurrent {
            path = ShapePaths.path(for: kind, in: rectFrom(s, c), start: s, end: c, curveControl: nil)
        }
        guard let path else { return }
        strokeAndFillShape(ctx, path: path, kind: kind)
    }

    func strokeAndFillShape(_ ctx: CGContext, path: CGPath, kind: ShapeKind) {
        let isOpen = (kind == .line || kind == .curve)
        if !isOpen, state.shapeFill == .solid {
            ctx.setFillColor((state.secondaryColor.usingColorSpace(.deviceRGB) ?? state.secondaryColor).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        }
        if state.shapeOutline == .solid || isOpen {
            ctx.setStrokeColor((state.primaryColor.usingColorSpace(.deviceRGB) ?? state.primaryColor).cgColor)
            ctx.setLineWidth(state.shapeThickness)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    func rectFrom(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: - Cursors

    override func resetCursorRects() {
        let cursor: NSCursor
        switch state.tool {
        case .pencil, .brush, .fill, .shape: cursor = .crosshair
        case .eraser: cursor = .crosshair
        case .text: cursor = .iBeam
        case .eyedropper: cursor = .crosshair
        case .magnifier: cursor = .crosshair
        case .selectRect, .selectLasso: cursor = .crosshair
        }
        addCursorRect(canvasFrame, cursor: cursor)
        for (handle, rect) in handleRects() {
            switch handle {
            case .right: addCursorRect(rect, cursor: .resizeLeftRight)
            case .bottom: addCursorRect(rect, cursor: .resizeUpDown)
            case .corner: addCursorRect(rect, cursor: .crosshair)
            }
        }
    }

    func refreshAll() {
        updateFrameSize()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }
}
