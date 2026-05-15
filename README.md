# DotMenu

A minimal macOS menu bar app with screen capture.

- **Menu bar icon** — dashed square (drawn in code)
- **Capture selection** — select a screen region (macOS native overlay), image saved to `~/Pictures/DotMenu/` and shown in a window
- **About** — version info popup

## Build & install

```sh
make install
```

This builds `DotMenu.app`, copies it to `/Applications`, and launches it. The app is code-signed anonymously on each build, so installing to `/Applications` keeps the Screen Recording permission grant stable across rebuilds.

### Other commands

| Command | Effect |
|---|---|
| `make build` | Build `DotMenu.app` in project root |
| `make run` | Build and launch from project root |
| `make clean` | Remove build artifacts |

## Permissions

**Screen Recording** is required for screen capture. On first capture attempt (`make install` → click "Capture selection"), macOS will prompt you. If you miss the prompt, or after a rebuild:

1. Open System Settings → Privacy & Security → Screen Recording
2. Enable DotMenu (you may need to add it with the `+` button)
3. Re-launch and capture again

## Project structure

```
src/
├── main.swift           # Single source file: AppKit + SwiftUI
├── Info.plist           # LSUIElement = true (no dock icon)
└── AppIcon.icns         # Finder icon

Makefile                 # Build, install to /Applications, launch
AGENTS.md                # Agent instructions
README.md                # This file
```