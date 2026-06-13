import AppKit
import CoreGraphics

/// Scanline flood fill operating directly on a layer's RGBA8 backing store.
enum FloodFill {

    /// Fill starting at `point` (CG bottom-left coords) with `color`.
    /// Matching is done against the composite image so fills respect what the
    /// user sees, but pixels are written to the active layer.
    static func fill(layer: Layer, composite: CGImage?, at point: CGPoint,
                     with color: NSColor, tolerance: Int = 24) {
        let ctx = layer.context
        guard let data = ctx.data else { return }
        let width = ctx.width
        let height = ctx.height
        let bytesPerRow = ctx.bytesPerRow

        // Pixel coords: CG y is bottom-up; raster rows are top-down.
        let px = Int(point.x)
        let py = height - 1 - Int(point.y)
        guard px >= 0, px < width, py >= 0, py < height else { return }

        // Read reference colors from the composite so fill matches the visible image.
        var refBuffer = [UInt8](repeating: 0, count: width * height * 4)
        if let composite {
            let refCtx = CGContext(data: &refBuffer, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            refCtx.draw(composite, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let buffer = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        @inline(__always) func refPixel(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
            let i = y * width * 4 + x * 4
            return (refBuffer[i], refBuffer[i + 1], refBuffer[i + 2], refBuffer[i + 3])
        }

        let target = refPixel(px, py)

        let rgb = color.usingColorSpace(.deviceRGB)!
        let fr = UInt8(rgb.redComponent * 255)
        let fg = UInt8(rgb.greenComponent * 255)
        let fb = UInt8(rgb.blueComponent * 255)

        // Already the fill color? Nothing to do.
        if abs(Int(target.0) - Int(fr)) <= 2, abs(Int(target.1) - Int(fg)) <= 2,
           abs(Int(target.2) - Int(fb)) <= 2, target.3 == 255 { return }

        @inline(__always) func matches(_ x: Int, _ y: Int) -> Bool {
            let p = refPixel(x, y)
            return abs(Int(p.0) - Int(target.0)) <= tolerance
                && abs(Int(p.1) - Int(target.1)) <= tolerance
                && abs(Int(p.2) - Int(target.2)) <= tolerance
                && abs(Int(p.3) - Int(target.3)) <= tolerance
        }

        @inline(__always) func setPixel(_ x: Int, _ y: Int) {
            let i = y * bytesPerRow + x * 4
            buffer[i] = fr; buffer[i + 1] = fg; buffer[i + 2] = fb; buffer[i + 3] = 255
            // Mark visited in the reference buffer with an impossible value
            // so we never revisit; offset alpha to break future matches.
            let r = y * width * 4 + x * 4
            refBuffer[r] = fr; refBuffer[r + 1] = fg; refBuffer[r + 2] = fb
            refBuffer[r + 3] = target.3 == 0 ? 255 : 0
        }

        // Scanline fill with explicit stack.
        var stack: [(Int, Int)] = [(px, py)]
        stack.reserveCapacity(1024)

        while let (sx, sy) = stack.popLast() {
            guard matches(sx, sy) else { continue }
            // Expand left and right.
            var left = sx
            while left > 0, matches(left - 1, sy) { left -= 1 }
            var right = sx
            while right < width - 1, matches(right + 1, sy) { right += 1 }
            for x in left...right { setPixel(x, sy) }
            // Seed rows above and below.
            for ny in [sy - 1, sy + 1] where ny >= 0 && ny < height {
                var x = left
                while x <= right {
                    if matches(x, ny) {
                        stack.append((x, ny))
                        while x <= right, matches(x, ny) { x += 1 }
                    } else {
                        x += 1
                    }
                }
            }
        }
    }
}
