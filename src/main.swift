import AppKit
import SwiftUI
import Carbon

let hotkeyKeyCodeKey = "hotkeyKeyCode"
let hotkeyModifiersKey = "hotkeyModifiers"
let captureHistoryKey = "captureHistory"

var savedHotkeyKeyCode: UInt16 {
    get { UInt16(UserDefaults.standard.integer(forKey: hotkeyKeyCodeKey)) }
    set { UserDefaults.standard.set(Int(newValue), forKey: hotkeyKeyCodeKey) }
}

var savedHotkeyModifiers: UInt {
    get { UInt(bitPattern: UserDefaults.standard.integer(forKey: hotkeyModifiersKey)) }
    set { UserDefaults.standard.set(Int(bitPattern: newValue), forKey: hotkeyModifiersKey) }
}

func matchesHotkey(event: NSEvent) -> Bool {
    let keyCode = savedHotkeyKeyCode
    let modifiers = NSEvent.ModifierFlags(rawValue: savedHotkeyModifiers)
    return event.keyCode == keyCode && event.modifierFlags.contains(modifiers)
}

var gHotKeyRef: EventHotKeyRef?

func installCarbonEventHandler() {
    var handler: EventHandlerRef?
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
        var hotKeyID = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        if hotKeyID.signature == 0x444D {
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.captureSelection()
            }
        }
        return noErr
    } as EventHandlerUPP, 1, &spec, nil, &handler)
}

func registerCarbonHotkey() {
    if let ref = gHotKeyRef { UnregisterEventHotKey(ref); gHotKeyRef = nil }
    var mods: UInt32 = 0
    let flags = NSEvent.ModifierFlags(rawValue: savedHotkeyModifiers)
    if flags.contains(.command) { mods |= UInt32(cmdKey) }
    if flags.contains(.shift) { mods |= UInt32(shiftKey) }
    if flags.contains(.option) { mods |= UInt32(optionKey) }
    if flags.contains(.control) { mods |= UInt32(controlKey) }
    let id = EventHotKeyID(signature: 0x444D, id: 1)
    RegisterEventHotKey(UInt32(savedHotkeyKeyCode), mods, id, GetApplicationEventTarget(), 0, &gHotKeyRef)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var prefsWindowController: NSWindowController?

func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = makeIcon()

        if UserDefaults.standard.object(forKey: hotkeyKeyCodeKey) == nil {
            savedHotkeyKeyCode = 26
            savedHotkeyModifiers = NSEvent.ModifierFlags([.command, .shift]).rawValue
        }

        installCarbonEventHandler()
        registerCarbonHotkey()
        CaptureController.loadHistory()
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let captureItem = NSMenuItem(title: "Capture selection", action: #selector(captureSelection), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(.separator())

        if !CaptureController.history.isEmpty {
            for item in CaptureController.history.reversed() {
                let mi = NSMenuItem(title: item.label, action: #selector(openHistoryItem(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = item
                menu.addItem(mi)
            }
            menu.addItem(.separator())
        }

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: "")
        prefsItem.target = self
        menu.addItem(prefsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func openHistoryItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? CaptureHistoryItem else { return }
        CaptureController.shared.showHistoryItem(item)
    }

    @objc func captureSelection() {
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
        window.setContentSize(NSSize(width: 380, height: 320))
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

// MARK: - Capture History

final class CaptureHistoryItem {
    var image: NSImage
    let label: String
    let date: Date
    var filename: String = ""
    init(image: NSImage, label: String, date: Date = Date()) {
        self.image = image
        self.label = label
        self.date = date
    }
}

// MARK: - Capture Controller

final class CaptureController: NSObject {
    static let shared = CaptureController()
    static var history: [CaptureHistoryItem] = []

    private static var historyDir: URL = {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        let dir = pictures.appendingPathComponent("DotMenu/.history")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var metadataFile: URL { historyDir.appendingPathComponent("history.json") }

    static func loadHistory() {
        history.removeAll()
        guard let data = try? Data(contentsOf: metadataFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return }
        for entry in json {
            guard let label = entry["label"], let filename = entry["filename"] else { continue }
            let url = historyDir.appendingPathComponent(filename)
            guard let imgData = try? Data(contentsOf: url),
                  let image = NSImage(data: imgData)
            else { continue }
            let item = CaptureHistoryItem(image: image, label: label)
            item.filename = filename
            history.append(item)
        }
    }

    static func addToHistory(image: NSImage, label: String) {
        let item = CaptureHistoryItem(image: image, label: label)
        item.filename = "\(UUID().uuidString).png"
        let url = historyDir.appendingPathComponent(item.filename)
        if let data = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: data),
           let pngData = rep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: url)
        }
        history.append(item)
        if history.count > 10 {
            let removed = history.removeFirst()
            try? FileManager.default.removeItem(at: historyDir.appendingPathComponent(removed.filename))
        }
        rewriteMetadata()
        (NSApp.delegate as? AppDelegate)?.rebuildMenu()
    }

    static func updateLastHistory(image newImage: NSImage) {
        guard let item = history.last else { return }
        let url = historyDir.appendingPathComponent(item.filename)
        item.image = newImage
        if let data = newImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: data),
           let pngData = rep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: url)
        }
    }

    static var isClearing = false

    static func clearHistory() {
        isClearing = true
        for ctrl in shared.captureWindowControllers {
            ctrl.window?.close()
        }
        shared.captureWindowControllers.removeAll()
        history.removeAll()
        try? FileManager.default.removeItem(at: historyDir)
        try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
        isClearing = false
        (NSApp.delegate as? AppDelegate)?.rebuildMenu()
    }

    private static func rewriteMetadata() {
        var json: [[String: String]] = []
        for item in history {
            json.append(["label": item.label, "filename": item.filename])
        }
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            try? data.write(to: metadataFile)
        }
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    func showHistoryItem(_ item: CaptureHistoryItem) {
        let url = capturesDir.appendingPathComponent("history")
        let ctrl = CaptureWindowController(image: item.image, fileURL: url)
        ctrl.window?.center()
        captureWindowControllers.append(ctrl)
        ctrl.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

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

        let label = CaptureController.dateFormatter.string(from: Date())
        CaptureController.addToHistory(image: image, label: label)

        let controller = CaptureWindowController(image: image, fileURL: url)
        controller.window?.center()
        captureWindowControllers.append(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Shape model

struct Shape {
    enum Kind { case rect, circle, line }
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
        constrainAspectRatio(&s, event: event)
        inProgress = s
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard var s = inProgress else { return }
        s.end = convert(event.locationInWindow, from: nil)
        constrainAspectRatio(&s, event: event)
        shapes.append(s)
        inProgress = nil
        onShapeFinished?(s)
        needsDisplay = true
    }

    private func constrainAspectRatio(_ s: inout Shape, event: NSEvent) {
        guard s.kind != .line, event.modifierFlags.contains(.shift) else { return }
        let dx = s.end.x - s.start.x
        let dy = s.end.y - s.start.y
        let size = max(abs(dx), abs(dy))
        s.end.x = s.start.x + (dx >= 0 ? size : -size)
        s.end.y = s.start.y + (dy >= 0 ? size : -size)
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
        case .circle:
            let r = NSRect(
                x: min(s.start.x, s.end.x), y: min(s.start.y, s.end.y),
                width: abs(s.end.x - s.start.x), height: abs(s.end.y - s.start.y)
            )
            let path = NSBezierPath(ovalIn: r)
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
    private var circleItem: NSToolbarItem!
    private var lineItem: NSToolbarItem!
    private var undoItem: NSToolbarItem!
    private var colorItem: NSToolbarItem!
    private var fillItem: NSToolbarItem!
    private var widthItem: NSToolbarItem!
    private let widthPopUp: NSPopUpButton
    private var keyMonitor: Any?
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
        window.title = "Capture  \(Int(image.size.width))x\(Int(image.size.height))"
        window.contentView = container
        window.isReleasedWhenClosed = false

        colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 32, height: 24))
        colorWell.color = overlayView.shapeColor
        colorWell.isBordered = true

        let fillBtn = NSButton(checkboxWithTitle: "Fill", target: nil, action: nil)
        fillBtn.state = overlayView.shapeFill ? .on : .off

        let savedWidth = UserDefaults.standard.integer(forKey: "lineWidth")
        overlayView.shapeLineWidth = savedWidth > 0 ? CGFloat(savedWidth) : 3
        widthPopUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 56, height: 24), pullsDown: false)
        for w in [1, 2, 3, 4, 5, 6, 8, 10, 12, 16] {
            widthPopUp.addItem(withTitle: "\(w)")
        }
        widthPopUp.selectItem(withTitle: "\(Int(overlayView.shapeLineWidth))")
        widthPopUp.bezelStyle = .texturedRounded

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

        circleItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("circleItem"))
        circleItem.label = "Circle"
        circleItem.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Draw circle")
        circleItem.target = self
        circleItem.action = #selector(beginTool)
        circleItem.isEnabled = true

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

        widthPopUp.target = self
        widthPopUp.action = #selector(widthChanged)
        widthItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("widthItem"))
        widthItem.label = "Width"
        widthItem.view = widthPopUp

        let toolbar = NSToolbar(identifier: "CaptureToolbar")
        toolbar.delegate = self
        window.toolbar = toolbar

        window.delegate = self
        container.addSubview(toastLabel)
        toastLabel.frame.origin.x = (imageSize.width - 200) / 2

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            let cmd = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)
            guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return event }
            if cmd && !shift && chars == "c" { self.copyImage(); return nil }
            if cmd && !shift && chars == "s" { self.saveImage(); return nil }
            if matchesHotkey(event: event) { CaptureController.shared.beginCapture(); return nil }
            if !cmd && chars == "r" { self.beginTool(self.rectItem); return nil }
            if !cmd && chars == "c" { self.beginTool(self.circleItem); return nil }
            if !cmd && chars == "l" { self.beginTool(self.lineItem); return nil }
            if !cmd && event.keyCode == 36 { self.copyImage(); return nil }
            return event
        }

        NSApp.setActivationPolicy(.regular)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [copyItem.itemIdentifier, saveItem.itemIdentifier, saveAsItem.itemIdentifier, .flexibleSpace, rectItem.itemIdentifier, circleItem.itemIdentifier, lineItem.itemIdentifier, colorItem.itemIdentifier, fillItem.itemIdentifier, widthItem.itemIdentifier, undoItem.itemIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [copyItem.itemIdentifier, saveItem.itemIdentifier, saveAsItem.itemIdentifier, .flexibleSpace, rectItem.itemIdentifier, circleItem.itemIdentifier, lineItem.itemIdentifier, colorItem.itemIdentifier, fillItem.itemIdentifier, widthItem.itemIdentifier, undoItem.itemIdentifier]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == copyItem.itemIdentifier { return copyItem }
        if identifier == saveItem.itemIdentifier { return saveItem }
        if identifier == saveAsItem.itemIdentifier { return saveAsItem }
        if identifier == rectItem.itemIdentifier { return rectItem }
        if identifier == circleItem.itemIdentifier { return circleItem }
        if identifier == lineItem.itemIdentifier { return lineItem }
        if identifier == colorItem.itemIdentifier { return colorItem }
        if identifier == fillItem.itemIdentifier { return fillItem }
        if identifier == widthItem.itemIdentifier { return widthItem }
        if identifier == undoItem.itemIdentifier { return undoItem }
        return nil
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        NSColorPanel.shared.orderOut(nil)
        if !CaptureController.isClearing && !overlayView.shapes.isEmpty {
            let img = compositedImage()
            CaptureController.updateLastHistory(image: img)
        }
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

    @objc private func widthChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title, let w = Float(title) else { return }
        overlayView.shapeLineWidth = CGFloat(w)
        UserDefaults.standard.set(Int(w), forKey: "lineWidth")
    }

    @objc private func beginTool(_ sender: NSToolbarItem) {
        resetToolItemAppearance()
        if sender.itemIdentifier == rectItem.itemIdentifier {
            overlayView.activeTool = .rect
            activeToolItem = rectItem
            rectItem.image = NSImage(systemSymbolName: "rectangle.fill", accessibilityDescription: "Draw rectangle")
        } else if sender.itemIdentifier == circleItem.itemIdentifier {
            overlayView.activeTool = .circle
            activeToolItem = circleItem
            circleItem.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Draw circle")
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
            } else if item.itemIdentifier == circleItem.itemIdentifier {
                circleItem.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Draw circle")
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
            case .circle:
                let r = NSRect(
                    x: min(start.x, end.x), y: min(start.y, end.y),
                    width: abs(end.x - start.x), height: abs(end.y - start.y)
                )
                let path = NSBezierPath(ovalIn: r)
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
        NSSound(named: "Tink")?.play()
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
    @State private var historyCount = 0

    private var shortcutLabel: String {
        let mods = NSEvent.ModifierFlags(rawValue: savedHotkeyModifiers)
        var parts: [String] = []
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        if let source = CGEventSource(stateID: .combinedSessionState),
           let cgEvent = CGEvent(keyboardEventSource: source, virtualKey: savedHotkeyKeyCode, keyDown: true),
           let nsEvent = NSEvent(cgEvent: cgEvent) {
            let str = nsEvent.charactersIgnoringModifiers?.uppercased() ?? "?"
            parts.append(str)
        } else {
            parts.append("#\(savedHotkeyKeyCode)")
        }
        return parts.joined()
    }

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

                HStack {
                    Text("Capture shortcut:")
                    Text(shortcutLabel)
                        .foregroundColor(.secondary)
                }

                if historyCount > 0 {
                    Button("Clear History (\(historyCount))") {
                        CaptureController.clearHistory()
                        historyCount = 0
                    }
                }
            }
            .font(.body)
        }
        .padding()
        .frame(width: 380, height: 320)
        .onAppear { historyCount = CaptureController.history.count }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
