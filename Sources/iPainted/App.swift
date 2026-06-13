import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct IPaintedApp: App {
    @StateObject private var state = AppState()

    init() {
        SelfTest.runIfRequested()
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        Window(windowTitle, id: "main") {
            ContentView(state: state)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            fileCommands
            editCommands
            imageCommands
            viewCommands
        }
    }

    private var windowTitle: String {
        "iPainted"
    }

    // MARK: - File

    private var fileCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { FileOps.newDocument(state) }
                .keyboardShortcut("n")
            Button("Open…") { FileOps.open(state) }
                .keyboardShortcut("o")
            Divider()
            Button("Save") { FileOps.save(state) }
                .keyboardShortcut("s")
            Button("Save As…") { FileOps.saveAs(state) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }

    // MARK: - Edit

    private var editCommands: some Commands {
        Group {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    state.canvasView?.commitFloatingSelection()
                    state.canvasView?.clearSelection()
                    state.document.undo()
                    state.canvasView?.refreshAll()
                }
                .keyboardShortcut("z")
                .disabled(!state.document.canUndo)
                Button("Redo") {
                    state.document.redo()
                    state.canvasView?.refreshAll()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!state.document.canRedo)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    if !forwardToFocusedText(#selector(NSText.cut(_:))) { state.canvasView?.cutSelection() }
                }
                .keyboardShortcut("x")
                Button("Copy") {
                    if !forwardToFocusedText(#selector(NSText.copy(_:))) { state.canvasView?.copySelection() }
                }
                .keyboardShortcut("c")
                Button("Paste") {
                    if !forwardToFocusedText(#selector(NSText.paste(_:))) { state.canvasView?.paste() }
                }
                .keyboardShortcut("v")
                Button("Delete") { state.canvasView?.deleteSelectionContents() }
                Divider()
                Button("Select All") {
                    if !forwardToFocusedText(#selector(NSText.selectAll(_:))) { state.canvasView?.selectAll() }
                }
                .keyboardShortcut("a")
                Button("Invert Selection") { state.canvasView?.invertSelection() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Deselect") {
                    state.canvasView?.commitFloatingSelection()
                    state.canvasView?.clearSelection()
                    state.canvasView?.needsDisplay = true
                }
                .keyboardShortcut("d")
            }
        }
    }

    // MARK: - Image

    private var imageCommands: some Commands {
        CommandMenu("Image") {
            Button("Crop to Selection") { state.canvasView?.cropToSelection() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Divider()
            Button("Rotate Right 90°") { transform(.rotate90CW) }
                .keyboardShortcut("r")
            Button("Rotate Left 90°") { transform(.rotate90CCW) }
                .keyboardShortcut("l")
            Button("Rotate 180°") { transform(.rotate180) }
            Button("Flip Horizontal") { transform(.flipHorizontal) }
            Button("Flip Vertical") { transform(.flipVertical) }
            Divider()
            Button("Remove Background") { state.canvasView?.removeBackground() }
            Divider()
            Button("Swap Colors") { state.swapColors() }
                .keyboardShortcut("x", modifiers: [.command, .shift])
        }
    }

    /// When a text view (the text tool editor) has focus, route clipboard
    /// commands to it instead of the canvas.
    private func forwardToFocusedText(_ selector: Selector) -> Bool {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        tv.perform(selector, with: nil)
        return true
    }

    private func transform(_ op: ImageTransform) {
        state.canvasView?.commitFloatingSelection()
        state.canvasView?.clearSelection()
        state.document.transform(op)
        state.canvasView?.refreshAll()
    }

    // MARK: - View

    private var viewCommands: some Commands {
        CommandMenu("Zoom") {
            Button("Zoom In") {
                state.zoom = min(8, state.zoom * 1.25)
                state.canvasView?.refreshAll()
            }
            .keyboardShortcut("=")
            Button("Zoom Out") {
                state.zoom = max(0.125, state.zoom / 1.25)
                state.canvasView?.refreshAll()
            }
            .keyboardShortcut("-")
            Button("Actual Size") {
                state.zoom = 1
                state.canvasView?.refreshAll()
            }
            .keyboardShortcut("0")
            Divider()
            Toggle("Gridlines", isOn: gridBinding)
                .keyboardShortcut("g")
            Toggle("Rulers", isOn: rulersBinding)
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Toggle("Layers Panel", isOn: layersBinding)
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }

    private var gridBinding: Binding<Bool> {
        Binding(get: { state.showGrid }, set: { state.showGrid = $0; state.canvasView?.needsDisplay = true })
    }
    private var rulersBinding: Binding<Bool> {
        Binding(get: { state.showRulers }, set: { state.showRulers = $0 })
    }
    private var layersBinding: Binding<Bool> {
        Binding(get: { state.showLayers }, set: { state.showLayers = $0 })
    }
}

// MARK: - File operations

enum FileOps {
    static let imageTypes: [UTType] = [.png, .jpeg, .bmp, .tiff, .gif, .heic, .webP]

    /// Returns true if it is OK to discard the current document.
    static func confirmDiscard(_ state: AppState) -> Bool {
        guard state.document.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save changes?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save(state)
            return !state.document.isDirty
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    static func newDocument(_ state: AppState) {
        guard confirmDiscard(state) else { return }
        state.canvasView?.clearSelection()
        state.document.newDocument(size: CGSize(width: 1152, height: 648))
        state.canvasView?.refreshAll()
    }

    static func open(_ state: AppState) {
        guard confirmDiscard(state) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = imageTypes
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.canvasView?.clearSelection()
        if state.document.open(url: url) {
            state.zoom = 1
            state.canvasView?.refreshAll()
        }
    }

    static func save(_ state: AppState) {
        state.canvasView?.commitFloatingSelection()
        state.canvasView?.commitTextIfNeeded()
        if let url = state.document.fileURL {
            state.document.save(to: url)
        } else {
            saveAs(state)
        }
    }

    static func saveAs(_ state: AppState) {
        state.canvasView?.commitFloatingSelection()
        state.canvasView?.commitTextIfNeeded()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .bmp, .tiff, .gif]
        panel.canSelectHiddenExtension = true
        panel.nameFieldStringValue = state.document.fileURL?.lastPathComponent ?? "Untitled.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.document.save(to: url)
    }
}
