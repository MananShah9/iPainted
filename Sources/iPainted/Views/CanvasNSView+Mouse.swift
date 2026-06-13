import AppKit

extension CanvasNSView {

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)

        // Canvas resize handles take priority.
        for (handle, rect) in handleRects() where rect.insetBy(dx: -3, dy: -3).contains(viewPoint) {
            draggingHandle = handle
            proposedCanvasSize = document.canvasSize
            return
        }

        commitTextIfNeeded()
        let p = clampToCanvas(toImage(viewPoint))
        handleToolDown(at: p, viewPoint: viewPoint, secondary: false)
    }

    override func rightMouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let p = clampToCanvas(toImage(viewPoint))
        handleToolDown(at: p, viewPoint: viewPoint, secondary: true)
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)

        if let handle = draggingHandle {
            let p = toImageTopLeft(viewPoint)
            var size = document.canvasSize
            switch handle {
            case .right: size.width = max(1, p.x.rounded())
            case .bottom: size.height = max(1, p.y.rounded())
            case .corner:
                size.width = max(1, p.x.rounded())
                size.height = max(1, p.y.rounded())
            }
            proposedCanvasSize = size
            state.statusMessage = "\(Int(size.width)) × \(Int(size.height))px"
            updateFrameSize()
            needsDisplay = true
            return
        }

        let p = clampToCanvas(toImage(viewPoint))
        handleToolDrag(at: p)
        updateCursorReadout(viewPoint)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if draggingHandle != nil {
            if let size = proposedCanvasSize, size != document.canvasSize {
                document.resizeCanvas(to: size, stretch: false)
            }
            draggingHandle = nil
            proposedCanvasSize = nil
            state.statusMessage = ""
            refreshAll()
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let p = clampToCanvas(toImage(viewPoint))
        handleToolUp(at: p)
    }

    override func rightMouseUp(with event: NSEvent) {
        mouseUp(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursorReadout(convert(event.locationInWindow, from: nil))
    }

    /// View point -> image coords with TOP-LEFT origin (for status bar / resizing).
    func toImageTopLeft(_ p: NSPoint) -> CGPoint {
        CGPoint(x: (p.x - Self.pad) / zoom, y: (p.y - Self.pad) / zoom)
    }

    func updateCursorReadout(_ viewPoint: NSPoint) {
        let p = toImageTopLeft(viewPoint)
        if canvasFrame.contains(viewPoint) {
            state.cursorPosition = CGPoint(x: p.x.rounded(.down), y: p.y.rounded(.down))
        } else {
            state.cursorPosition = nil
        }
    }

    // MARK: - Tool dispatch

    private func handleToolDown(at p: CGPoint, viewPoint: NSPoint, secondary: Bool) {
        switch state.tool {
        case .pencil, .brush, .eraser:
            beginStroke(at: p, secondary: secondary)
        case .fill:
            doFloodFill(at: p, secondary: secondary)
        case .eyedropper:
            pickColor(at: p, secondary: secondary)
        case .magnifier:
            doMagnify(zoomIn: !secondary && !NSEvent.modifierFlags.contains(.option), at: viewPoint)
        case .text:
            beginTextEditing(at: p, viewPoint: viewPoint)
        case .selectRect, .selectLasso:
            selectionMouseDown(at: p)
        case .shape(let kind):
            if kind == .curve, curvePhase == 1 {
                curveControl = p
            } else {
                commitPendingCurveIfAny()
                shapeStart = p
                shapeCurrent = p
            }
        }
        needsDisplay = true
    }

    private func handleToolDrag(at p: CGPoint) {
        switch state.tool {
        case .pencil, .brush, .eraser:
            continueStroke(to: p)
        case .selectRect, .selectLasso:
            selectionMouseDrag(at: p)
        case .shape(let kind):
            if kind == .curve, curvePhase == 1 {
                curveControl = p
            } else {
                shapeCurrent = constrainIfShift(p)
            }
        default:
            break
        }
        needsDisplay = true
    }

    private func handleToolUp(at p: CGPoint) {
        switch state.tool {
        case .pencil, .brush, .eraser:
            endStroke()
        case .selectRect, .selectLasso:
            selectionMouseUp(at: p)
        case .shape(let kind):
            if kind == .curve {
                if curvePhase == 0, let s = shapeStart, let c = shapeCurrent, s != c {
                    pendingCurve = (s, c)
                    curveControl = nil
                    curvePhase = 1
                    shapeStart = nil
                    shapeCurrent = nil
                } else if curvePhase == 1 {
                    commitPendingCurveIfAny()
                }
            } else {
                commitShape(kind)
            }
        default:
            break
        }
        needsDisplay = true
    }

    /// Hold shift: constrain shapes to square/circle, lines to 45° steps.
    private func constrainIfShift(_ p: CGPoint) -> CGPoint {
        guard NSEvent.modifierFlags.contains(.shift), let s = shapeStart else { return p }
        if case .shape(.line) = state.tool {
            let dx = p.x - s.x, dy = p.y - s.y
            let angle = atan2(dy, dx)
            let snapped = (angle / (.pi / 4)).rounded() * (.pi / 4)
            let dist = sqrt(dx * dx + dy * dy)
            return CGPoint(x: s.x + cos(snapped) * dist, y: s.y + sin(snapped) * dist)
        }
        let side = max(abs(p.x - s.x), abs(p.y - s.y))
        return CGPoint(x: s.x + (p.x >= s.x ? side : -side),
                       y: s.y + (p.y >= s.y ? side : -side))
    }

    // MARK: - Freehand strokes

    private func currentEngine(secondary: Bool) -> StrokeEngine {
        let isEraser = state.tool == .eraser
        let color = secondary ? state.secondaryColor : state.primaryColor
        let kind: BrushKind? = state.tool == .brush ? state.brushKind : nil
        return StrokeEngine(kind: kind, color: color, size: state.brushSize, isEraser: isEraser)
    }

    private func beginStroke(at p: CGPoint, secondary: Bool) {
        guard let layer = document.activeLayer else { return }
        document.registerUndo()
        isStroking = true
        strokeUsesSecondary = secondary
        lastStrokePoint = p
        let engine = strokeEngineForCurrent()
        if state.tool == .eraser && document.activeLayerIndex == 0 {
            // Background layer: erase with secondary color, classic Paint style.
            let bg = StrokeEngine(kind: nil, color: state.secondaryColor,
                                  size: state.brushSize * 2, isEraser: false)
            bg.beginStroke(in: layer.context, at: p)
        } else {
            engine.beginStroke(in: layer.context, at: p)
        }
        needsDisplay = true
    }

    private func strokeEngineForCurrent() -> StrokeEngine {
        currentEngine(secondary: strokeUsesSecondary)
    }

    private func continueStroke(to p: CGPoint) {
        guard isStroking, let layer = document.activeLayer else { return }
        if state.tool == .eraser && document.activeLayerIndex == 0 {
            let bg = StrokeEngine(kind: nil, color: state.secondaryColor,
                                  size: state.brushSize * 2, isEraser: false)
            bg.drawSegment(in: layer.context, from: lastStrokePoint, to: p)
        } else {
            strokeEngineForCurrent().drawSegment(in: layer.context, from: lastStrokePoint, to: p)
        }
        // Repaint only the affected strip.
        let pad = state.brushSize * 3 + 6
        let dirty = toViewRect(rectFrom(lastStrokePoint, p).insetBy(dx: -pad, dy: -pad))
        lastStrokePoint = p
        setNeedsDisplay(dirty)
    }

    private func endStroke() {
        guard isStroking else { return }
        isStroking = false
        document.contentChanged()
    }

    // MARK: - Shapes

    private func commitShape(_ kind: ShapeKind) {
        guard let s = shapeStart, let c = shapeCurrent, let layer = document.activeLayer else {
            shapeStart = nil; shapeCurrent = nil
            return
        }
        if abs(s.x - c.x) > 1 || abs(s.y - c.y) > 1 {
            document.registerUndo()
            let path = ShapePaths.path(for: kind, in: rectFrom(s, c), start: s, end: c, curveControl: nil)
            strokeAndFillShape(layer.context, path: path, kind: kind)
            document.contentChanged()
        }
        shapeStart = nil
        shapeCurrent = nil
    }

    func commitPendingCurveIfAny() {
        guard let pc = pendingCurve, let layer = document.activeLayer else {
            curvePhase = 0
            return
        }
        document.registerUndo()
        let path = ShapePaths.path(for: .curve, in: rectFrom(pc.start, pc.end),
                                   start: pc.start, end: pc.end, curveControl: curveControl)
        strokeAndFillShape(layer.context, path: path, kind: .curve)
        document.contentChanged()
        pendingCurve = nil
        curveControl = nil
        curvePhase = 0
        needsDisplay = true
    }

    // MARK: - Fill / pick / magnify

    private func doFloodFill(at p: CGPoint, secondary: Bool) {
        guard let layer = document.activeLayer else { return }
        document.registerUndo()
        let color = secondary ? state.secondaryColor : state.primaryColor
        FloodFill.fill(layer: layer, composite: document.compositeImage(), at: p, with: color)
        document.contentChanged()
        needsDisplay = true
    }

    private func pickColor(at p: CGPoint, secondary: Bool) {
        guard let composite = document.compositeImage() else { return }
        let x = Int(p.x), y = composite.height - 1 - Int(p.y)
        guard x >= 0, x < composite.width, y >= 0, y < composite.height,
              let data = composite.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return }
        let bpr = composite.bytesPerRow
        let i = y * bpr + x * 4
        let color = NSColor(red: CGFloat(bytes[i]) / 255, green: CGFloat(bytes[i + 1]) / 255,
                            blue: CGFloat(bytes[i + 2]) / 255, alpha: 1)
        if secondary { state.secondaryColor = color } else { state.primaryColor = color }
        state.tool = .pencil
    }

    private func doMagnify(zoomIn: Bool, at viewPoint: NSPoint) {
        let steps: [CGFloat] = [0.125, 0.25, 0.5, 0.75, 1, 2, 3, 4, 6, 8]
        let current = state.zoom
        let next: CGFloat
        if zoomIn {
            next = steps.first(where: { $0 > current + 0.001 }) ?? 8
        } else {
            next = steps.last(where: { $0 < current - 0.001 }) ?? 0.125
        }
        state.zoom = next
        refreshAll()
    }

    // MARK: - Text tool

    func beginTextEditing(at p: CGPoint, viewPoint: NSPoint) {
        commitTextIfNeeded()
        let editor = NSTextView(frame: NSRect(x: viewPoint.x, y: viewPoint.y, width: 240, height: 40))
        editor.font = currentTextFont()
        editor.textColor = state.primaryColor
        editor.backgroundColor = .clear
        editor.drawsBackground = false
        editor.isRichText = false
        editor.allowsUndo = true
        editor.wantsLayer = true
        editor.layer?.borderColor = NSColor.systemBlue.cgColor
        editor.layer?.borderWidth = 1
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = true
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: 1200, height: 1200)
        addSubview(editor)
        window?.makeFirstResponder(editor)
        textEditor = editor
        textOrigin = p
    }

    func currentTextFont() -> NSFont {
        var font = NSFont(name: state.textFont, size: state.textSize * zoom)
            ?? NSFont.systemFont(ofSize: state.textSize * zoom)
        var traits: NSFontTraitMask = []
        if state.textBold { traits.insert(.boldFontMask) }
        if state.textItalic { traits.insert(.italicFontMask) }
        if !traits.isEmpty {
            font = NSFontManager.shared.convert(font, toHaveTrait: traits)
        }
        return font
    }

    /// Render the text editor's contents into the active layer and remove it.
    func commitTextIfNeeded() {
        guard let editor = textEditor else { return }
        defer {
            editor.removeFromSuperview()
            textEditor = nil
        }
        let text = editor.string
        guard !text.isEmpty, let layer = document.activeLayer else { return }
        document.registerUndo()

        var font = NSFont(name: state.textFont, size: state.textSize)
            ?? NSFont.systemFont(ofSize: state.textSize)
        var traits: NSFontTraitMask = []
        if state.textBold { traits.insert(.boldFontMask) }
        if state.textItalic { traits.insert(.italicFontMask) }
        if !traits.isEmpty { font = NSFontManager.shared.convert(font, toHaveTrait: traits) }

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: state.primaryColor,
        ]
        if state.textUnderline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        let attributed = NSAttributedString(string: text, attributes: attrs)

        let ctx = layer.context
        ctx.saveGState()
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        let textSize = attributed.size()
        // textOrigin is the click point in CG coords; draw text below the click.
        attributed.draw(at: NSPoint(x: textOrigin.x, y: textOrigin.y - textSize.height))
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
        document.contentChanged()
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            commitPendingCurveIfAny()
            commitFloatingSelection()
            clearSelection()
            needsDisplay = true
        case 51, 117: // Delete / Forward delete
            deleteSelectionContents()
        case 123, 124, 125, 126: // Arrows nudge floating selection
            nudgeSelection(keyCode: event.keyCode)
        default:
            super.keyDown(with: event)
        }
    }

    func nudgeSelection(keyCode: UInt16) {
        guard floatingImage != nil else { return }
        var dx: CGFloat = 0, dy: CGFloat = 0
        switch keyCode {
        case 123: dx = -1
        case 124: dx = 1
        case 125: dy = -1 // down in screen = down in CG image coords? down arrow lowers y in CG
        case 126: dy = 1
        default: break
        }
        floatingOrigin.x += dx
        floatingOrigin.y += dy
        moveSelectionOutline(dx: dx, dy: dy)
        needsDisplay = true
    }
}
