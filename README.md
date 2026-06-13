# iPainted

A lightweight, native macOS paint app modeled on Windows 11 Paint.

## Like the project? Consider sponsoring me on GitHub ❤️
[![Sponsor](https://img.shields.io/badge/Sponsor-MananShah9-ea4aaa?style=flat-square&logo=github-sponsors)](https://github.com/sponsors/MananShah9)

## Easy Install

1. Download the latest **`iPainted-x.y.z.dmg`** from the [Releases page](https://github.com/MananShah9/iPainted/releases).
2. Open the DMG and drag **iPainted** into your **Applications** folder.
3. The first time you open it, macOS may say *"iPainted is damaged"* or *"can't be opened because it's from an unidentified developer."*

   **This is normal and the app is safe.** It only means the app isn't signed with a paid Apple Developer account ($99/yr) — apparently, making free, open-source software is only cool if you pay Apple rent!

   To open it, do **either** of these once:
   - **Right-click** iPainted in Applications → **Open** → **Open**, or
   - run this one line in Terminal:
     ```sh
     xattr -dr com.apple.quarantine /Applications/iPainted.app
     ```

   After that, it opens normally like any other app.

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

## Release (maintainers)

One command bumps the version, builds the app, packages a DMG, commits, tags, and publishes a GitHub release:

```sh
./scripts/deploy.sh            # patch bump, e.g. 1.0.0 -> 1.0.1
./scripts/deploy.sh minor      # 1.0.0 -> 1.1.0
./scripts/deploy.sh major      # 1.0.0 -> 2.0.0
./scripts/deploy.sh 1.4.2      # explicit version
```

The version lives in the `VERSION` file (single source of truth, read by `build_app.sh`).
Requires the `gh` CLI: `brew install gh && gh auth login`. A nicer DMG layout uses
`create-dmg` (`brew install create-dmg`); without it the script falls back to `hdiutil`.

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

## Support

If you find iPainted useful and want to support its development or consider sponsoring! Your support helps and keeps the project going:

- **[Sponsor on GitHub](https://github.com/sponsors/MananShah9)**

## To raise issues or contribute, please open a GitHub issue or pull request. Contributions are welcome!

## License is licensed under the MIT License. See [LICENSE](LICENSE) for details.