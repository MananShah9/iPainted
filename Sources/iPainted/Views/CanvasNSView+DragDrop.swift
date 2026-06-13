import AppKit
import UniformTypeIdentifiers

/// Dropping image files (or dragged image data) onto the canvas, plus the
/// shared image-placement pipeline used by both drag-and-drop and Paste.
extension CanvasNSView {

    // MARK: - Drag destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.canRead(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.canRead(sender.draggingPasteboard) ? .copy : []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Self.canRead(sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let cg = Self.imageForPlacement(from: sender.draggingPasteboard) else { return false }
        let viewPoint = convert(sender.draggingLocation, from: nil)
        // Drop the image centered on the cursor when it lands on the canvas;
        // otherwise fall back to top-left placement.
        let dropPoint = canvasFrame.contains(viewPoint) ? clampToCanvas(toImage(viewPoint)) : nil
        window?.makeFirstResponder(self)
        placeImage(cg, at: dropPoint)
        return true
    }

    // MARK: - Pasteboard reading

    /// True if the pasteboard carries image data or an image file URL.
    static func canRead(_ pb: NSPasteboard) -> Bool {
        if pb.canReadObject(forClasses: [NSImage.self], options: nil) { return true }
        return pb.canReadObject(forClasses: [NSURL.self], options: urlImageOptions)
    }

    /// Decode a usable bitmap from the pasteboard: an image file URL first
    /// (so we honor the on-disk pixels), then raw image data.
    static func imageForPlacement(from pb: NSPasteboard) -> CGImage? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: urlImageOptions) as? [URL],
           let url = urls.first,
           let image = NSImage(contentsOf: url),
           let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg
        }
        if let image = NSImage(pasteboard: pb),
           let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg
        }
        return nil
    }

    private static let urlImageOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: FileOps.imageTypes.map { $0.identifier },
    ]

    // MARK: - Placement pipeline

    enum OversizeChoice { case expandCanvas, resizeImage, clip, cancel }

    /// Place an external image onto the canvas as a floating selection the user
    /// can then move/commit. `dropPoint` (image coords, CG bottom-left) is the
    /// desired center; nil places it at the top-left corner.
    ///
    /// When the image is larger than the canvas the user picks how to fit it.
    /// The size question is asked BEFORE any mutation so Cancel is a true no-op.
    func placeImage(_ source: CGImage, at dropPoint: CGPoint?) {
        let canvas = document.canvasSize
        let imgW = CGFloat(source.width), imgH = CGFloat(source.height)
        var image = source
        var anchor = dropPoint
        var grow = false

        if imgW > canvas.width || imgH > canvas.height {
            switch oversizeChoice(imageSize: CGSize(width: imgW, height: imgH)) {
            case .expandCanvas:
                grow = true
                anchor = nil                  // Paint anchors the expanded image top-left
            case .resizeImage:
                image = Self.scaledToFit(source, in: canvas) ?? source
            case .clip:
                break                          // keep native size; commit clips to canvas
            case .cancel:
                return
            }
        }

        commitFloatingSelection()
        document.registerUndo()
        if grow {
            document.setCanvasSize(CGSize(width: max(canvas.width, imgW),
                                          height: max(canvas.height, imgH)))
        }
        insertFloatingImage(image, at: anchor)
    }

    /// Drop a (correctly sized) image in as a floating selection.
    private func insertFloatingImage(_ cg: CGImage, at dropPoint: CGPoint?) {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let ch = document.canvasSize.height
        // Center on the drop point, else top-left of the canvas.
        let desired = dropPoint.map { CGPoint(x: $0.x - w / 2, y: $0.y - h / 2) }
            ?? CGPoint(x: 0, y: ch - h)

        state.tool = .selectRect
        floatingImage = cg
        floatingOrigin = clampedFloatingOrigin(width: w, height: h, desired: desired)
        let rect = CGRect(origin: floatingOrigin, size: CGSize(width: w, height: h))
        selectionRect = rect
        selectionPath = CGPath(rect: rect, transform: nil)
        updateSelectionState()
        document.contentChanged()
        refreshAll()
    }

    /// Keep the floating origin so the image stays on-canvas when it fits;
    /// when a dimension is larger than the canvas, pin that axis to the
    /// top-left so the visible portion starts at the corner (the clipped case).
    private func clampedFloatingOrigin(width w: CGFloat, height h: CGFloat,
                                       desired: CGPoint) -> CGPoint {
        let cw = document.canvasSize.width, ch = document.canvasSize.height
        let x = w <= cw ? min(max(desired.x, 0), cw - w) : 0
        let y = h <= ch ? min(max(desired.y, 0), ch - h) : ch - h
        return CGPoint(x: x, y: y)
    }

    private func oversizeChoice(imageSize: CGSize) -> OversizeChoice {
        let canvas = document.canvasSize
        let alert = NSAlert()
        alert.messageText = "Image is larger than the canvas"
        alert.informativeText = """
        The image (\(Int(imageSize.width)) × \(Int(imageSize.height))px) is bigger than the \
        canvas (\(Int(canvas.width)) × \(Int(canvas.height))px). How should it be placed?
        """
        alert.addButton(withTitle: "Expand Canvas")        // .alertFirstButtonReturn
        alert.addButton(withTitle: "Resize Image to Fit")  // .alertSecondButtonReturn
        alert.addButton(withTitle: "Clip to Canvas")       // .alertThirdButtonReturn
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .expandCanvas
        case .alertSecondButtonReturn: return .resizeImage
        case .alertThirdButtonReturn:  return .clip
        default:                       return .cancel
        }
    }

    /// Scale an image down to fit inside `size`, preserving aspect ratio.
    static func scaledToFit(_ image: CGImage, in size: CGSize) -> CGImage? {
        let scale = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        guard scale < 1 else { return image }
        let w = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let h = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let ctx = Layer.makeContext(size: CGSize(width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
