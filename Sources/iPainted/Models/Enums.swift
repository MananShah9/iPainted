import Foundation

enum Tool: Equatable {
    case pencil
    case brush
    case eraser
    case fill
    case text
    case eyedropper
    case magnifier
    case selectRect
    case selectLasso
    case shape(ShapeKind)

    var isShape: Bool {
        if case .shape = self { return true }
        return false
    }

    var isSelection: Bool {
        self == .selectRect || self == .selectLasso
    }
}

enum BrushKind: String, CaseIterable, Identifiable {
    case brush = "Brush"
    case calligraphyBrush = "Calligraphy brush"
    case calligraphyPen = "Calligraphy pen"
    case airbrush = "Airbrush"
    case oilBrush = "Oil brush"
    case crayon = "Crayon"
    case marker = "Marker"
    case naturalPencil = "Natural pencil"
    case watercolor = "Watercolor"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .brush: return "paintbrush.pointed.fill"
        case .calligraphyBrush: return "paintbrush.fill"
        case .calligraphyPen: return "pencil.tip"
        case .airbrush: return "humidifier.and.droplets.fill"
        case .oilBrush: return "paintbrush"
        case .crayon: return "pencil.and.outline"
        case .marker: return "highlighter"
        case .naturalPencil: return "pencil"
        case .watercolor: return "drop.fill"
        }
    }
}

enum ShapeKind: String, CaseIterable, Identifiable {
    case line = "Line"
    case curve = "Curve"
    case oval = "Oval"
    case rectangle = "Rectangle"
    case roundedRectangle = "Rounded rectangle"
    case polygon = "Polygon"
    case triangle = "Triangle"
    case rightTriangle = "Right triangle"
    case diamond = "Diamond"
    case pentagon = "Pentagon"
    case hexagon = "Hexagon"
    case arrowRight = "Right arrow"
    case arrowLeft = "Left arrow"
    case arrowUp = "Up arrow"
    case arrowDown = "Down arrow"
    case star4 = "Four-point star"
    case star5 = "Five-point star"
    case star6 = "Six-point star"
    case calloutRect = "Rounded callout"
    case calloutOval = "Oval callout"
    case calloutCloud = "Cloud callout"
    case heart = "Heart"
    case lightning = "Lightning"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .line: return "line.diagonal"
        case .curve: return "scribble"
        case .oval: return "oval"
        case .rectangle: return "rectangle"
        case .roundedRectangle: return "rectangle.roundedtop"
        case .polygon: return "pentagon.bottomhalf.filled"
        case .triangle: return "triangle"
        case .rightTriangle: return "triangle.righthalf.filled"
        case .diamond: return "diamond"
        case .pentagon: return "pentagon"
        case .hexagon: return "hexagon"
        case .arrowRight: return "arrowshape.right"
        case .arrowLeft: return "arrowshape.left"
        case .arrowUp: return "arrowshape.up"
        case .arrowDown: return "arrowshape.down"
        case .star4: return "sparkle"
        case .star5: return "star"
        case .star6: return "staroflife"
        case .calloutRect: return "bubble.left"
        case .calloutOval: return "ellipsis.bubble"
        case .calloutCloud: return "cloud"
        case .heart: return "heart"
        case .lightning: return "bolt"
        }
    }
}

enum ShapeFillStyle: String, CaseIterable, Identifiable {
    case none = "No fill"
    case solid = "Solid color"
    var id: String { rawValue }
}

enum ShapeOutlineStyle: String, CaseIterable, Identifiable {
    case solid = "Solid color"
    case none = "No outline"
    var id: String { rawValue }
}
