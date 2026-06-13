import AppKit
import UniformTypeIdentifiers

/// The paint document: an ordered stack of layers plus undo history and file state.
final class CanvasDocument: ObservableObject {
    @Published var layers: [Layer] = []
    @Published var activeLayerIndex: Int = 0
    @Published private(set) var canvasSize: CGSize
    @Published var isDirty = false
    var fileURL: URL?

    private struct UndoState {
        let layerSnapshots: [(id: UUID, name: String, visible: Bool, opacity: CGFloat, data: Data)]
        let canvasSize: CGSize
        let activeIndex: Int
    }
    private var undoStack: [UndoState] = []
    private var redoStack: [UndoState] = []
    private let maxUndo = 60

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var activeLayer: Layer? {
        layers.indices.contains(activeLayerIndex) ? layers[activeLayerIndex] : nil
    }

    init(size: CGSize = CGSize(width: 1152, height: 648)) {
        canvasSize = size
        layers = [Layer(size: size, name: "Background", fill: .white)]
    }

    // MARK: - Compositing

    /// Flattened image of all visible layers (bottom of array = bottom of stack).
    func compositeImage() -> CGImage? {
        let ctx = Layer.makeContext(size: canvasSize)
        for layer in layers where layer.isVisible {
            guard let img = layer.cgImage else { continue }
            ctx.setAlpha(layer.opacity)
            ctx.draw(img, in: CGRect(origin: .zero, size: canvasSize))
        }
        return ctx.makeImage()
    }

    // MARK: - Undo

    private func captureState() -> UndoState? {
        var snaps: [(UUID, String, Bool, CGFloat, Data)] = []
        for layer in layers {
            guard let data = layer.snapshotData() else { return nil }
            snaps.append((layer.id, layer.name, layer.isVisible, layer.opacity, data))
        }
        return UndoState(layerSnapshots: snaps.map { (id: $0.0, name: $0.1, visible: $0.2, opacity: $0.3, data: $0.4) },
                         canvasSize: canvasSize, activeIndex: activeLayerIndex)
    }

    /// Call BEFORE mutating layers/canvas.
    func registerUndo() {
        guard let state = captureState() else { return }
        undoStack.append(state)
        if undoStack.count > maxUndo { undoStack.removeFirst() }
        redoStack.removeAll()
        isDirty = true
        objectWillChange.send()
    }

    private func apply(_ state: UndoState) {
        canvasSize = state.canvasSize
        layers = state.layerSnapshots.map { snap in
            let layer = Layer(size: state.canvasSize, name: snap.name)
            layer.isVisible = snap.visible
            layer.opacity = snap.opacity
            layer.restore(from: snap.data, size: state.canvasSize)
            return layer
        }
        activeLayerIndex = min(state.activeIndex, max(0, layers.count - 1))
        objectWillChange.send()
    }

    func undo() {
        guard let prev = undoStack.popLast(), let current = captureState() else { return }
        redoStack.append(current)
        apply(prev)
    }

    func redo() {
        guard let next = redoStack.popLast(), let current = captureState() else { return }
        undoStack.append(current)
        apply(next)
    }

    /// Notify views that pixel content changed (without structural change).
    func contentChanged() {
        objectWillChange.send()
    }

    // MARK: - Canvas operations

    func resizeCanvas(to newSize: CGSize, stretch: Bool) {
        guard newSize.width >= 1, newSize.height >= 1 else { return }
        registerUndo()
        setCanvasSize(newSize, stretch: stretch)
    }

    /// Resize the canvas and ALL layers, anchoring existing content at the
    /// top-left (or stretching it). Crucially this keeps `canvasSize` in sync
    /// with the layers — callers that resize layers directly without going
    /// through here will leave the view geometry pointing at a stale size.
    /// Does NOT register undo; the caller must do so before mutating.
    func setCanvasSize(_ newSize: CGSize, stretch: Bool = false) {
        guard newSize.width >= 1, newSize.height >= 1, newSize != canvasSize else { return }
        for (i, layer) in layers.enumerated() {
            let bg: NSColor? = (i == 0 && !stretch) ? .white : nil
            layer.resizeCanvas(to: newSize, stretch: stretch, background: bg)
        }
        canvasSize = newSize
        objectWillChange.send()
    }

    func transform(_ op: ImageTransform) {
        registerUndo()
        layers.forEach { $0.transformed(op) }
        if let first = layers.first { canvasSize = first.size }
    }

    func crop(to rect: CGRect) {
        let clamped = rect.intersection(CGRect(origin: .zero, size: canvasSize))
        guard clamped.width >= 1, clamped.height >= 1 else { return }
        registerUndo()
        layers.forEach { $0.crop(to: clamped) }
        canvasSize = clamped.size
    }

    // MARK: - Layer management

    func addLayer() {
        registerUndo()
        let layer = Layer(size: canvasSize, name: "Layer \(layers.count + 1)")
        layers.insert(layer, at: activeLayerIndex + 1)
        activeLayerIndex += 1
    }

    func deleteActiveLayer() {
        guard layers.count > 1 else { return }
        registerUndo()
        layers.remove(at: activeLayerIndex)
        activeLayerIndex = min(activeLayerIndex, layers.count - 1)
    }

    func duplicateActiveLayer() {
        guard let src = activeLayer, let img = src.cgImage else { return }
        registerUndo()
        let copy = Layer(size: canvasSize, name: src.name + " copy")
        copy.setContents(img)
        copy.opacity = src.opacity
        layers.insert(copy, at: activeLayerIndex + 1)
        activeLayerIndex += 1
    }

    func mergeDown() {
        guard activeLayerIndex > 0, let top = activeLayer else { return }
        registerUndo()
        let bottom = layers[activeLayerIndex - 1]
        if let img = top.cgImage {
            bottom.context.setAlpha(top.opacity)
            bottom.context.draw(img, in: CGRect(origin: .zero, size: canvasSize))
            bottom.context.setAlpha(1)
        }
        layers.remove(at: activeLayerIndex)
        activeLayerIndex -= 1
    }

    func moveLayer(at index: Int, up: Bool) {
        let target = up ? index + 1 : index - 1
        guard layers.indices.contains(index), layers.indices.contains(target) else { return }
        registerUndo()
        layers.swapAt(index, target)
        if activeLayerIndex == index { activeLayerIndex = target }
        else if activeLayerIndex == target { activeLayerIndex = index }
    }

    // MARK: - File I/O

    func newDocument(size: CGSize) {
        canvasSize = size
        layers = [Layer(size: size, name: "Background", fill: .white)]
        activeLayerIndex = 0
        undoStack.removeAll()
        redoStack.removeAll()
        fileURL = nil
        isDirty = false
        objectWillChange.send()
    }

    func open(url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let size = CGSize(width: cg.width, height: cg.height)
        canvasSize = size
        let base = Layer(size: size, name: "Background", fill: .white)
        base.context.draw(cg, in: CGRect(origin: .zero, size: size))
        layers = [base]
        activeLayerIndex = 0
        undoStack.removeAll()
        redoStack.removeAll()
        fileURL = url
        isDirty = false
        objectWillChange.send()
        return true
    }

    @discardableResult
    func save(to url: URL) -> Bool {
        guard let image = compositeImage() else { return false }
        let rep = NSBitmapImageRep(cgImage: image)
        let ext = url.pathExtension.lowercased()
        let fileType: NSBitmapImageRep.FileType
        var props: [NSBitmapImageRep.PropertyKey: Any] = [:]
        switch ext {
        case "jpg", "jpeg":
            fileType = .jpeg
            props[.compressionFactor] = 0.92
        case "bmp": fileType = .bmp
        case "tiff", "tif": fileType = .tiff
        case "gif": fileType = .gif
        default: fileType = .png
        }
        guard let data = rep.representation(using: fileType, properties: props) else { return false }
        do {
            try data.write(to: url)
            fileURL = url
            isDirty = false
            objectWillChange.send()
            return true
        } catch {
            return false
        }
    }
}
