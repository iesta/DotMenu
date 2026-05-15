import AppKit

// Generate app icon as .icns: a dashed square on a rounded-rect background.
let iconSize = CGSize(width: 1024, height: 1024)
let image = NSImage(size: iconSize)

image.lockFocus()

let bgPath = NSBezierPath(roundedRect: NSRect(origin: .zero, size: iconSize), xRadius: 180, yRadius: 180)
NSColor.controlAccentColor.setFill()
bgPath.fill()

let margin: CGFloat = 200
let rect = NSRect(x: margin, y: margin, width: iconSize.width - 2 * margin, height: iconSize.height - 2 * margin)
let path = NSBezierPath(rect: rect)
path.lineWidth = 24
let dashes: [CGFloat] = [40, 30]
path.setLineDash(dashes, count: 2, phase: 0)
NSColor.white.setStroke()
path.stroke()

image.unlockFocus()

// Write as .png first, then convert via iconutil
let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dotmenu-icon")
try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmpDir) }

let iconsetDir = tmpDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// Generate all needed sizes
let sizes: [(Int, String)] = [
    (16, "icon_16x16"),
    (32, "icon_16x16@2x"),
    (32, "icon_32x32"),
    (64, "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

for (size, name) in sizes {
    let resized = NSImage(size: NSSize(width: size, height: size))
    resized.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    resized.unlockFocus()

    guard let cgImage = resized.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    let fileURL = iconsetDir.appendingPathComponent("\(name).png")
    try rep.representation(using: .png, properties: [:])?.write(to: fileURL)
}

// Convert iconset to icns
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", "AppIcon.icns"]
try process.run()
process.waitUntilExit()

let outputPath = FileManager.default.currentDirectoryPath + "/DotMenu/AppIcon.icns"
try FileManager.default.moveItem(at: URL(fileURLWithPath: "AppIcon.icns"), to: URL(fileURLWithPath: outputPath))

print("✓ Created \(outputPath)")