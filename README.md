# iPainted

A lightweight, native macOS paint app modeled on Windows 11 Paint.

## Build & run

```sh
# Quick run (debug, no bundle):
swift run

# Build the distributable .app (with generated icon):
./scripts/build_app.sh          # -> iPainted.app
open iPainted.app

# Headless engine sanity checks:
swift build && .build/debug/iPainted --selftest
```

Requires macOS 14+ and a Swift 5.9+ toolchain (Xcode 15+).

## Project layout

```
Sources/iPainted/
  App.swift                 @main scene, menu commands, file ops
  Models/                   Enums, Layer (CGContext-backed), Document (+ undo/IO)
  Drawing/                  StrokeEngine, ShapePaths, FloodFill
  Views/                    CanvasNSView (+Mouse, +Selection), CanvasContainer
  UI/                       AppState, ToolbarView, Panels, ContentView
  SelfTest.swift            --selftest engine checks
```

## To raise issues or contribute, please open a GitHub issue or pull request. Contributions are welcome!

## License is licensed under the MIT License. See [LICENSE](LICENSE) for details.