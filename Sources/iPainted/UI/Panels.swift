import SwiftUI
import AppKit

// MARK: - Layers panel

struct LayersPanel: View {
    @ObservedObject var state: AppState
    @ObservedObject var document: CanvasDocument

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Layers").font(.headline)
                Spacer()
                Button { document.addLayer(); refresh() } label: { Image(systemName: "plus") }
                    .help("Add layer")
                Button { document.duplicateActiveLayer(); refresh() } label: { Image(systemName: "plus.square.on.square") }
                    .help("Duplicate layer")
                Button { document.deleteActiveLayer(); refresh() } label: { Image(systemName: "trash") }
                    .disabled(document.layers.count <= 1)
                    .help("Delete layer")
            }
            .buttonStyle(.borderless)
            .padding(10)
            Divider()
            List {
                // Top of stack first.
                ForEach(Array(document.layers.enumerated()).reversed(), id: \.element.id) { index, layer in
                    layerRow(index: index, layer: layer)
                }
            }
            .listStyle(.plain)
            Divider()
            HStack(spacing: 6) {
                Button { document.moveLayer(at: document.activeLayerIndex, up: true); refresh() } label: {
                    Image(systemName: "chevron.up")
                }.help("Move layer up")
                Button { document.moveLayer(at: document.activeLayerIndex, up: false); refresh() } label: {
                    Image(systemName: "chevron.down")
                }.help("Move layer down")
                Button { document.mergeDown(); refresh() } label: {
                    Image(systemName: "arrow.merge")
                }
                .disabled(document.activeLayerIndex == 0)
                .help("Merge down")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
            if let layer = document.activeLayer {
                opacityControl(layer: layer)
            }
        }
        .frame(width: 220)
        .background(.thinMaterial)
    }

    private func layerRow(index: Int, layer: Layer) -> some View {
        HStack(spacing: 8) {
            Button {
                layer.isVisible.toggle()
                refresh()
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(layer.isVisible ? .primary : .tertiary)
            }
            .buttonStyle(.borderless)
            thumbnail(for: layer)
            Text(layer.name).lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            state.canvasView?.commitFloatingSelection()
            document.activeLayerIndex = index
            refresh()
        }
        .listRowBackground(index == document.activeLayerIndex ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    private func thumbnail(for layer: Layer) -> some View {
        Group {
            if let cg = layer.cgImage {
                Image(decorative: cg, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.white
            }
        }
        .frame(width: 36, height: 24)
        .background(Color.white)
        .overlay(Rectangle().stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))
    }

    private func opacityControl(layer: Layer) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Opacity \(Int(layer.opacity * 100))%").font(.caption)
            Slider(value: Binding(
                get: { layer.opacity },
                set: { layer.opacity = $0; refresh() }), in: 0...1)
        }
        .padding(10)
    }

    private func refresh() {
        document.contentChanged()
        state.canvasView?.refreshAll()
    }
}

// MARK: - Status bar

struct StatusBarView: View {
    @ObservedObject var state: AppState
    @ObservedObject var document: CanvasDocument

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Image(systemName: "plus.viewfinder").font(.caption)
                Text(cursorText).font(.caption).monospacedDigit()
                    .frame(width: 90, alignment: .leading)
            }
            if !state.selectionSizeText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.dashed").font(.caption)
                    Text(state.selectionSizeText).font(.caption).monospacedDigit()
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "square.resize").font(.caption)
                Text("\(Int(document.canvasSize.width)) × \(Int(document.canvasSize.height))px")
                    .font(.caption).monospacedDigit()
            }
            if !state.statusMessage.isEmpty {
                Text(state.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Fit") { fitToWindow() }
                .buttonStyle(.borderless)
                .font(.caption)
            Image(systemName: "minus.magnifyingglass").font(.caption)
            Slider(value: zoomBinding, in: 0.125...8)
                .frame(width: 120)
            Image(systemName: "plus.magnifyingglass").font(.caption)
            Text("\(Int(state.zoom * 100))%")
                .font(.caption).monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private var cursorText: String {
        guard let p = state.cursorPosition else { return "—" }
        return "\(Int(p.x)), \(Int(p.y))px"
    }

    private var zoomBinding: Binding<CGFloat> {
        Binding(get: { state.zoom }, set: { state.zoom = $0; state.canvasView?.refreshAll() })
    }

    private func fitToWindow() {
        guard let canvas = state.canvasView,
              let visible = canvas.enclosingScrollView?.contentView.bounds.size else { return }
        let cs = document.canvasSize
        let pad = CanvasNSView.pad * 2 + 40
        let scale = min((visible.width - pad) / cs.width, (visible.height - pad) / cs.height)
        state.zoom = min(8, max(0.125, scale))
        canvas.refreshAll()
    }
}

// MARK: - Resize sheet

struct ResizeSheet: View {
    @ObservedObject var state: AppState
    @ObservedObject var document: CanvasDocument
    @Binding var isPresented: Bool

    @State private var widthText = ""
    @State private var heightText = ""
    @State private var byPercent = false
    @State private var keepAspect = true
    @State private var stretchContent = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Resize image").font(.headline)
            Picker("", selection: $byPercent) {
                Text("Pixels").tag(false)
                Text("Percent").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack {
                Text("Width").frame(width: 50, alignment: .leading)
                TextField("", text: $widthText)
                    .frame(width: 80)
                    .onChange(of: widthText) { _, newValue in
                        if keepAspect, let w = Double(newValue) {
                            let ratio = document.canvasSize.height / document.canvasSize.width
                            heightText = byPercent ? newValue : String(Int((w * ratio).rounded()))
                        }
                    }
            }
            HStack {
                Text("Height").frame(width: 50, alignment: .leading)
                TextField("", text: $heightText).frame(width: 80)
            }
            Toggle("Maintain aspect ratio", isOn: $keepAspect)
            Toggle("Stretch contents (off = grow/crop canvas)", isOn: $stretchContent)
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("OK") { apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            widthText = byPercent ? "100" : String(Int(document.canvasSize.width))
            heightText = byPercent ? "100" : String(Int(document.canvasSize.height))
        }
    }

    private func apply() {
        guard let w = Double(widthText), let h = Double(heightText), w > 0, h > 0 else { return }
        let newSize: CGSize
        if byPercent {
            newSize = CGSize(width: document.canvasSize.width * w / 100,
                             height: document.canvasSize.height * h / 100)
        } else {
            newSize = CGSize(width: w, height: h)
        }
        state.canvasView?.commitFloatingSelection()
        state.canvasView?.clearSelection()
        document.resizeCanvas(to: newSize, stretch: stretchContent)
        state.canvasView?.refreshAll()
        isPresented = false
    }
}
