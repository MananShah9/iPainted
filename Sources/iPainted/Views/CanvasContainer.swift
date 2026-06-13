import SwiftUI
import AppKit

/// Wraps the AppKit canvas in an NSScrollView for SwiftUI.
struct CanvasContainer: NSViewRepresentable {
    @ObservedObject var state: AppState
    @ObservedObject var document: CanvasDocument

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .underPageBackgroundColor
        scroll.allowsMagnification = false
        scroll.hasHorizontalRuler = true
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = false

        let canvas = CanvasNSView(state: state)
        scroll.documentView = canvas
        state.canvasView = canvas

        // Track mouse-moved for the status bar readout.
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: canvas, userInfo: nil)
        canvas.addTrackingArea(tracking)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let canvas = scroll.documentView as? CanvasNSView else { return }
        scroll.rulersVisible = state.showRulers
        canvas.refreshAll()
    }
}

extension CanvasNSView {
    override func magnify(with event: NSEvent) {
        let newZoom = min(8, max(0.125, state.zoom * (1 + event.magnification)))
        state.zoom = newZoom
        refreshAll()
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let factor: CGFloat = event.scrollingDeltaY > 0 ? 1.1 : 0.9
            state.zoom = min(8, max(0.125, state.zoom * factor))
            refreshAll()
        } else {
            super.scrollWheel(with: event)
        }
    }
}
