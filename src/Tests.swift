import AppKit
import Foundation

// Minimal assert-based self-check. Run with `make test`.
// Not compiled into the app: only the `make test` build passes -D DOTMENU_TESTS.

private var failures = 0
private var checks = 0

private func check(_ ok: Bool, _ what: String) {
    checks += 1
    if ok {
        print("ok   \(what)")
    } else {
        failures += 1
        print("FAIL \(what)")
    }
}

private func makeImage(width: Int, height: Int, _ color: (Int, Int) -> (UInt8, UInt8, UInt8)) -> NSImage {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: width * 4, bitsPerPixel: 32
    )!
    let pixels = rep.bitmapData!
    for y in 0..<height {
        for x in 0..<width {
            let (r, g, b) = color(x, y)
            let o = (y * width + x) * 4
            pixels[o] = r
            pixels[o + 1] = g
            pixels[o + 2] = b
            pixels[o + 3] = 255
        }
    }
    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(rep)
    return image
}

func runTests() -> Int32 {
    let cal = Calendar.current
    let now = Date()

    // MARK: display rect (the mirrored-selection bug)
    let mainHeight: CGFloat = 900
    let topSelection = displayRect(
        fromSelection: NSRect(x: 100, y: 700, width: 50, height: 100),
        windowOrigin: .zero, mainScreenHeight: mainHeight
    )
    check(topSelection == CGRect(x: 100, y: 100, width: 50, height: 100), "selection at screen top maps to display top")
    let full = displayRect(
        fromSelection: NSRect(x: 0, y: 0, width: 1440, height: mainHeight),
        windowOrigin: .zero, mainScreenHeight: mainHeight
    )
    check(full == CGRect(x: 0, y: 0, width: 1440, height: mainHeight), "full-screen selection keeps origin")
    let secondScreen = displayRect(
        fromSelection: NSRect(x: 0, y: 0, width: 100, height: 100),
        windowOrigin: NSPoint(x: 0, y: mainHeight), mainScreenHeight: mainHeight
    )
    check(secondScreen.origin.y == -100, "screen above main maps to negative Y")

    // MARK: history labels
    check(historyDateLabel(from: now).hasPrefix("Today"), "today")
    check(historyDateLabel(from: cal.date(byAdding: .day, value: -1, to: now)!).hasPrefix("Yesterday"), "yesterday")
    check(historyDateLabel(from: cal.date(byAdding: .day, value: -3, to: now)!) == "3 days ago", "3 days ago")
    check(historyDateLabel(from: cal.date(byAdding: .day, value: -8, to: now)!) == "1 week ago", "8 days = 1 week")
    check(historyDateLabel(from: cal.date(byAdding: .day, value: -21, to: now)!) == "3 weeks ago", "21 days = 3 weeks")
    check(historyDateLabel(from: cal.date(byAdding: .day, value: -100, to: now)!).contains("month"), "100 days = months")
    check(historyDateLabel(from: cal.date(byAdding: .day, value: -500, to: now)!).contains("year"), "500 days = years")
    check(!historyDateLabel(from: now, absolute: true).isEmpty, "absolute label is non-empty")

    // MARK: legacy label migration
    check(historyMigrateLabel("sel") == "Selection", "migrate sel")
    check(historyMigrateLabel("full") == "Screen", "migrate full")
    check(historyMigrateLabel("app") == "Window", "migrate app")
    check(historyMigrateLabel("Selection-2") == "Selection", "migrate Selection-2")
    check(historyMigrateLabel("Window") == "Window", "migrate keeps Window")
    check(historyMigrateLabel("Custom") == "Custom", "migrate keeps unknown label")

    // MARK: color helpers
    check(NSColor(hexString: "#12AB34")?.hexString == "#12AB34", "hex round trip")
    check(NSColor(hexString: "12ab34")?.hexString == "#12AB34", "hex accepts lowercase without #")
    check(NSColor(hexString: "#12AB3") == nil, "hex rejects wrong length")
    check(NSColor.black.luminance < 0.01 && NSColor.white.luminance > 0.99, "luminance extremes")

    // MARK: palette extraction on a uniform image
    let green = makeImage(width: 20, height: 20) { _, _ in (0, 255, 0) }
    let palette = PaletteExtractor.extract(from: green, count: 3)
    check(palette.count == 3, "palette returns requested count")
    check(palette.allSatisfy { $0.hexString == "#00FF00" }, "uniform image yields one color")

    print("\(checks - failures)/\(checks) checks passed")
    return failures == 0 ? 0 : 1
}
