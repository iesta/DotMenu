# DotMenu

A minimal macOS menu bar screen capture utility. Click the dashed-square icon in the menu bar, select a screen region, and view the result in a resizable window with Copy and Save toolbar buttons.

## Features

- **Menu bar icon** — dashed square, drawn in code with `NSBezierPath`
- **Capture selection** — macOS native crosshair overlay (via `/usr/sbin/screencapture -i`)
- **View capture** — captured image opens in a titled, resizable window
- **Copy to pasteboard** — toolbar button copies the image as TIFF data
- **Save to disk** — toolbar button saves a PNG to `~/Pictures/DotMenu/`
- **Automatic activation** — app appears in the Dock and menu bar when a capture window is open, returns to menu-bar-only when closed
- **Permission guided** — if Screen Capture access is denied, opens System Settings directly

## Build & Install

```sh
make install
```

This builds `DotMenu.app`, copies it to `/Applications`, and launches it. The app is ad-hoc code-signed with a **stable designated requirement** (`identifier "com.example.DotMenu"`) so the TCC permission grant survives rebuilds.

### Other commands

| Command       | Effect                                     |
|---------------|--------------------------------------------|
| `make build`  | Build `DotMenu.app` in the project root    |
| `make run`    | Build and launch from the project root     |
| `make clean`  | Remove build artifacts and generated files |

## First-time setup

1. Run `make install`
2. Click **Capture selection** in the menu bar
3. If prompted, grant **Screen Capture** access in the system dialog
4. Select a screen region — the image appears in a window
5. Use the **Copy** and **Save** toolbar buttons

If the permission dialog is dismissed, or after a rebuild, the app will open System Settings → Privacy & Security → Screen Capture automatically.

## Version system

Each build increments an auto-generated version (5-digit, starting at `00001`). The version is displayed in Preferences and is tracked in `src/version.txt`:

```
src/version.txt       # Current version (incremented after each successful build)
src/VersionGenerated.swift  # Auto-generated: `let appVersion = "000XX"`
```

The version is incremented **only after a successful compile**, so failed builds don't create gaps.

## Project structure

```
src/
├── main.swift           # Single source file — AppKit + SwiftUI
├── Info.plist           # LSUIElement = true, CFBundleIdentifier = com.example.DotMenu
├── AppIcon.icns         # Finder icon
├── make-icon.swift      # Icon generator helper (one-time use)
├── version.txt          # Build version counter
└── VersionGenerated.swift   # Auto-generated, .gitignored

Makefile                 # Build, sign, install, launch
AGENTS.md                # Agent development notes
README.md                # This file
```

## Technical details

- **No Xcode project or Package.swift** — bare `swiftc` compilation
- **No asset catalog** — the dashed-square icon is drawn at runtime with `NSBezierPath`
- **No Dock icon by default** — uses `.accessory` activation policy, switches to `.regular` when a capture window is open
- **Single source file** — `src/main.swift`, compiled with `-framework AppKit -framework SwiftUI`
- **Code signing** — ad-hoc signed with `--requirements '=designated => identifier "com.example.DotMenu"'` for stable TCC tracking
- **Screen Capture permission** — checked via `CGPreflightScreenCaptureAccess()` before each capture; denied → opens System Settings
- **Capture engine** — uses `/usr/sbin/screencapture -i` via `Process` for the native selection overlay

## TODO

See [TODO.md](TODO.md) for planned features.
