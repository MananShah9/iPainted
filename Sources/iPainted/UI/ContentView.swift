import SwiftUI

struct ContentView: View {
    @ObservedObject var state: AppState
    @State private var showResizeSheet = false

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(state: state, document: state.document, showResizeSheet: $showResizeSheet)
                .background(.bar)
            Divider()
            HStack(spacing: 0) {
                CanvasContainer(state: state, document: state.document)
                if state.showLayers {
                    Divider()
                    LayersPanel(state: state, document: state.document)
                }
            }
            Divider()
            StatusBarView(state: state, document: state.document)
                .background(.bar)
        }
        .sheet(isPresented: $showResizeSheet) {
            ResizeSheet(state: state, document: state.document, isPresented: $showResizeSheet)
        }
        .frame(minWidth: 980, minHeight: 600)
    }
}
