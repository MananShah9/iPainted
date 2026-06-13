import AppKit
import CoreGraphics

/// A single bitmap layer backed by a CGContext (premultiplied RGBA, device RGB).
final class Layer: Identifiable {
    let id = UUID()
    var name: String
    var isVisible: Bool = true
    var opacity: CGFloat = 1.0
    private(set) var context: CGContext
    private(set) var size: CGSize

    init(size: CGSize, name: String, fill: NSColor? = nil) {
        self.name = name
        self.size = size
        self.context = Layer.makeContext(size: size)
        if let fill {
            context.setFillColor(fill.usingColorSpace(.deviceRGB)!.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func makeContext(size: CGSize) -> CGContext {
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))
        let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .high
        return ctx
    }

    var cgImage: CGImage? { context.makeImage() }

    /// Replace contents with the given image, optionally resizing the layer.
    func setContents(_ image: CGImage, newSize: CGSize? = nil) {
        if let newSize, newSize != size {
            size = newSize
            context = Layer.makeContext(size: newSize)
        }
        context.clear(CGRect(origin: .zero, size: size))
        context.draw(image, in: CGRect(origin: .zero, size: size))
    }

    /// Resize the layer canvas. Existing content is anchored at top-left.
    /// If `stretch` is true, content is scaled to the new size instead.
    func resizeCanvas(to newSize: CGSize, stretch: Bool, background: NSColor?) {
        guard newSize != size, let image = cgImage else {
            size = newSize
            return
        }
        let oldSize = size
        size = newSize
        let newCtx = Layer.makeContext(size: newSize)
        if let background {
            newCtx.setFillColor(background.usingColorSpace(.deviceRGB)!.cgColor)
            newCtx.fill(CGRect(origin: .zero, size: newSize))
        }
        if stretch {
            newCtx.draw(image, in: CGRect(origin: .zero, size: newSize))
        } else {
            // Anchor top-left: CG origin is bottom-left, so offset y.
            let y = newSize.height - oldSize.height
            newCtx.draw(image, in: CGRect(x: 0, y: y, width: oldSize.width, height: oldSize.height))
        }
        context = newCtx
    }

    func transformed(_ op: ImageTransform) {
        guard let image = cgImage else { return }
        let oldSize = size
        let newSize: CGSize
        switch op {
        case .rotate90CW, .rotate90CCW:
            newSize = CGSize(width: oldSize.height, height: oldSize.width)
        case .rotate180, .flipHorizontal, .flipVertical:
            newSize = oldSize
        }
        size = newSize
        let ctx = Layer.makeContext(size: newSize)
        ctx.saveGState()
        switch op {
        case .rotate90CW:
            ctx.translateBy(x: newSize.width, y: 0)
            ctx.rotate(by: .pi / 2)
        case .rotate90CCW:
            ctx.translateBy(x: 0, y: newSize.height)
            ctx.rotate(by: -.pi / 2)
        case .rotate180:
            ctx.translateBy(x: newSize.width, y: newSize.height)
            ctx.rotate(by: .pi)
        case .flipHorizontal:
            ctx.translateBy(x: newSize.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        case .flipVertical:
            ctx.translateBy(x: 0, y: newSize.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        ctx.draw(image, in: CGRect(origin: .zero, size: oldSize))
        ctx.restoreGState()
        context = ctx
    }

    /// Crop layer to rect (in image coordinates, bottom-left origin).
    func crop(to rect: CGRect) {
        guard let image = cgImage,
              let cropped = image.cropping(to: pixelRect(rect)) else { return }
        size = rect.size
        context = Layer.makeContext(size: rect.size)
        context.draw(cropped, in: CGRect(origin: .zero, size: rect.size))
    }

    /// Convert a CG (bottom-left) rect to pixel (top-left) rect for CGImage.cropping.
    private func pixelRect(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height)
    }

    /// PNG snapshot for undo. Compact, deterministic.
    func snapshotData() -> Data? {
        guard let image = cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    func restore(from data: Data, size restoredSize: CGSize) {
        guard let rep = NSBitmapImageRep(data: data), let image = rep.cgImage else { return }
        size = restoredSize
        context = Layer.makeContext(size: restoredSize)
        context.draw(image, in: CGRect(origin: .zero, size: restoredSize))
    }
}

enum ImageTransform {
    case rotate90CW, rotate90CCW, rotate180, flipHorizontal, flipVertical
}
