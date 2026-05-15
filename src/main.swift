import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var prefsWindowController: NSWindowController?

func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = makeIcon()

        let menu = NSMenu()

        let captureItem = NSMenuItem(title: "Capture selection", action: #selector(captureSelection), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(.separator())

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: "")
        prefsItem.target = self
        menu.addItem(prefsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

@objc private func captureSelection() {
        if #available(macOS 14.0, *) {
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                return
            }
        }
        CaptureController.shared.beginCapture()
    }

    @objc private func showPreferences() {
        if let wc = prefsWindowController {
            wc.window?.orderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Preferences"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 380, height: 260))
        window.center()
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        prefsWindowController = controller
        window.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(x: 2, y: 2, width: 14, height: 14)
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2.0
        let dashes: [CGFloat] = [3.0, 2.5]
        path.setLineDash(dashes, count: 2, phase: 0)
        NSColor.labelColor.setStroke()
        path.stroke()
        image.unlockFocus()
        return image
    }
}

// MARK: - Capture Controller

final class CaptureController: NSObject {
    static let shared = CaptureController()

    private let capturesDir: URL = {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        return pictures.appendingPathComponent("DotMenu")
}()
    private var captureWindowControllers: [CaptureWindowController] = []

    func beginCapture() {
        runScreencapture()
    }

    private func runScreencapture() {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("dotmenu_\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", tempFile.path]

        try? process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let image = NSImage(contentsOf: tempFile)
        else { try? FileManager.default.removeItem(at: tempFile); return }

        try? FileManager.default.removeItem(at: tempFile)
        saveAndShow(image: image)
    }

    private func saveAndShow(image: NSImage) {
        try? FileManager.default.createDirectory(at: capturesDir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let url = capturesDir.appendingPathComponent("Capture_\(formatter.string(from: Date())).png")

        let controller = CaptureWindowController(image: image, fileURL: url)
        controller.window?.center()
        captureWindowControllers.append(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Shape model

struct Shape {
    enum Kind { case rect, line }
    let kind: Kind
    let start: NSPoint
    var end: NSPoint
    let color: NSColor
    let lineWidth: CGFloat
    let fill: Bool
}

// MARK: - Drawing Overlay View

final class DrawingOverlayView: NSView {
    var shapes: [Shape] = []
    var inProgress: Shape?
    var activeTool: Shape.Kind? {
        didSet {
            window?.invalidateCursorRects(for: self)
            if activeTool == nil { NSCursor.arrow.set() }
        }
    }
    var shapeColor: NSColor = .yellow
    var shapeFill: Bool = false
    var shapeLineWidth: CGFloat = 3.0
    var onShapeFinished: ((Shape) -> Void)?
    var onToolConsumed: (() -> Void)?

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        if activeTool != nil {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let tool = activeTool else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let s = Shape(kind: tool, start: pt, end: pt, color: shapeColor, lineWidth: shapeLineWidth, fill: shapeFill)
        inProgress = s
        activeTool = nil
        NSCursor.arrow.set()
        onToolConsumed?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard var s = inProgress else { return }
        s.end = convert(event.locationInWindow, from: nil)
        inProgress = s
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard var s = inProgress else { return }
        s.end = convert(event.locationInWindow, from: nil)
        shapes.append(s)
        inProgress = nil
        onShapeFinished?(s)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for s in shapes { drawShape(s) }
        if let s = inProgress { drawShape(s) }
    }

    private func drawShape(_ s: Shape) {
        s.color.setStroke()
        if s.fill { s.color.setFill() }
        switch s.kind {
        case .rect:
            let r = NSRect(
                x: min(s.start.x, s.end.x), y: min(s.start.y, s.end.y),
                width: abs(s.end.x - s.start.x), height: abs(s.end.y - s.start.y)
            )
            let path = NSBezierPath(rect: r)
            path.lineWidth = s.lineWidth
            if s.fill { path.fill() }
            path.stroke()
        case .line:
            let path = NSBezierPath()
            path.move(to: s.start)
            path.line(to: s.end)
            path.lineWidth = s.lineWidth
            path.stroke()
        }
    }
}

// MARK: - Capture Window Controller

final class CaptureWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    private let image: NSImage
    private let fileURL: URL
    private let toastLabel: NSTextField
    private let overlayView: DrawingOverlayView
    private var copyItem: NSToolbarItem!
    private var saveItem: NSToolbarItem!
    private var saveAsItem: NSToolbarItem!
    private var rectItem: NSToolbarItem!
    private var lineItem: NSToolbarItem!
    private var undoItem: NSToolbarItem!
    private var colorItem: NSToolbarItem!
    private var fillItem: NSToolbarItem!
    private let colorWell: NSColorWell
    private weak var activeToolItem: NSToolbarItem?

    init(image: NSImage, fileURL: URL) {
        self.image = image
        self.fileURL = fileURL

        let maxSize = NSSize(width: 800, height: 600)
        let imageSize = NSSize(
            width: min(image.size.width, maxSize.width),
            height: min(image.size.height, maxSize.height)
        )

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = NSRect(origin: .zero, size: imageSize)
        imageView.autoresizingMask = [.width, .height]

        overlayView = DrawingOverlayView(frame: NSRect(origin: .zero, size: imageSize))
        overlayView.autoresizingMask = [.width, .height]
        if let data = UserDefaults.standard.data(forKey: "drawingColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            overlayView.shapeColor = color
        }
        overlayView.shapeFill = UserDefaults.standard.bool(forKey: "drawingFill")

        let container = NSView(frame: NSRect(origin: .zero, size: imageSize))
        container.addSubview(imageView)
        container.addSubview(overlayView)

        toastLabel = NSTextField(labelWithString: "")
        toastLabel.alignment = .center
        toastLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        toastLabel.textColor = .white
        toastLabel.backgroundColor = NSColor(white: 0, alpha: 0.7)
        toastLabel.isBezeled = false
        toastLabel.isEditable = false
        toastLabel.isHidden = true
        toastLabel.wantsLayer = true
        toastLabel.layer?.cornerRadius = 6
        toastLabel.frame = NSRect(x: 0, y: 12, width: 200, height: 28)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: imageSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Capture"
        window.contentView = container
        window.isReleasedWhenClosed = false

        colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 32, height: 24))
        colorWell.color = overlayView.shapeColor
        colorWell.isBordered = true

        let fillBtn = NSButton(checkboxWithTitle: "Fill", target: nil, action: nil)
        fillBtn.state = overlayView.shapeFill ? .on : .off

        super.init(window: window)

        overlayView.onShapeFinished = { [weak self] _ in
            self?.undoItem.isEnabled = true
            self?.resetToolItemAppearance()
        }

        copyItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("copyItem"))
        copyItem.label = "Copy"
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        copyItem.target = self
        copyItem.action = #selector(copyImage)
        copyItem.isEnabled = true

        saveItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("saveItem"))
        saveItem.label = "Save"
        saveItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
        saveItem.target = self
        saveItem.action = #selector(saveImage)
        saveItem.isEnabled = true

        saveAsItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("saveAsItem"))
        saveAsItem.label = "Save As…"
        saveAsItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Save As")
        saveAsItem.target = self
        saveAsItem.action = #selector(saveAsImage)
        saveAsItem.isEnabled = true

        rectItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("rectItem"))
        rectItem.label = "Rectangle"
        rectItem.image = NSImage(systemSymbolName: "rectangle", accessibilityDescription: "Draw rectangle")
        rectItem.target = self
        rectItem.action = #selector(beginTool)
        rectItem.isEnabled = true

        lineItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("lineItem"))
        lineItem.label = "Line"
        lineItem.image = NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "Draw line")
        lineItem.target = self
        lineItem.action = #selector(beginTool)
        lineItem.isEnabled = true

        undoItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("undoItem"))
        undoItem.label = "Undo"
        undoItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")
        undoItem.target = self
        undoItem.action = #selector(undoShape)
        undoItem.isEnabled = false

        colorWell.target = self
        colorWell.action = #selector(colorChanged)

        colorItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("colorItem"))
        colorItem.label = "Color"
        colorItem.view = colorWell

        fillBtn.target = self
        fillBtn.action = #selector(fillChanged)
        fillItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("fillItem"))
        fillItem.view = fillBtn

        let toolbar = NSToolbar(identifier: "CaptureToolbar")
        toolbar.delegate = self
        window.toolbar = toolbar

        window.delegate = self
        container.addSubview(toastLabel)
        toastLabel.frame.origin.x = (imageSize.width - 200) / 2

        NSApp.setActivationPolicy(.regular)
    }

    required init?(coder: NSCoder) { nil }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [copyItem.itemIdentifier, saveItem.itemIdentifier, saveAsItem.itemIdentifier, .flexibleSpace, rectItem.itemIdentifier, lineItem.itemIdentifier, colorItem.itemIdentifier, fillItem.itemIdentifier, undoItem.itemIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [copyItem.itemIdentifier, saveItem.itemIdentifier, saveAsItem.itemIdentifier, .flexibleSpace, rectItem.itemIdentifier, lineItem.itemIdentifier, colorItem.itemIdentifier, fillItem.itemIdentifier, undoItem.itemIdentifier]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == copyItem.itemIdentifier { return copyItem }
        if identifier == saveItem.itemIdentifier { return saveItem }
        if identifier == saveAsItem.itemIdentifier { return saveAsItem }
        if identifier == rectItem.itemIdentifier { return rectItem }
        if identifier == lineItem.itemIdentifier { return lineItem }
        if identifier == colorItem.itemIdentifier { return colorItem }
        if identifier == fillItem.itemIdentifier { return fillItem }
        if identifier == undoItem.itemIdentifier { return undoItem }
        return nil
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        NSColorPanel.shared.orderOut(nil)
        let hasOtherWindows = NSApp.windows.contains { w in
            w != window && w.isVisible
        }
        if !hasOtherWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        overlayView.shapeColor = sender.color
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: sender.color, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "drawingColor")
        }
    }

    @objc private func fillChanged(_ sender: NSButton) {
        overlayView.shapeFill = sender.state == .on
        UserDefaults.standard.set(overlayView.shapeFill, forKey: "drawingFill")
    }

    @objc private func beginTool(_ sender: NSToolbarItem) {
        resetToolItemAppearance()
        if sender.itemIdentifier == rectItem.itemIdentifier {
            overlayView.activeTool = .rect
            activeToolItem = rectItem
            rectItem.image = NSImage(systemSymbolName: "rectangle.fill", accessibilityDescription: "Draw rectangle")
        } else if sender.itemIdentifier == lineItem.itemIdentifier {
            overlayView.activeTool = .line
            activeToolItem = lineItem
            lineItem.image = NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: "Draw line")
        }
    }

    private func resetToolItemAppearance() {
        if let item = activeToolItem {
            if item.itemIdentifier == rectItem.itemIdentifier {
                rectItem.image = NSImage(systemSymbolName: "rectangle", accessibilityDescription: "Draw rectangle")
            } else if item.itemIdentifier == lineItem.itemIdentifier {
                lineItem.image = NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "Draw line")
            }
        }
        activeToolItem = nil
    }

    @objc private func undoShape() {
        guard !overlayView.shapes.isEmpty else { return }
        overlayView.shapes.removeLast()
        overlayView.needsDisplay = true
        undoItem.isEnabled = !overlayView.shapes.isEmpty
    }

    private func compositedImage() -> NSImage {
        let fullSize = image.size
        let containerSize = overlayView.bounds.size
        let img = NSImage(size: fullSize)
        img.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: fullSize))

        let imageAspect = fullSize.width / fullSize.height
        let containerAspect = containerSize.width / containerSize.height
        var imageRect: NSRect
        if imageAspect > containerAspect {
            let h = containerSize.width / imageAspect
            imageRect = NSRect(x: 0, y: (containerSize.height - h) / 2, width: containerSize.width, height: h)
        } else {
            let w = containerSize.height * imageAspect
            imageRect = NSRect(x: (containerSize.width - w) / 2, y: 0, width: w, height: containerSize.height)
        }

        let sx = fullSize.width / imageRect.width
        let sy = fullSize.height / imageRect.height

        for s in overlayView.shapes {
            let map: (NSPoint) -> NSPoint = { pt in
                let nx = (pt.x - imageRect.origin.x) * sx
                let ny = (imageRect.height - (pt.y - imageRect.origin.y)) * sy
                return NSPoint(x: nx, y: ny)
            }
            let start = map(s.start)
            let end = map(s.end)
            s.color.setStroke()
            if s.fill { s.color.setFill() }
            switch s.kind {
            case .rect:
                let r = NSRect(
                    x: min(start.x, end.x), y: min(start.y, end.y),
                    width: abs(end.x - start.x), height: abs(end.y - start.y)
                )
                let path = NSBezierPath(rect: r)
                path.lineWidth = s.lineWidth * sx
                if s.fill { path.fill() }
                path.stroke()
            case .line:
                let path = NSBezierPath()
                path.move(to: start)
                path.line(to: end)
                path.lineWidth = s.lineWidth * sx
                path.stroke()
            }
        }
        img.unlockFocus()
        return img
    }

    private func savePNG(_ img: NSImage, to url: URL) throws {
        if let data = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: data),
           let pngData = rep.representation(using: .png, properties: [:]) {
            try pngData.write(to: url)
        }
    }

    @objc private func copyImage() {
        let img = compositedImage()
        let pb = NSPasteboard.general
        pb.clearContents()
        if let data = img.tiffRepresentation {
            let item = NSPasteboardItem()
            item.setData(data, forType: .tiff)
            pb.writeObjects([item])
        }
        showToast("Copied to pasteboard")
    }

    @objc private func saveImage() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try savePNG(compositedImage(), to: fileURL)
        } catch {}
        showToast("Saved to ~/Pictures/DotMenu")
    }

    @objc private func saveAsImage() {
        let panel = NSSavePanel()
        panel.title = "Save capture as"
        panel.nameFieldStringValue = fileURL.lastPathComponent
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try savePNG(compositedImage(), to: url)
        } catch {}
        showToast("Saved")
    }

    private func showToast(_ message: String) {
        toastLabel.stringValue = message
        toastLabel.isHidden = false
        toastLabel.alphaValue = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.toastLabel.isHidden = true
        }
    }
}

// MARK: - Preferences

struct PreferencesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.dashed")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("DotMenu")
                .font(.title2.bold())

            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()
                .frame(width: 200)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Capture folder:")
                    Text("~/Pictures/DotMenu")
                        .foregroundColor(.secondary)
                }
            }
            .font(.body)
        }
        .padding()
        .frame(width: 380, height: 260)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
