import AppKit
import SwiftUI

/// Central UI state shared between SwiftUI chrome and the AppKit canvas.
final class AppState: ObservableObject {
    let document = CanvasDocument()

    @Published var tool: Tool = .pencil
    @Published var brushKind: BrushKind = .brush
    @Published var brushSize: CGFloat = 3
    @Published var primaryColor: NSColor = .black
    @Published var secondaryColor: NSColor = .white
    @Published var activeColorSlot: Int = 1   // 1 = primary, 2 = secondary
    @Published var customColors: [NSColor] = []

    // Shape options
    @Published var shapeFill: ShapeFillStyle = .none
    @Published var shapeOutline: ShapeOutlineStyle = .solid
    @Published var shapeThickness: CGFloat = 3

    // Selection options
    @Published var transparentSelection = false
    @Published var hasSelection = false
    @Published var selectionSizeText = ""

    // Text tool
    @Published var textFont: String = "Helvetica"
    @Published var textSize: CGFloat = 24
    @Published var textBold = false
    @Published var textItalic = false
    @Published var textUnderline = false

    // View state
    @Published var zoom: CGFloat = 1.0
    @Published var showGrid = false
    @Published var showRulers = false
    @Published var showLayers = false
    @Published var cursorPosition: CGPoint? = nil
    @Published var statusMessage = ""

    /// Set by the canvas view so menu commands can reach it.
    weak var canvasView: CanvasNSView?

    var activeColor: NSColor { activeColorSlot == 1 ? primaryColor : secondaryColor }

    func setActiveColor(_ color: NSColor) {
        if activeColorSlot == 1 { primaryColor = color } else { secondaryColor = color }
    }

    func swapColors() {
        let t = primaryColor
        primaryColor = secondaryColor
        secondaryColor = t
    }

    func addCustomColor(_ color: NSColor) {
        if !customColors.contains(where: { $0.isClose(to: color) }) {
            customColors.insert(color, at: 0)
            if customColors.count > 10 { customColors.removeLast() }
        }
    }

    static let defaultPalette: [NSColor] = [
        .black,
        NSColor(white: 0.45, alpha: 1),
        NSColor(red: 0.53, green: 0.0, blue: 0.08, alpha: 1),
        NSColor(red: 0.91, green: 0.13, blue: 0.18, alpha: 1),
        NSColor(red: 1.0, green: 0.49, blue: 0.15, alpha: 1),
        NSColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 1),
        NSColor(red: 0.13, green: 0.69, blue: 0.30, alpha: 1),
        NSColor(red: 0.0, green: 0.64, blue: 0.91, alpha: 1),
        NSColor(red: 0.25, green: 0.28, blue: 0.80, alpha: 1),
        NSColor(red: 0.64, green: 0.29, blue: 0.64, alpha: 1),
        .white,
        NSColor(white: 0.78, alpha: 1),
        NSColor(red: 0.72, green: 0.58, blue: 0.45, alpha: 1),
        NSColor(red: 1.0, green: 0.68, blue: 0.79, alpha: 1),
        NSColor(red: 1.0, green: 0.85, blue: 0.65, alpha: 1),
        NSColor(red: 0.94, green: 0.89, blue: 0.55, alpha: 1),
        NSColor(red: 0.70, green: 0.87, blue: 0.41, alpha: 1),
        NSColor(red: 0.60, green: 0.85, blue: 0.92, alpha: 1),
        NSColor(red: 0.44, green: 0.58, blue: 0.86, alpha: 1),
        NSColor(red: 0.78, green: 0.61, blue: 0.43, alpha: 1),
    ]
}

extension NSColor {
    func isClose(to other: NSColor) -> Bool {
        guard let a = usingColorSpace(.deviceRGB), let b = other.usingColorSpace(.deviceRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01
            && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01
    }
}
