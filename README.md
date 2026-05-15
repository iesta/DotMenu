# DotMenu

A macOS menu bar screen capture utility with drawing tools. Click the dashed-square icon in the menu bar, select a screen region, and annotate the result with shapes (rectangle, circle, line) before copying or saving.

## Features

- **Capture selection** — macOS native crosshair overlay (`/usr/sbin/screencapture -i`), includes Shift-constrain for perfect squares
- **Drawing tools** — Rectangle, Circle, Line with configurable color (NSColorWell) and Fill toggle
- **Copy to pasteboard** — copies the annotated image (Cmd+C)
- **Save to disk** — saves PNG to `~/Pictures/DotMenu/` (Cmd+S); Save As… for custom location
- **Undo** — removes the last drawn shape
- **Keyboard shortcuts** when the capture window is active: R (Rectangle), C (Circle), L (Line), Cmd+C (Copy), Cmd+S (Save)
- **Global hotkey** — Cmd+Shift+7 triggers capture from anywhere (Carbon `RegisterEventHotKey`, configurable via UserDefaults)
- **Capture history** — last 10 captures persisted to `~/Pictures/DotMenu/.history/` as PNG + JSON; includes final annotated version; accessible from the menu bar
- **Preferences window** — version info, capture folder, shortcut display, Clear History
- **Automatic activation** — app appears in the Dock when a capture window is open, menu-bar-only when closed
- **Permission guided** — denied Screen Capture access opens System Settings automatically

## Build & Install

```sh
make install
```

Builds `DotMenu.app`, copies it to `/Applications`, and launches it. The app is ad-hoc code-signed with a **stable designated requirement** (`identifier "com.example.DotMenu"`) so the TCC permission grant survives rebuilds.

### Other commands

| Command       | Effect                                     |
|---------------|--------------------------------------------|
| `make build`  | Build `DotMenu.app` in the project root    |
| `make run`    | Build and launch from the project root     |
| `make clean`  | Remove build artifacts and generated files |

## First-time setup

1. Run `make install`
2. Click **Capture selection** in the menu bar or press **Cmd+Shift+7**
3. If prompted, grant **Screen Capture** access
4. Select a screen region
5. Draw annotations using the toolbar buttons (Rectangle, Circle, Line)
6. Copy (Cmd+C) or Save (Cmd+S)

## Usage tips

- Hold **Shift** while dragging to constrain Rectangle/Circle to a perfect square/circle
- Select a **Color** from the toolbar color well — persists across restarts
- Enable **Fill** to fill shapes with the current color
- **Undo** removes the last shape
- **History** — captures appear in the menu bar immediately; click to reopen

## Version system

Each build increments an auto-generated version (5-digit, starting at `00001`). Displayed in Preferences.

```
src/version.txt             # Current version (incremented after successful build)
src/VersionGenerated.swift  # Auto-generated: `let appVersion = "000XX"`
```

## Project structure

```
src/
├── main.swift           # Single source file — AppKit + SwiftUI (857 lines)
├── Info.plist           # LSUIElement = true, CFBundleIdentifier = com.example.DotMenu
├── AppIcon.icns         # Finder icon
├── version.txt          # Build version counter
└── VersionGenerated.swift   # Auto-generated, .gitignored

Makefile                 # Build, sign, install, launch
AGENTS.md                # Agent development notes
README.md                # This file
TODO.md                  # Upcoming features
```

## Technical details

- **No Xcode project or Package.swift** — bare `swiftc` compilation
- **No asset catalog** — the dashed-square icon is drawn at runtime with `NSBezierPath`
- **No Dock icon by default** — `.accessory` activation policy, switches to `.regular` when a capture window is open
- **Single source file** — `src/main.swift`, compiled with `-framework AppKit -framework SwiftUI`
- **Code signing** — ad-hoc signed with `--requirements '=designated => identifier "com.example.DotMenu"'` for stable TCC tracking
- **Global hotkey** — Carbon `RegisterEventHotKey`, stored in UserDefaults (key code + modifier flags)
- **Screen Capture permission** — checked via `CGPreflightScreenCaptureAccess()` before each capture; denied → opens System Settings
- **Capture engine** — `/usr/sbin/screencapture -i` via `Process` for the native selection overlay
- **Drawing overlay** — transparent `DrawingOverlayView` on top of `NSImageView`, tracks mouse events, renders with `NSBezierPath`
- **Composited export** — Copy/Save combine the original image + all shapes into a single PNG

## TODO

See [TODO.md](TODO.md) for planned features.
