import AppKit
import Vision

extension CanvasNSView {

    // MARK: - Selection mouse handling

    func selectionMouseDown(at p: CGPoint) {
        // Click inside existing selection -> start moving it.
        if let path = selectionPath, path.contains(p) || floatingHitTest(p) {
            if floatingImage == nil { liftSelection() }
            draggingSelection = true
            dragAnchor = p
            return
        }
        // Otherwise commit any floating pixels and start a new selection.
        commitFloatingSelection()
        clearSelection()
        isDraggingOutSelection = true
        if state.tool == .selectLasso {
            lassoPoints = [p]
        } else {
            dragAnchor = p
            selectionRect = CGRect(origin: p, size: .zero)
        }
    }

    func selectionMouseDrag(at p: CGPoint) {
        if draggingSelection {
            let dx = p.x - dragAnchor.x
            let dy = p.y - dragAnchor.y
            dragAnchor = p
            floatingOrigin.x += dx
            floatingOrigin.y += dy
            moveSelectionOutline(dx: dx, dy: dy)
            return
        }
        guard isDraggingOutSelection else { return }
        if state.tool == .selectLasso {
            lassoPoints.append(p)
        } else {
            selectionRect = rectFrom(dragAnchor, p)
            selectionPath = CGPath(rect: selectionRect!, transform: nil)
        }
    }

    func selectionMouseUp(at p: CGPoint) {
        if draggingSelection {
            draggingSelection = false
            return
        }
        guard isDraggingOutSelection else { return }
        isDraggingOutSelection = false
        if state.tool == .selectLasso {
            guard lassoPoints.count > 2 else { lassoPoints = []; return }
            let path = CGMutablePath()
            path.addLines(between: lassoPoints)
            path.closeSubpath()
            selectionPath = path
            selectionRect = path.boundingBox.intersection(CGRect(origin: .zero, size: document.canvasSize))
            lassoPoints = []
        } else if let r = selectionRect, r.width > 1, r.height > 1 {
            let clamped = r.intersection(CGRect(origin: .zero, size: document.canvasSize))
            selectionRect = clamped
            selectionPath = CGPath(rect: clamped, transform: nil)
        } else {
            clearSelection()
        }
        updateSelectionState()
    }

    func floatingHitTest(_ p: CGPoint) -> Bool {
        guard let img = floatingImage else { return false }
        let r = CGRect(x: floatingOrigin.x, y: floatingOrigin.y,
                       width: CGFloat(img.width), height: CGFloat(img.height))
        return r.contains(p)
    }

    func moveSelectionOutline(dx: CGFloat, dy: CGFloat) {
        var t = CGAffineTransform(translationX: dx, y: dy)
        if let path = selectionPath { selectionPath = path.copy(using: &t) }
        if let r = selectionRect { selectionRect = r.offsetBy(dx: dx, dy: dy) }
    }

    func updateSelectionState() {
        state.hasSelection = selectionPath != nil
        if let r = selectionRect, selectionPath != nil {
            state.selectionSizeText = "\(Int(r.width)) × \(Int(r.height))px"
        } else {
            state.selectionSizeText = ""
        }
    }

    func clearSelection() {
        selectionPath = nil
        selectionRect = nil
        floatingImage = nil
        draggingSelection = false
        updateSelectionState()
    }

    func selectAll() {
        commitFloatingSelection()
        let r = CGRect(origin: .zero, size: document.canvasSize)
        selectionRect = r
        selectionPath = CGPath(rect: r, transform: nil)
        state.tool = .selectRect
        updateSelectionState()
        needsDisplay = true
    }

    func invertSelection() {
        guard let path = selectionPath else { return }
        commitFloatingSelection()
        let full = CGMutablePath()
        full.addRect(CGRect(origin: .zero, size: document.canvasSize))
        full.addPath(path)
        selectionPath = full   // drawn/clipped with even-odd rule
        selectionRect = CGRect(origin: .zero, size: document.canvasSize)
        updateSelectionState()
        needsDisplay = true
    }

    // MARK: - Lift / commit / delete

    /// Copy selected pixels into floatingImage and clear them from the layer.
    func liftSelection() {
        guard let path = selectionPath, let rect = selectionRect,
              let layer = document.activeLayer,
              rect.width >= 1, rect.height >= 1 else { return }
        document.registerUndo()

        // Render the selected region into its own bitmap.
        let w = Int(rect.width.rounded()), h = Int(rect.height.rounded())
        guard w > 0, h > 0, let layerImage = layer.cgImage else { return }
        let ctx = Layer.makeContext(size: CGSize(width: w, height: h))
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ctx.addPath(path)
        ctx.clip(using: .evenOdd)
        ctx.draw(layerImage, in: CGRect(origin: .zero, size: document.canvasSize))
        var lifted = ctx.makeImage()

        if state.transparentSelection, let img = lifted {
            lifted = Self.makeColorTransparent(img, color: state.secondaryColor)
        }
        floatingImage = lifted
        floatingOrigin = rect.origin

        // Clear region from the layer (background layer gets secondary color).
        let lctx = layer.context
        lctx.saveGState()
        lctx.addPath(path)
        lctx.clip(using: .evenOdd)
        if document.activeLayerIndex == 0 {
            lctx.setFillColor((state.secondaryColor.usingColorSpace(.deviceRGB) ?? state.secondaryColor).cgColor)
            lctx.fill(CGRect(origin: .zero, size: document.canvasSize))
        } else {
            lctx.clear(CGRect(origin: .zero, size: document.canvasSize))
        }
        lctx.restoreGState()
        document.contentChanged()
    }

    /// Stamp floating pixels back onto the active layer.
    func commitFloatingSelection() {
        guard let img = floatingImage, let layer = document.activeLayer else { return }
        layer.context.draw(img, in: CGRect(x: floatingOrigin.x, y: floatingOrigin.y,
                                           width: CGFloat(img.width), height: CGFloat(img.height)))
        floatingImage = nil
        document.contentChanged()
        needsDisplay = true
    }

    func deleteSelectionContents() {
        if floatingImage != nil {
            // Deleting a floating selection just discards it.
            floatingImage = nil
            clearSelection()
            needsDisplay = true
            return
        }
        guard let path = selectionPath, let layer = document.activeLayer else { return }
        document.registerUndo()
        let ctx = layer.context
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip(using: .evenOdd)
        if document.activeLayerIndex == 0 {
            ctx.setFillColor((state.secondaryColor.usingColorSpace(.deviceRGB) ?? state.secondaryColor).cgColor)
            ctx.fill(CGRect(origin: .zero, size: document.canvasSize))
        } else {
            ctx.clear(CGRect(origin: .zero, size: document.canvasSize))
        }
        ctx.restoreGState()
        clearSelection()
        document.contentChanged()
        needsDisplay = true
    }

    /// Pixels matching `color` (within tolerance) become transparent.
    static func makeColorTransparent(_ image: CGImage, color: NSColor, tolerance: Int = 12) -> CGImage? {
        let w = image.width, h = image.height
        let ctx = Layer.makeContext(size: CGSize(width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return image }
        let buf = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * h)
        let rgb = color.usingColorSpace(.deviceRGB)!
        let tr = Int(rgb.redComponent * 255), tg = Int(rgb.greenComponent * 255), tb = Int(rgb.blueComponent * 255)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * ctx.bytesPerRow + x * 4
                if abs(Int(buf[i]) - tr) <= tolerance,
                   abs(Int(buf[i + 1]) - tg) <= tolerance,
                   abs(Int(buf[i + 2]) - tb) <= tolerance {
                    buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 0
                }
            }
        }
        return ctx.makeImage()
    }

    // MARK: - Clipboard

    func copySelection() {
        let image: CGImage?
        if let floating = floatingImage {
            image = floating
        } else if let path = selectionPath, let rect = selectionRect, let composite = document.compositeImage() {
            let w = Int(rect.width.rounded()), h = Int(rect.height.rounded())
            guard w > 0, h > 0 else { return }
            let ctx = Layer.makeContext(size: CGSize(width: w, height: h))
            ctx.translateBy(x: -rect.minX, y: -rect.minY)
            ctx.addPath(path)
            ctx.clip(using: .evenOdd)
            ctx.draw(composite, in: CGRect(origin: .zero, size: document.canvasSize))
            image = ctx.makeImage()
        } else if let composite = document.compositeImage() {
            image = composite
        } else {
            image = nil
        }
        guard let image else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)
    }

    func cutSelection() {
        copySelection()
        deleteSelectionContents()
    }

    func paste() {
        guard let cg = Self.imageForPlacement(from: NSPasteboard.general) else { return }
        placeImage(cg, at: nil)
    }

    func cropToSelection() {
        guard let rect = selectionRect, selectionPath != nil else { return }
        commitFloatingSelection()
        document.crop(to: rect)
        clearSelection()
        refreshAll()
    }

    // MARK: - Background removal (Vision)

    func removeBackground() {
        guard let layer = document.activeLayer, let input = layer.cgImage else { return }
        state.statusMessage = "Removing background…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: input, options: [:])
            var output: CGImage?
            do {
                try handler.perform([request])
                if let result = request.results?.first {
                    let buffer = try result.generateMaskedImage(
                        ofInstances: result.allInstances,
                        from: handler,
                        croppedToInstancesExtent: false)
                    let ciImage = CIImage(cvPixelBuffer: buffer)
                    let ciCtx = CIContext()
                    output = ciCtx.createCGImage(ciImage, from: ciImage.extent)
                }
            } catch {
                output = nil
            }
            DispatchQueue.main.async {
                defer { self.state.statusMessage = "" }
                guard let output else {
                    self.state.statusMessage = "No subject found"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.state.statusMessage = "" }
                    return
                }
                self.document.registerUndo()
                layer.context.clear(CGRect(origin: .zero, size: self.document.canvasSize))
                layer.context.draw(output, in: CGRect(origin: .zero, size: self.document.canvasSize))
                self.document.contentChanged()
                self.needsDisplay = true
            }
        }
    }

    // MARK: - Selection drawing (view coords)

    func drawSelectionOutline(_ ctx: CGContext) {
        guard let path = selectionPath else { return }
        ctx.saveGState()
        // Transform image-space path into view space.
        var t = CGAffineTransform(translationX: Self.pad, y: Self.pad + document.canvasSize.height * zoom)
        t = t.scaledBy(x: zoom, y: -zoom)
        if let viewPath = path.copy(using: &t) {
            ctx.addPath(viewPath)
            ctx.setLineWidth(1)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.strokePath()
            ctx.addPath(viewPath)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    func drawLassoPreview(_ ctx: CGContext) {
        guard state.tool == .selectLasso, isDraggingOutSelection, lassoPoints.count > 1 else { return }
        ctx.saveGState()
        let viewPoints = lassoPoints.map { toView($0) }
        ctx.addLines(between: viewPoints)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.strokePath()
        ctx.restoreGState()
    }
}
