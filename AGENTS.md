# DotMenu — macOS menu bar app

## Build & run

Always use `make install` to build, install to `/Applications`, and launch —
this keeps the Screen Recording TCC grant stable across rebuilds:

```sh
make install
```

Or for a quick build without installing:

```sh
make run
```

Manual compile equivalent:

```sh
swiftc -o DotMenu.app/Contents/MacOS/DotMenu src/main.swift \
  -framework AppKit -framework SwiftUI \
  -target arm64-apple-macosx14.0
```

## Structure

| File | Purpose |
|---|---|---|
| `src/main.swift` | Single entrypoint — AppKit + SwiftUI, menu bar item, capture, About window |
| `src/version.txt` | Current build version (5-digit, auto-incremented) |
| `src/VersionGenerated.swift` | **Auto-generated** — `let appVersion` constant from `version.txt` |
| `src/Info.plist` | `LSUIElement = true` → no dock icon, menu bar only |
| `src/AppIcon.icns` | Finder icon |
| `Makefile` | `make install` → build + copy to `/Applications` + launch |
| `AGENTS.md` | This file |

## Key details

- **No Xcode project or Package.swift** — bare `swiftc` compilation.
- **No asset catalog** — the dashed-square icon is drawn in code (`NSBezierPath`).
- **No Dock icon** — `LSUIElement` + `.accessory` activation policy keep it in the menu bar only.
- **Single source file** — `src/main.swift` is the only source; add new files by passing them to `swiftc`.
- **Screen Recording permission** required for capture. Install via `make install` to keep the TCC grant across rebuilds.
- **Version auto-increment** — `src/version.txt` is incremented every build. The current version is displayed in Preferences.

## Interaction protocol

At the end of each interaction, print the current version from `version.txt` so the user knows which build is running.
- **Version auto-increment** — `src/version.txt` is incremented every build. The current version is displayed in Preferences.

## Interaction protocol

At the end of each interaction, print the current version from `version.txt` so the user knows which build is running.