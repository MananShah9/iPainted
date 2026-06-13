import AppKit

/// Headless sanity checks for the pixel-level engines, run with `iPainted --selftest`.
/// Exits 0 on success, 1 on failure. Not part of the normal UI path.
enum SelfTest {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--selftest") else { return }
        var ok = true
        ok = floodFill() && ok
        ok = shapeRender() && ok
        ok = transformsAndCrop() && ok
        ok = undoRedo() && ok
        ok = canvasSizeSync() && ok
        ok = scaleToFit() && ok
        print(ok ? "SELFTEST PASS" : "SELFTEST FAIL")
        exit(ok ? 0 : 1)
    }

    private static func pixel(_ layer: Layer, _ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
        let ctx = layer.context
        let buf = ctx.data!.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * ctx.height)
        let i = (ctx.height - 1 - y) * ctx.bytesPerRow + x * 4  // CG y -> raster row
        return (Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2]), Int(buf[i + 3]))
    }

    private static func check(_ cond: Bool, _ label: String) -> Bool {
        print("  [\(cond ? "ok" : "XX")] \(label)")
        return cond
    }

    // Draw a black box outline on white, fill interior red, confirm spill-free.
    private static func floodFill() -> Bool {
        let size = CGSize(width: 100, height: 100)
        let layer = Layer(size: size, name: "t", fill: .white)
        let ctx = layer.context
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(CGRect(x: 20, y: 20, width: 60, height: 60))

        let composite = layer.cgImage
        FloodFill.fill(layer: layer, composite: composite, at: CGPoint(x: 50, y: 50), with: .red)

        let inside = pixel(layer, 50, 50)
        let outside = pixel(layer, 5, 5)
        var ok = true
        ok = check(inside.0 > 200 && inside.1 < 60 && inside.2 < 60, "interior filled red") && ok
        ok = check(outside.0 > 240 && outside.1 > 240 && outside.2 > 240, "exterior stayed white (no spill)") && ok
        return ok
    }

    // Filled rectangle shape should paint its interior.
    private static func shapeRender() -> Bool {
        let size = CGSize(width: 100, height: 100)
        let layer = Layer(size: size, name: "t", fill: .white)
        let ctx = layer.context
        let path = ShapePaths.path(for: .rectangle, in: CGRect(x: 25, y: 25, width: 50, height: 50),
                                   start: .zero, end: .zero)
        ctx.setFillColor(NSColor.blue.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        let center = pixel(layer, 50, 50)
        return check(center.2 > 200 && center.0 < 60, "rectangle shape filled blue")
    }

    // 90° rotation swaps dimensions; crop reduces size.
    private static func transformsAndCrop() -> Bool {
        let doc = CanvasDocument(size: CGSize(width: 80, height: 40))
        var ok = true
        doc.transform(.rotate90CW)
        ok = check(doc.canvasSize == CGSize(width: 40, height: 80), "rotate 90° swaps W/H") && ok
        doc.crop(to: CGRect(x: 0, y: 0, width: 20, height: 30))
        ok = check(doc.canvasSize == CGSize(width: 20, height: 30), "crop resizes canvas") && ok
        return ok
    }

    // Undo restores pixels; redo reapplies.
    private static func undoRedo() -> Bool {
        let doc = CanvasDocument(size: CGSize(width: 50, height: 50))
        let layer = doc.activeLayer!
        doc.registerUndo()
        layer.context.setFillColor(NSColor.black.cgColor)
        layer.context.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        var ok = true
        ok = check(pixel(doc.activeLayer!, 25, 25).0 < 30, "painted black") && ok
        doc.undo()
        ok = check(pixel(doc.activeLayer!, 25, 25).0 > 240, "undo restored white") && ok
        doc.redo()
        ok = check(pixel(doc.activeLayer!, 25, 25).0 < 30, "redo reapplied black") && ok
        return ok
    }

    // Growing the canvas must keep `canvasSize` in lockstep with the layers,
    // otherwise tool coordinate mapping drifts (the paste-then-draw bug).
    private static func canvasSizeSync() -> Bool {
        let doc = CanvasDocument(size: CGSize(width: 50, height: 50))
        doc.setCanvasSize(CGSize(width: 200, height: 120))
        var ok = true
        ok = check(doc.canvasSize == CGSize(width: 200, height: 120), "canvasSize updated on grow") && ok
        ok = check(doc.layers.allSatisfy { $0.size == CGSize(width: 200, height: 120) },
                   "layers match canvasSize after grow") && ok
        return ok
    }

    // Oversized images scale down to fit while preserving aspect ratio.
    private static func scaleToFit() -> Bool {
        let big = Layer(size: CGSize(width: 400, height: 200), name: "t", fill: .black).cgImage!
        guard let fit = CanvasNSView.scaledToFit(big, in: CGSize(width: 100, height: 100)) else {
            return check(false, "scaledToFit returned an image")
        }
        var ok = true
        ok = check(fit.width <= 100 && fit.height <= 100, "fits inside canvas") && ok
        ok = check(fit.width == 100 && fit.height == 50, "preserves 2:1 aspect ratio") && ok
        return ok
    }
}
