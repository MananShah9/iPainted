import SwiftUI
import AppKit

struct ToolbarView: View {
    @ObservedObject var state: AppState
    @ObservedObject var document: CanvasDocument
    @Binding var showResizeSheet: Bool

    var body: some View {
        HStack(spacing: 10) {
            undoRedoGroup
            divider
            selectionGroup
            imageGroup
            divider
            toolsGroup
            divider
            brushGroup
            shapesGroup
            divider
            sizeGroup
            divider
            colorsGroup
            if state.tool == .text {
                divider
                textOptionsGroup
            }
            Spacer()
            Button {
                state.canvasView?.removeBackground()
            } label: {
                Image(systemName: "person.and.background.dotted")
            }
            .buttonStyle(.borderless)
            .help("Remove background (AI)")
            Button {
                state.showLayers.toggle()
            } label: {
                Image(systemName: "square.3.layers.3d")
            }
            .buttonStyle(.borderless)
            .help("Layers")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var divider: some View {
        Divider().frame(height: 26)
    }

    // MARK: Groups

    private var undoRedoGroup: some View {
        HStack(spacing: 4) {
            Button { undoDocument() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!document.canUndo)
                .help("Undo (⌘Z)")
            Button { redoDocument() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!document.canRedo)
                .help("Redo (⇧⌘Z)")
        }
        .buttonStyle(.borderless)
    }

    private func undoDocument() {
        state.canvasView?.commitFloatingSelection()
        state.canvasView?.clearSelection()
        document.undo()
        state.canvasView?.refreshAll()
    }

    private func redoDocument() {
        document.redo()
        state.canvasView?.refreshAll()
    }

    private var selectionGroup: some View {
        Menu {
            Button("Rectangular selection") { state.tool = .selectRect }
            Button("Free-form selection") { state.tool = .selectLasso }
            Divider()
            Button("Select all") { state.canvasView?.selectAll() }
            Button("Invert selection") { state.canvasView?.invertSelection() }
                .disabled(!state.hasSelection)
            Button("Delete") { state.canvasView?.deleteSelectionContents() }
                .disabled(!state.hasSelection)
            Divider()
            Toggle("Transparent selection", isOn: $state.transparentSelection)
        } label: {
            Label("Select", systemImage: "rectangle.dashed")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .background(toolHighlight(state.tool.isSelection))
        .help("Selection tools")
    }

    private var imageGroup: some View {
        HStack(spacing: 4) {
            Button { state.canvasView?.cropToSelection() } label: { Image(systemName: "crop") }
                .disabled(!state.hasSelection)
                .help("Crop to selection")
            Button { showResizeSheet = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right.square") }
                .help("Resize image…")
            Menu {
                Button("Rotate right 90°") { transform(.rotate90CW) }
                Button("Rotate left 90°") { transform(.rotate90CCW) }
                Button("Rotate 180°") { transform(.rotate180) }
                Divider()
                Button("Flip horizontal") { transform(.flipHorizontal) }
                Button("Flip vertical") { transform(.flipVertical) }
            } label: {
                Image(systemName: "rotate.right")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Rotate or flip")
        }
        .buttonStyle(.borderless)
    }

    private func transform(_ op: ImageTransform) {
        state.canvasView?.commitFloatingSelection()
        state.canvasView?.clearSelection()
        document.transform(op)
        state.canvasView?.refreshAll()
    }

    private var toolsGroup: some View {
        HStack(spacing: 2) {
            toolButton(.pencil, "pencil", "Pencil")
            toolButton(.fill, "drop.fill", "Fill with color")
            toolButton(.text, "textformat", "Text")
            toolButton(.eraser, "eraser", "Eraser")
            toolButton(.eyedropper, "eyedropper", "Color picker")
            toolButton(.magnifier, "magnifyingglass", "Magnifier")
        }
    }

    private func toolButton(_ tool: Tool, _ symbol: String, _ help: String) -> some View {
        Button {
            state.canvasView?.commitTextIfNeeded()
            state.canvasView?.commitPendingCurveIfAny()
            state.tool = tool
        } label: {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .background(toolHighlight(state.tool == tool))
        .help(help)
    }

    private func toolHighlight(_ active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(active ? Color.accentColor.opacity(0.22) : Color.clear)
    }

    private var brushGroup: some View {
        Menu {
            ForEach(BrushKind.allCases) { kind in
                Button {
                    state.brushKind = kind
                    state.tool = .brush
                } label: {
                    Label(kind.rawValue, systemImage: kind.symbolName)
                }
            }
        } label: {
            Label("Brushes", systemImage: state.brushKind.symbolName)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .background(toolHighlight(state.tool == .brush))
        .help("Brushes")
    }

    @State private var shapesExpanded = false

    private var shapesGroup: some View {
        HStack(spacing: 6) {
            Button {
                shapesExpanded.toggle()
            } label: {
                Label("Shapes", systemImage: currentShapeSymbol)
            }
            .buttonStyle(.borderless)
            .background(toolHighlight(state.tool.isShape))
            .popover(isPresented: $shapesExpanded, arrowEdge: .bottom) {
                shapesPopover
            }
            .help("Shapes")
        }
    }

    private var currentShapeSymbol: String {
        if case .shape(let kind) = state.tool { return kind.symbolName }
        return "square.on.circle"
    }

    private var shapesPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 6), spacing: 4) {
                ForEach(ShapeKind.allCases) { kind in
                    Button {
                        state.canvasView?.commitPendingCurveIfAny()
                        state.tool = .shape(kind)
                        shapesExpanded = false
                    } label: {
                        Image(systemName: kind.symbolName)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .background(toolHighlight(state.tool == .shape(kind)))
                    .help(kind.rawValue)
                }
            }
            Divider()
            Picker("Outline", selection: $state.shapeOutline) {
                ForEach(ShapeOutlineStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Fill", selection: $state.shapeFill) {
                ForEach(ShapeFillStyle.allCases) { Text($0.rawValue).tag($0) }
            }
        }
        .padding(12)
        .frame(width: 250)
    }

    @State private var sizePopover = false

    private var sizeGroup: some View {
        Button {
            sizePopover.toggle()
        } label: {
            Image(systemName: "lineweight")
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $sizePopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Size: \(Int(currentSizeBinding.wrappedValue))px")
                    .font(.caption)
                ForEach([1, 3, 5, 8], id: \.self) { (preset: Int) in
                    Button {
                        currentSizeBinding.wrappedValue = CGFloat(preset)
                    } label: {
                        RoundedRectangle(cornerRadius: CGFloat(preset) / 2)
                            .frame(width: 120, height: max(1, CGFloat(preset)))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.borderless)
                }
                Slider(value: currentSizeBinding, in: 1...64)
                    .frame(width: 160)
            }
            .padding(12)
        }
        .help("Stroke size")
    }

    private var currentSizeBinding: Binding<CGFloat> {
        if state.tool.isShape {
            return $state.shapeThickness
        }
        return $state.brushSize
    }

    // MARK: Colors

    private var colorsGroup: some View {
        HStack(spacing: 8) {
            colorSlots
            paletteGrid
            ColorPicker("", selection: customColorBinding, supportsOpacity: false)
                .labelsHidden()
                .help("Edit colors")
        }
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: state.activeColor) },
            set: { newValue in
                let ns = NSColor(newValue)
                state.setActiveColor(ns)
                state.addCustomColor(ns)
            })
    }

    private var colorSlots: some View {
        HStack(spacing: 6) {
            colorSlot(slot: 1, color: state.primaryColor, label: "1")
            colorSlot(slot: 2, color: state.secondaryColor, label: "2")
        }
    }

    private func colorSlot(slot: Int, color: NSColor, label: String) -> some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: color))
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(state.activeColorSlot == slot ? Color.accentColor : Color.secondary.opacity(0.4),
                                lineWidth: state.activeColorSlot == slot ? 2 : 1))
            Text(label).font(.system(size: 8))
        }
        .onTapGesture { state.activeColorSlot = slot }
        .help(slot == 1 ? "Color 1 (foreground)" : "Color 2 (background)")
    }

    private var paletteGrid: some View {
        let colors = AppState.defaultPalette + state.customColors
        return LazyHGrid(rows: Array(repeating: GridItem(.fixed(13), spacing: 3), count: 2), spacing: 3) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color(nsColor: color))
                    .frame(width: 13, height: 13)
                    .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.black.opacity(0.15), lineWidth: 0.5))
                    .onTapGesture { state.setActiveColor(color) }
            }
        }
        .frame(height: 30)
    }

    // MARK: Text options

    private var textOptionsGroup: some View {
        HStack(spacing: 6) {
            Menu(state.textFont) {
                ForEach(["Helvetica", "Times New Roman", "Courier New", "Georgia", "Verdana",
                         "Arial", "Comic Sans MS", "Impact", "Menlo", "SF Pro"], id: \.self) { name in
                    Button(name) { state.textFont = name }
                }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 130)
            Stepper(value: $state.textSize, in: 8...144, step: 2) {
                Text("\(Int(state.textSize))pt").font(.caption).frame(width: 36)
            }
            Toggle("B", isOn: $state.textBold).toggleStyle(.button).bold()
            Toggle("I", isOn: $state.textItalic).toggleStyle(.button).italic()
            Toggle("U", isOn: $state.textUnderline).toggleStyle(.button).underline()
        }
    }
}
