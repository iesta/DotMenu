import AppKit
import SwiftUI
import Carbon

let hotkeyKeyCodeKey = "hotkeyKeyCode"
let hotkeyModifiersKey = "hotkeyModifiers"
let fullHotkeyKeyCodeKey = "fullHotkeyKeyCode"
let fullHotkeyModifiersKey = "fullHotkeyModifiers"
let winHotkeyKeyCodeKey = "winHotkeyKeyCode"
let winHotkeyModifiersKey = "winHotkeyModifiers"
let captureHistoryKey = "captureHistory"

var savedHotkeyKeyCode: UInt16 {
    get { UInt16(UserDefaults.standard.integer(forKey: hotkeyKeyCodeKey)) }
    set { UserDefaults.standard.set(Int(newValue), forKey: hotkeyKeyCodeKey) }
}
var savedHotkeyModifiers: UInt {
    get { UInt(bitPattern: UserDefaults.standard.integer(forKey: hotkeyModifiersKey)) }
    set { UserDefaults.standard.set(Int(bitPattern: newValue), forKey: hotkeyModifiersKey) }
}
var savedFullHotkeyKeyCode: UInt16 {
    get { UInt16(UserDefaults.standard.integer(forKey: fullHotkeyKeyCodeKey)) }
    set { UserDefaults.standard.set(Int(newValue), forKey: fullHotkeyKeyCodeKey) }
}
var savedFullHotkeyModifiers: UInt {
    get { UInt(bitPattern: UserDefaults.standard.integer(forKey: fullHotkeyModifiersKey)) }
    set { UserDefaults.standard.set(Int(bitPattern: newValue), forKey: fullHotkeyModifiersKey) }
}
var savedWinHotkeyKeyCode: UInt16 {
    get { UInt16(UserDefaults.standard.integer(forKey: winHotkeyKeyCodeKey)) }
    set { UserDefaults.standard.set(Int(newValue), forKey: winHotkeyKeyCodeKey) }
}
var savedWinHotkeyModifiers: UInt {
    get { UInt(bitPattern: UserDefaults.standard.integer(forKey: winHotkeyModifiersKey)) }
    set { UserDefaults.standard.set(Int(bitPattern: newValue), forKey: winHotkeyModifiersKey) }
}

func matchesHotkey(event: NSEvent, keyCode: UInt16, modifiers: UInt) -> Bool {
    let m = NSEvent.ModifierFlags(rawValue: modifiers)
    return event.keyCode == keyCode && event.modifierFlags.contains(m)
}

var gHotKeyRef1: EventHotKeyRef?
var gHotKeyRef2: EventHotKeyRef?
var gHotKeyRef3: EventHotKeyRef?

func installCarbonEventHandler() {
    var handler: EventHandlerRef?
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
        var hotKeyID = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        guard hotKeyID.signature == 0x444D else { return noErr }
        DispatchQueue.main.async {
            let del = NSApp.delegate as? AppDelegate
            switch hotKeyID.id {
            case 1: del?.captureSelection()
            case 2: del?.captureFullScreen()
            case 3: del?.captureWindow()
            default: break
            }
        }
        return noErr
    } as EventHandlerUPP, 1, &spec, nil, &handler)
}

private func registerOneHotkey(keyCode: UInt16, rawModifiers: UInt, id: UInt32, ref: inout EventHotKeyRef?) {
    if let r = ref { UnregisterEventHotKey(r); ref = nil }
    var mods: UInt32 = 0
    let flags = NSEvent.ModifierFlags(rawValue: rawModifiers)
    if flags.contains(.command) { mods |= UInt32(cmdKey) }
    if flags.contains(.shift) { mods |= UInt32(shiftKey) }
    if flags.contains(.option) { mods |= UInt32(optionKey) }
    if flags.contains(.control) { mods |= UInt32(controlKey) }
    let hotKeyID = EventHotKeyID(signature: 0x444D, id: id)
    RegisterEventHotKey(UInt32(keyCode), mods, hotKeyID, GetApplicationEventTarget(), 0, &ref)
}

func registerCarbonHotkeys() {
    registerOneHotkey(keyCode: savedHotkeyKeyCode, rawModifiers: savedHotkeyModifiers, id: 1, ref: &gHotKeyRef1)
    registerOneHotkey(keyCode: savedFullHotkeyKeyCode, rawModifiers: savedFullHotkeyModifiers, id: 2, ref: &gHotKeyRef2)
    registerOneHotkey(keyCode: savedWinHotkeyKeyCode, rawModifiers: savedWinHotkeyModifiers, id: 3, ref: &gHotKeyRef3)
}

private func menuThumbnail(from image: NSImage, maxDimension: CGFloat) -> NSImage? {
    let thumbSize = NSSize(width: maxDimension, height: maxDimension)
    let thumb = NSImage(size: thumbSize)
    thumb.lockFocus()
    let imageSize = image.size
    let aspect = imageSize.width / imageSize.height
    let drawRect: NSRect
    if aspect >= 1 {
        let h = maxDimension / aspect
        drawRect = NSRect(x: 0, y: (maxDimension - h) / 2, width: maxDimension, height: h)
    } else {
        let w = maxDimension * aspect
        drawRect = NSRect(x: (maxDimension - w) / 2, y: 0, width: w, height: maxDimension)
    }
    image.draw(in: drawRect, from: NSRect(origin: .zero, size: imageSize), operation: .copy, fraction: 1.0)
    thumb.unlockFocus()
    return thumb
}

private let historyTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

private let historyAbsoluteFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .short
    f.locale = .current
    return f
}()

func historyDateLabel(from date: Date, absolute: Bool = false) -> String {
    if absolute {
        return historyAbsoluteFormatter.string(from: date)
    }
    let cal = Calendar.current
    let now = Date()
    if cal.isDateInToday(date) {
        return "Today \(historyTimeFormatter.string(from: date))"
    }
    if cal.isDateInYesterday(date) {
        return "Yesterday \(historyTimeFormatter.string(from: date))"
    }
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
    if days <= 7 {
        return "\(days) days ago"
    }
    if days <= 30 {
        let weeks = days / 7
        return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
    }
    let months = cal.dateComponents([.month], from: date, to: now).month ?? 0
    if months <= 12 {
        return months == 1 ? "1 month ago" : "\(months) months ago"
    }
    let years = cal.dateComponents([.year], from: date, to: now).year ?? 0
    return years == 1 ? "1 year ago" : "\(years) years ago"
}

func historyMigrateLabel(_ label: String) -> String {
    let map: [String: String] = [
        "sel": "Selection",
        "full": "Screen",
        "win": "Window",
        "app": "Window"
    ]
    let lower = label.lowercased()
    if let mapped = map[lower] { return mapped }
    let prefixes = ["Selection", "Screen", "Window", "App"]
    for prefix in prefixes {
        if label == prefix { return prefix == "App" ? "Window" : prefix }
        if label.hasPrefix(prefix + "-") {
            return prefix == "App" ? "Window" : prefix
        }
    }
    return label
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
        if UserDefaults.standard.object(forKey: fullHotkeyKeyCodeKey) == nil {
            savedFullHotkeyKeyCode = 28
            savedFullHotkeyModifiers = NSEvent.ModifierFlags([.command, .shift]).rawValue
        }
        if UserDefaults.standard.object(forKey: winHotkeyKeyCodeKey) == nil {
            savedWinHotkeyKeyCode = 25
            savedWinHotkeyModifiers = NSEvent.ModifierFlags([.command, .shift]).rawValue
        }

        installCarbonEventHandler()
        registerCarbonHotkeys()
        CaptureController.loadHistory()
        rebuildMenu()
        setupMainMenu()
    }

    private func setupMainMenu() {
        let main = NSMenu()

        let file = NSMenu(title: "File")
        let newCapture = NSMenuItem(title: "New Capture", action: #selector(captureSelection), keyEquivalent: "n")
        newCapture.target = self
        file.addItem(newCapture)
        file.addItem(.separator())
        let close = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(close)
        let closeAll = NSMenuItem(title: "Close All", action: #selector(closeAllWindows), keyEquivalent: "W")
        closeAll.keyEquivalentModifierMask = [.command, .shift]
        closeAll.target = self
        file.addItem(closeAll)
        file.addItem(.separator())
        let save = NSMenuItem(title: "Save", action: #selector(CaptureWindowController.saveImage), keyEquivalent: "s")
        file.addItem(save)
        let saveAs = NSMenuItem(title: "Save As…", action: #selector(CaptureWindowController.saveAsImage), keyEquivalent: "")
        file.addItem(saveAs)
        file.addItem(.separator())
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        prefs.target = self
        file.addItem(prefs)

        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileItem.submenu = file
        main.addItem(fileItem)

        let edit = NSMenu(title: "Edit")
        let undo = NSMenuItem(title: "Undo", action: #selector(CaptureWindowController.undoShape), keyEquivalent: "z")
        edit.addItem(undo)
        edit.addItem(.separator())
        let copy = NSMenuItem(title: "Copy", action: #selector(CaptureWindowController.copyImage), keyEquivalent: "c")
        edit.addItem(copy)

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }
        let captureActions: [Selector] = [
            #selector(CaptureWindowController.copyImage),
            #selector(CaptureWindowController.saveImage),
            #selector(CaptureWindowController.saveAsImage),
            #selector(CaptureWindowController.undoShape),
        ]
        if captureActions.contains(action) {
            return CaptureController.shared.captureWindowControllers.contains { $0.window?.isKeyWindow == true }
        }
        return true
    }

    private func keyEq(for keyCode: UInt16) -> String {
        if let source = CGEventSource(stateID: .combinedSessionState),
           let cgEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            cgEvent.flags = []
            if let nsEvent = NSEvent(cgEvent: cgEvent) {
                return nsEvent.characters?.lowercased() ?? ""
            }
        }
        return ""
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let captureItem = NSMenuItem(title: "Capture selection", action: #selector(captureSelection), keyEquivalent: keyEq(for: savedHotkeyKeyCode))
        captureItem.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: savedHotkeyModifiers)
        captureItem.target = self
        menu.addItem(captureItem)
        let fullItem = NSMenuItem(title: "Capture full screen", action: #selector(captureFullScreen), keyEquivalent: keyEq(for: savedFullHotkeyKeyCode))
        fullItem.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: savedFullHotkeyModifiers)
        fullItem.target = self
        menu.addItem(fullItem)
        let winItem = NSMenuItem(title: "Capture window", action: #selector(captureWindow), keyEquivalent: keyEq(for: savedWinHotkeyKeyCode))
        winItem.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: savedWinHotkeyModifiers)
        winItem.target = self
        menu.addItem(winItem)
        menu.addItem(.separator())

        if !CaptureController.history.isEmpty {
            for item in CaptureController.history.reversed() {
                let baseTitle = "\(item.label) • \(historyDateLabel(from: item.date))"
                let mi = NSMenuItem(title: baseTitle, action: #selector(openHistoryItem(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = item
                mi.image = menuThumbnail(from: item.image, maxDimension: 36)
                menu.addItem(mi)

                let altTitle = "\(item.label) • \(historyDateLabel(from: item.date, absolute: true))"
                let altMi = NSMenuItem(title: altTitle, action: #selector(openHistoryItem(_:)), keyEquivalent: "")
                altMi.target = self
                altMi.representedObject = item
                altMi.image = menuThumbnail(from: item.image, maxDimension: 36)
                altMi.isAlternate = true
                altMi.keyEquivalentModifierMask = .option
                menu.addItem(altMi)
            }
            menu.addItem(.separator())
            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistoryFromMenu), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: "")
        prefsItem.target = self
        menu.addItem(prefsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func clearHistoryFromMenu() {
        CaptureController.clearHistory()
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
        statusItem.button?.contentTintColor = .systemBlue
        CaptureController.shared.onCaptureStateChange = { [weak self] highlighted in
            self?.statusItem.button?.contentTintColor = highlighted ? .systemBlue : nil
        }
        CaptureController.shared.beginCapture()
    }

    @objc func captureFullScreen() {
        if #available(macOS 14.0, *) {
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                return
            }
        }
        statusItem.button?.contentTintColor = .systemBlue
        CaptureController.shared.onCaptureStateChange = { [weak self] highlighted in
            self?.statusItem.button?.contentTintColor = highlighted ? .systemBlue : nil
        }
        CaptureController.shared.beginFullScreenCapture()
    }

    @objc func captureWindow() {
        if #available(macOS 14.0, *) {
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                return
            }
        }
        statusItem.button?.contentTintColor = .systemBlue
        CaptureController.shared.onCaptureStateChange = { [weak self] highlighted in
            self?.statusItem.button?.contentTintColor = highlighted ? .systemBlue : nil
        }
        CaptureController.shared.beginWindowCapture()
    }

    @objc func closeAllWindows() {
        for ctrl in CaptureController.shared.captureWindowControllers {
            ctrl.window?.close()
        }
    }

    @objc func showPreferences() {
        if let wc = prefsWindowController {
            wc.window?.makeKeyAndOrderFront(nil)
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
        window.makeKeyAndOrderFront(nil)
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }
        let iso = ISO8601DateFormatter()
        for entry in json {
            guard let label = entry["label"] as? String, let filename = entry["filename"] as? String else { continue }
            let url = historyDir.appendingPathComponent(filename)
            guard let imgData = try? Data(contentsOf: url),
                  let image = NSImage(data: imgData)
            else { continue }
            var date = Date()
            if let dateStr = entry["date"] as? String, let d = iso.date(from: dateStr) {
                date = d
            } else if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let mtime = attrs[.modificationDate] as? Date {
                date = mtime
            }
            let cleanLabel = historyMigrateLabel(label)
            let item = CaptureHistoryItem(image: image, label: cleanLabel, date: date)
            item.filename = filename
            history.append(item)
        }
    }

    @discardableResult
    static func addToHistory(image: NSImage, label: String, filename: String) -> CaptureHistoryItem {
        let item = CaptureHistoryItem(image: image, label: label)
        item.filename = filename
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
        return item
    }

    static func update(_ item: CaptureHistoryItem, image newImage: NSImage) {
        item.image = newImage
        if let data = newImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: data),
           let pngData = rep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: historyDir.appendingPathComponent(item.filename))
            let saved = shared.capturesDir.appendingPathComponent(item.filename)
            if FileManager.default.fileExists(atPath: saved.path) {
                try? pngData.write(to: saved)
            }
        }
        (NSApp.delegate as? AppDelegate)?.rebuildMenu()
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
        var json: [[String: Any]] = []
        for item in history {
            json.append([
                "label": item.label,
                "filename": item.filename,
                "date": ISO8601DateFormatter().string(from: item.date)
            ])
        }
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            try? data.write(to: metadataFile)
        }
    }

    func showHistoryItem(_ item: CaptureHistoryItem) {
        let url = capturesDir.appendingPathComponent(item.filename)
        let ctrl = CaptureWindowController(image: item.image, fileURL: url)
        ctrl.historyItem = item
        ctrl.window?.center()
        captureWindowControllers.append(ctrl)
        ctrl.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    let capturesDir: URL = {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        return pictures.appendingPathComponent("DotMenu")
}()
    var captureWindowControllers: [CaptureWindowController] = []
    var onCaptureStateChange: ((Bool) -> Void)?
    private var currentPrefix = ""
    private var currentLabel = ""

    func beginCapture() {
        currentPrefix = "sel"
        currentLabel = "Selection"
        SelectionCaptureController.shared.start { [weak self] image in
            guard let self = self else { return }
            if let image = image {
                self.saveAndShow(image: image)
            } else {
                self.onCaptureStateChange?(false)
            }
        }
    }

    func beginFullScreenCapture() {
        currentPrefix = "full"
        currentLabel = "Screen"
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("dotmenu_\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = [tempFile.path]

        process.terminationHandler = { [weak self] p in
            guard p.terminationStatus == 0,
                  let image = NSImage(contentsOf: tempFile)
            else {
                try? FileManager.default.removeItem(at: tempFile)
                DispatchQueue.main.async { self?.onCaptureStateChange?(false) }
                return
            }
            try? FileManager.default.removeItem(at: tempFile)
            DispatchQueue.main.async { self?.saveAndShow(image: image) }
        }
        do {
            try process.run()
        } catch {
            onCaptureStateChange?(false)
        }
    }

    func beginWindowCapture() {
        currentPrefix = "win"
        currentLabel = "Window"
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("dotmenu_\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-W", tempFile.path]

        process.terminationHandler = { [weak self] p in
            guard p.terminationStatus == 0,
                  let image = NSImage(contentsOf: tempFile)
            else {
                try? FileManager.default.removeItem(at: tempFile)
                DispatchQueue.main.async { self?.onCaptureStateChange?(false) }
                return
            }
            try? FileManager.default.removeItem(at: tempFile)
            DispatchQueue.main.async { self?.saveAndShow(image: image) }
        }
        do {
            try process.run()
        } catch {
            onCaptureStateChange?(false)
        }
    }

    private func saveAndShow(image: NSImage) {
        onCaptureStateChange?(false)
        try? FileManager.default.createDirectory(at: capturesDir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let prefix = currentPrefix
        let label = currentLabel
        let filename = "\(prefix)-Capture_\(timestamp).png"
        let url = capturesDir.appendingPathComponent(filename)

        CaptureController.addToHistory(image: image, label: label, filename: filename)

        let controller = CaptureWindowController(image: image, fileURL: url)
        controller.historyItem = CaptureController.history.last
        controller.window?.center()
        captureWindowControllers.append(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Selection Capture (custom overlay, Shift-safe)

/// Converts a selection in overlay-window coordinates to the global display-space
/// rectangle `CGDisplayCreateImage` expects (Y grows down from the main screen's top).
func displayRect(fromSelection rect: NSRect, windowOrigin: NSPoint, mainScreenHeight: CGFloat) -> CGRect {
    let global = NSRect(
        x: rect.origin.x + windowOrigin.x,
        y: rect.origin.y + windowOrigin.y,
        width: rect.width,
        height: rect.height
    )
    return CGRect(x: global.origin.x, y: mainScreenHeight - global.maxY, width: global.width, height: global.height)
}

final class SelectionCaptureController: NSObject {
    static let shared = SelectionCaptureController()
    private var window: NSWindow?
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var onComplete: ((NSImage?) -> Void)?

    func start(onComplete: @escaping (NSImage?) -> Void) {
        self.onComplete = onComplete
        guard let screen = NSScreen.main else {
            onComplete(nil)
            return
        }
        let frame = screen.frame
        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.acceptsMouseMovedEvents = true
        let view = SelectionCaptureView(frame: frame)
        view.controller = self
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        window = win
        NSCursor.hide()
    }

    fileprivate func setStart(_ p: NSPoint) {
        startPoint = p
        currentPoint = p
        window?.contentView?.needsDisplay = true
    }

    fileprivate func updateCurrent(_ p: NSPoint) {
        updateDrag(p, constrainSquare: false)
    }

    fileprivate func updateDrag(_ p: NSPoint, constrainSquare: Bool) {
        if constrainSquare, let start = startPoint {
            let dx = abs(p.x - start.x)
            let dy = abs(p.y - start.y)
            let size = max(dx, dy)
            let signX: CGFloat = p.x >= start.x ? 1 : -1
            let signY: CGFloat = p.y >= start.y ? 1 : -1
            currentPoint = NSPoint(x: start.x + signX * size, y: start.y + signY * size)
        } else {
            currentPoint = p
        }
        window?.contentView?.needsDisplay = true
    }

    fileprivate func currentRect() -> NSRect? {
        guard let start = startPoint, let end = currentPoint else { return nil }
        return NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    fileprivate func cancel() {
        finish(with: nil)
    }

    fileprivate func performCapture() {
        guard let rect = currentRect() else {
            finish(with: nil)
            return
        }
        if rect.width < 5 || rect.height < 5 {
            finish(with: nil)
            return
        }
        guard let screen = window?.screen ?? NSScreen.main else {
            finish(with: nil)
            return
        }
        // rect is in window coordinates; the overlay window sits at the screen's origin.
        let windowOrigin = window?.frame.origin ?? .zero
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let cgRect = displayRect(fromSelection: rect, windowOrigin: windowOrigin, mainScreenHeight: mainHeight)
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            ?? CGMainDisplayID()
        guard let cgImage = CGDisplayCreateImage(displayID, rect: cgRect) else {
            finish(with: nil)
            return
        }
        let image = NSImage(cgImage: cgImage, size: rect.size)
        finish(with: image)
    }

    private func finish(with image: NSImage?) {
        NSCursor.unhide()
        window?.orderOut(nil)
        window = nil
        startPoint = nil
        currentPoint = nil
        let cb = onComplete
        onComplete = nil
        cb?(image)
    }
}

final class SelectionCaptureView: NSView {
    weak var controller: SelectionCaptureController?
    private var currentMouseLocation: NSPoint = .zero

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            controller?.cancel()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        currentMouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        currentMouseLocation = p
        controller?.setStart(p)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        currentMouseLocation = p
        let constrain = event.modifierFlags.contains(.shift)
        controller?.updateDrag(p, constrainSquare: constrain)
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        currentMouseLocation = p
        let constrain = event.modifierFlags.contains(.shift)
        controller?.updateDrag(p, constrainSquare: constrain)
        controller?.performCapture()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        drawCrosshair(at: currentMouseLocation)
        guard let rect = controller?.currentRect(), rect.width > 1, rect.height > 1 else { return }
        NSColor.clear.setFill()
        rect.fill(using: .clear)
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        NSColor.white.setStroke()
        path.setLineDash([4, 4], count: 2, phase: 0)
        path.stroke()
        let dimText = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        ]
        let textSize = (dimText as NSString).size(withAttributes: attrs)
        var textOrigin = NSPoint(x: rect.origin.x + 4, y: rect.origin.y - textSize.height - 4)
        if textOrigin.y < 0 {
            textOrigin.y = rect.origin.y + 4
        }
        if textOrigin.x + textSize.width > bounds.width {
            textOrigin.x = bounds.width - textSize.width - 4
        }
        (dimText as NSString).draw(at: textOrigin, withAttributes: attrs)
    }

    private func drawCrosshair(at point: NSPoint) {
        let arm: CGFloat = 16
        let gap: CGFloat = 5
        let thickness: CGFloat = 1
        let outline = NSBezierPath()
        outline.lineWidth = thickness + 2
        outline.lineCapStyle = .butt
        outline.move(to: NSPoint(x: point.x - arm, y: point.y))
        outline.line(to: NSPoint(x: point.x - gap, y: point.y))
        outline.move(to: NSPoint(x: point.x + gap, y: point.y))
        outline.line(to: NSPoint(x: point.x + arm, y: point.y))
        outline.move(to: NSPoint(x: point.x, y: point.y - arm))
        outline.line(to: NSPoint(x: point.x, y: point.y - gap))
        outline.move(to: NSPoint(x: point.x, y: point.y + gap))
        outline.line(to: NSPoint(x: point.x, y: point.y + arm))
        NSColor.black.setStroke()
        outline.stroke()
        let inner = NSBezierPath()
        inner.lineWidth = thickness
        inner.lineCapStyle = .butt
        inner.move(to: NSPoint(x: point.x - arm, y: point.y))
        inner.line(to: NSPoint(x: point.x - gap, y: point.y))
        inner.move(to: NSPoint(x: point.x + gap, y: point.y))
        inner.line(to: NSPoint(x: point.x + arm, y: point.y))
        inner.move(to: NSPoint(x: point.x, y: point.y - arm))
        inner.line(to: NSPoint(x: point.x, y: point.y - gap))
        inner.move(to: NSPoint(x: point.x, y: point.y + gap))
        inner.line(to: NSPoint(x: point.x, y: point.y + arm))
        NSColor.white.setStroke()
        inner.stroke()
    }
}

// MARK: - Shape model

struct Shape {
    enum Kind { case rect, circle, line, arrow, text }
    let kind: Kind
    let start: NSPoint
    var end: NSPoint
    let color: NSColor
    let lineWidth: CGFloat
    let fill: Bool
    let text: String
    let fontSize: CGFloat

    init(kind: Kind, start: NSPoint, end: NSPoint, color: NSColor, lineWidth: CGFloat, fill: Bool, text: String = "", fontSize: CGFloat = 16) {
        self.kind = kind
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
        self.fill = fill
        self.text = text
        self.fontSize = fontSize
    }
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

        if tool == .text {
            activeTool = nil
            NSCursor.arrow.set()
            onToolConsumed?()

            let alert = NSAlert()
            alert.messageText = "Enter text"
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            alert.accessoryView = textField
            alert.window.initialFirstResponder = textField
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let text = textField.stringValue
            guard !text.isEmpty else { return }

            let s = Shape(kind: .text, start: pt, end: pt, color: shapeColor, lineWidth: shapeLineWidth, fill: shapeFill, text: text, fontSize: 16)
            shapes.append(s)
            onShapeFinished?(s)
            needsDisplay = true
            return
        }

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
        inProgress = nil
        // A plain click without a drag would leave an invisible zero-size shape behind.
        if abs(s.end.x - s.start.x) >= 2 || abs(s.end.y - s.start.y) >= 2 {
            shapes.append(s)
            onShapeFinished?(s)
        }
        needsDisplay = true
    }

    private func constrainAspectRatio(_ s: inout Shape, event: NSEvent) {
        guard s.kind != .line && s.kind != .arrow, event.modifierFlags.contains(.shift) else { return }
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
        case .arrow:
            drawArrowShape(s)
        case .text:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: s.fontSize),
                .foregroundColor: s.color,
            ]
            (s.text as NSString).draw(at: s.start, withAttributes: attrs)
        }
    }

    private func drawArrowShape(_ s: Shape) {
        let angle = atan2(s.end.y - s.start.y, s.end.x - s.start.x)
        let len: CGFloat = 10 + s.lineWidth
        let a: CGFloat = .pi / 6
        let baseDist = len * cos(a)

        let shaftEnd = NSPoint(x: s.end.x - baseDist * cos(angle), y: s.end.y - baseDist * sin(angle))
        let path = NSBezierPath()
        path.move(to: s.start)
        path.line(to: shaftEnd)
        path.lineWidth = s.lineWidth
        path.stroke()

        let head = NSBezierPath()
        head.move(to: s.end)
        head.line(to: NSPoint(x: s.end.x - len * cos(angle - a), y: s.end.y - len * sin(angle - a)))
        head.line(to: NSPoint(x: s.end.x - len * cos(angle + a), y: s.end.y - len * sin(angle + a)))
        head.close()
        s.color.setFill()
        head.fill()
    }
}

// MARK: - Palette Extractor

final class PaletteExtractor {
    static func extract(from image: NSImage, count: Int = 5) -> [NSColor] {
        let maxDim: CGFloat = 150
        let w = min(image.size.width, maxDim)
        let h = min(image.size.height, maxDim)

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(w), pixelsHigh: Int(h),
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: Int(w) * 4,
            bitsPerPixel: 32
        )
        guard let rep = rep else { return [] }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: NSSize(width: w, height: h)))
        NSGraphicsContext.restoreGraphicsState()

        guard let pixels = rep.bitmapData else { return [] }

        let bw = Int(w), bh = Int(h)
        var points: [(r: Float, g: Float, b: Float)] = []
        for y in 0..<bh {
            for x in 0..<bw {
                let offset = (y * bw + x) * 4
                points.append((r: Float(pixels[offset]), g: Float(pixels[offset+1]), b: Float(pixels[offset+2])))
            }
        }
        guard !points.isEmpty else { return [] }

        // K-Means with K=count
        let k = min(count, points.count)
        var centroids: [(r: Float, g: Float, b: Float)] = (0..<k).map { i in
            let idx = i * points.count / k
            return points[idx]
        }

        for _ in 0..<10 {
            var sums: [(r: Float, g: Float, b: Float, count: Int)] = Array(repeating: (0,0,0,0), count: k)
            for p in points {
                var best = Float.greatestFiniteMagnitude
                var bestIdx = 0
                for (ci, c) in centroids.enumerated() {
                    let d = (p.r-c.r)*(p.r-c.r) + (p.g-c.g)*(p.g-c.g) + (p.b-c.b)*(p.b-c.b)
                    if d < best { best = d; bestIdx = ci }
                }
                sums[bestIdx].r += p.r; sums[bestIdx].g += p.g; sums[bestIdx].b += p.b
                sums[bestIdx].count += 1
            }
            for i in 0..<k where sums[i].count > 0 {
                centroids[i] = (sums[i].r / Float(sums[i].count), sums[i].g / Float(sums[i].count), sums[i].b / Float(sums[i].count))
            }
        }

        return centroids.map { NSColor(red: CGFloat($0.r)/255, green: CGFloat($0.g)/255, blue: CGFloat($0.b)/255, alpha: 1) }
    }
}

final class CaptureWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    private var image: NSImage
    private let fileURL: URL
    private let toastLabel: NSTextField
    private let overlayView: DrawingOverlayView
    private var copyItem: NSToolbarItem!
    private var saveItem: NSToolbarItem!
    private var saveAsItem: NSToolbarItem!
    private var rectItem: NSToolbarItem!
    private var circleItem: NSToolbarItem!
    private var lineItem: NSToolbarItem!
    private var arrowItem: NSToolbarItem!
    private var textItem: NSToolbarItem!
    private var undoItem: NSToolbarItem!
    private var undoBtn: NSButton!
    private var resizePopUp: NSPopUpButton!
    private var imageView: NSImageView!
    private var imageUndoStack: [NSImage] = []
    private var colorItem: NSToolbarItem!
    private var fillItem: NSToolbarItem!
    private var widthItem: NSToolbarItem!
    private var paletteItem: NSToolbarItem!
    private var accessoryView: NSView!
    private var toolButtons: [NSButton] = []
    private let palettePopover = NSPopover()
    private let widthPopUp: NSPopUpButton
    private var keyMonitor: Any?
    private let colorWell: NSColorWell
    private weak var activeToolItem: NSToolbarItem?
    var historyItem: CaptureHistoryItem?

    init(image: NSImage, fileURL: URL) {
        self.image = image
        self.fileURL = fileURL

        let screenSize = NSScreen.main?.visibleFrame.size ?? NSSize(width: 800, height: 600)
        let maxSize = NSSize(width: screenSize.width * 0.85, height: screenSize.height * 0.85)
        let imageSize = NSSize(
            width: min(image.size.width, maxSize.width),
            height: min(image.size.height, maxSize.height)
        )

        let imageView = NSImageView(image: image)
        self.imageView = imageView
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
            self?.resetToolAppearance()
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

        arrowItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("arrowItem"))
        arrowItem.label = "Arrow"
        arrowItem.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: "Draw arrow")
        arrowItem.target = self
        arrowItem.action = #selector(beginTool)
        arrowItem.isEnabled = true

        circleItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("circleItem"))
        circleItem.label = "Circle"
        circleItem.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Draw circle")
        circleItem.target = self
        circleItem.action = #selector(beginTool)
        circleItem.isEnabled = true

        textItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("textItem"))
        textItem.label = "Text"
        textItem.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Add text")
        textItem.target = self
        textItem.action = #selector(beginTool)
        textItem.isEnabled = true

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

        paletteItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("paletteItem"))
        paletteItem.label = "Palette"
        let paletteBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
        paletteBtn.bezelStyle = .texturedRounded
        paletteBtn.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "Extract palette")
        paletteBtn.target = self
        paletteBtn.action = #selector(extractPalette)
        paletteItem.view = paletteBtn

        let toolbar = NSToolbar(identifier: "CaptureToolbar")
        toolbar.delegate = self
        window.toolbar = toolbar

        let makeBtn = { (symbol: String, tooltip: String, action: Selector) -> NSButton in
            let b = NSButton(frame: NSRect(x: 0, y: 0, width: 44, height: 32))
            b.bezelStyle = .texturedRounded
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))
            b.target = self
            b.action = action
            b.toolTip = tooltip
            b.setButtonType(.pushOnPushOff)
            return b
        }

        let toolBtns = [
            makeBtn("rectangle", "Rectangle", #selector(beginTool)),
            makeBtn("circle", "Circle", #selector(beginTool)),
            makeBtn("line.diagonal", "Line", #selector(beginTool)),
            makeBtn("arrow.right", "Arrow", #selector(beginTool)),
        ]
        toolBtns.enumerated().forEach { i, b in b.tag = i; b.needsDisplay = true }

        let drawStack = NSStackView(views: toolBtns)
        drawStack.orientation = .horizontal
        drawStack.spacing = 6
        drawStack.alignment = .centerY
        drawStack.setContentHuggingPriority(.required, for: .horizontal)

        undoBtn = makeBtn("arrow.uturn.backward", "Undo", #selector(undoShape))
        undoBtn.setButtonType(.momentaryLight)

        resizePopUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 44, height: 32), pullsDown: true)
        resizePopUp.bezelStyle = .texturedRounded
        resizePopUp.toolTip = "Resize"
        resizePopUp.target = self
        resizePopUp.action = #selector(resizeImage(_:))
        let dummy = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        dummy.image = NSImage(systemSymbolName: "arrow.up.arrow.down.circle", accessibilityDescription: "Resize")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))
        resizePopUp.menu?.addItem(dummy)
        for (pct, value) in [("80%", 0.8), ("50%", 0.5), ("25%", 0.25), ("10%", 0.1)] {
            let item = NSMenuItem(title: pct, action: #selector(resizeImage(_:)), keyEquivalent: "")
            item.representedObject = value
            item.target = self
            resizePopUp.menu?.addItem(item)
        }

        let allControls = NSStackView(views: [
            drawStack, colorWell, fillBtn, widthPopUp,
            resizePopUp, undoBtn,
        ])
        allControls.orientation = .horizontal
        allControls.spacing = 6
        allControls.alignment = .centerY

        self.accessoryView = NSView()
        toolButtons = toolBtns
        accessoryView.addSubview(allControls)
        allControls.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            allControls.leadingAnchor.constraint(equalTo: accessoryView.leadingAnchor, constant: 8),
            allControls.topAnchor.constraint(equalTo: accessoryView.topAnchor),
            allControls.bottomAnchor.constraint(equalTo: accessoryView.bottomAnchor),
            allControls.trailingAnchor.constraint(lessThanOrEqualTo: accessoryView.trailingAnchor),
        ])

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = accessoryView
        accessory.layoutAttribute = .bottom
        window.addTitlebarAccessoryViewController(accessory)

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
            if cmd && !shift && chars == "," { (NSApp.delegate as? AppDelegate)?.showPreferences(); return nil }
            if matchesHotkey(event: event, keyCode: savedHotkeyKeyCode, modifiers: savedHotkeyModifiers) { CaptureController.shared.beginCapture(); return nil }
            if matchesHotkey(event: event, keyCode: savedFullHotkeyKeyCode, modifiers: savedFullHotkeyModifiers) { CaptureController.shared.beginFullScreenCapture(); return nil }
            if matchesHotkey(event: event, keyCode: savedWinHotkeyKeyCode, modifiers: savedWinHotkeyModifiers) { CaptureController.shared.beginWindowCapture(); return nil }
            if !cmd && chars == "r" { self.beginTool(self.rectItem); return nil }
            if !cmd && chars == "c" { self.beginTool(self.circleItem); return nil }
            if !cmd && chars == "l" { self.beginTool(self.lineItem); return nil }
            if !cmd && chars == "a" { self.beginTool(self.arrowItem); return nil }
            if !cmd && chars == "t" { self.beginTool(self.textItem); return nil }
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
        [copyItem.itemIdentifier, saveItem.itemIdentifier, saveAsItem.itemIdentifier, .flexibleSpace, paletteItem.itemIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [copyItem.itemIdentifier, saveItem.itemIdentifier, saveAsItem.itemIdentifier, .flexibleSpace, paletteItem.itemIdentifier]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == copyItem.itemIdentifier { return copyItem }
        if identifier == saveItem.itemIdentifier { return saveItem }
        if identifier == saveAsItem.itemIdentifier { return saveAsItem }
        if identifier == paletteItem.itemIdentifier { return paletteItem }
        return nil
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        NSColorPanel.shared.orderOut(nil)
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        CaptureController.shared.captureWindowControllers.removeAll { $0 === self }
        if !CaptureController.isClearing, let item = historyItem, !overlayView.shapes.isEmpty {
            CaptureController.update(item, image: compositedImage())
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

    @objc private func extractPalette() {
        if palettePopover.isShown {
            palettePopover.performClose(nil)
            return
        }

        let colors = PaletteExtractor.extract(from: image, count: 5)
        guard !colors.isEmpty else {
            showToast("Could not extract palette")
            return
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        for color in colors {
            let hex = color.hexString
            let isLight = color.luminance > 0.5

            let swatch = NSView()
            swatch.wantsLayer = true
            swatch.layer?.backgroundColor = color.cgColor
            swatch.identifier = NSUserInterfaceItemIdentifier(hex)

            let label = NSTextField(labelWithString: hex)
            label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            label.alignment = .right
            label.isSelectable = false
            label.isBezeled = false
            label.isEditable = false
            label.drawsBackground = false
            label.textColor = isLight ? .black : .white
            label.translatesAutoresizingMaskIntoConstraints = false
            swatch.addSubview(label)
            NSLayoutConstraint.activate([
                label.trailingAnchor.constraint(equalTo: swatch.trailingAnchor, constant: -4),
                label.bottomAnchor.constraint(equalTo: swatch.bottomAnchor, constant: -2),
            ])

            let click = NSClickGestureRecognizer(target: self, action: #selector(pickColor(_:)))
            swatch.addGestureRecognizer(click)

            swatch.heightAnchor.constraint(equalToConstant: 60).isActive = true
            swatch.widthAnchor.constraint(equalToConstant: 120).isActive = true

            stack.addArrangedSubview(swatch)
        }

        let sep = NSBox()
        sep.boxType = .separator
        stack.addArrangedSubview(sep)

        let jsonBtn = NSButton(title: "Copy as JSON", target: self, action: #selector(copyPaletteJson))
        jsonBtn.setButtonType(.momentaryPushIn)
        jsonBtn.isBordered = false
        jsonBtn.font = NSFont.systemFont(ofSize: 10)
        jsonBtn.contentTintColor = .systemBlue
        jsonBtn.action = #selector(copyPaletteJson)
        jsonBtn.target = self

        let cssBtn = NSButton(title: "Copy as CSS", target: self, action: #selector(copyPaletteCss))
        cssBtn.setButtonType(.momentaryPushIn)
        cssBtn.isBordered = false
        cssBtn.font = NSFont.systemFont(ofSize: 10)
        cssBtn.contentTintColor = .systemBlue

        let footer = NSStackView(views: [jsonBtn, cssBtn])
        footer.orientation = .vertical
        footer.spacing = 2
        footer.alignment = .leading
        footer.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        footer.widthAnchor.constraint(equalToConstant: 120).isActive = true
        stack.addArrangedSubview(footer)

        let vc = NSViewController()
        vc.view = stack
        palettePopover.contentViewController = vc
        palettePopover.behavior = .transient
        if let view = paletteItem.view {
            palettePopover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        }
    }

    @objc private func copyPaletteJson() {
        guard let vc = palettePopover.contentViewController else { return }
        let stack = vc.view as? NSStackView
        let hexes: [String] = stack?.arrangedSubviews.compactMap { view in
            guard let swatch = view as? NSView, let hex = swatch.identifier?.rawValue, hex.hasPrefix("#") else { return nil }
            return "\"\(hex)\""
        } ?? []
        guard !hexes.isEmpty else { return }
        let json = "[\(hexes.joined(separator: ", "))]"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(json, forType: .string)
        showToast("Copied JSON palette")
        palettePopover.performClose(nil)
    }

    @objc private func copyPaletteCss() {
        guard let vc = palettePopover.contentViewController else { return }
        let stack = vc.view as? NSStackView
        let hexes: [String] = stack?.arrangedSubviews.compactMap { view in
            guard let swatch = view as? NSView, let hex = swatch.identifier?.rawValue, hex.hasPrefix("#") else { return nil }
            return hex
        } ?? []
        guard !hexes.isEmpty else { return }
        let css = hexes.enumerated().map { "--color\($0.offset + 1): \($0.element);" }.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(css, forType: .string)
        showToast("Copied CSS palette")
        palettePopover.performClose(nil)
    }

    @objc func pickColor(_ sender: NSClickGestureRecognizer) {
        guard let hex = sender.view?.identifier?.rawValue,
              let color = NSColor(hexString: hex)
        else { return }

        overlayView.shapeColor = color
        colorWell.color = color
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "drawingColor")
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(hex, forType: .string)
        showToast("Copied \(hex)")

        palettePopover.performClose(nil)
    }

    @objc private func beginTool(_ sender: Any) {
        resetToolAppearance()
        var toolBtn: NSButton?
        let ti: NSToolbarItem?
        if let item = sender as? NSToolbarItem { ti = item }
        else if let btn = sender as? NSButton {
            toolBtn = btn
            let mapped = [rectItem, circleItem, lineItem, arrowItem, textItem]
            ti = btn.tag < mapped.count ? mapped[btn.tag] : nil
        } else { ti = nil }
        guard let t = ti else { return }
        if t.itemIdentifier == rectItem.itemIdentifier {
            overlayView.activeTool = .rect
            activeToolItem = rectItem
            rectItem.image = NSImage(systemSymbolName: "rectangle.fill", accessibilityDescription: "Draw rectangle")
        } else if t.itemIdentifier == circleItem.itemIdentifier {
            overlayView.activeTool = .circle
            activeToolItem = circleItem
            circleItem.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Draw circle")
        } else if t.itemIdentifier == lineItem.itemIdentifier {
            overlayView.activeTool = .line
            activeToolItem = lineItem
            lineItem.image = NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: "Draw line")
        } else if t.itemIdentifier == arrowItem.itemIdentifier {
            overlayView.activeTool = .arrow
            activeToolItem = arrowItem
            arrowItem.image = NSImage(systemSymbolName: "arrow.right.to.line", accessibilityDescription: "Draw arrow")
        } else if t.itemIdentifier == textItem.itemIdentifier {
            overlayView.activeTool = .text
            activeToolItem = textItem
            textItem.image = NSImage(systemSymbolName: "textformat.size", accessibilityDescription: "Add text")
        }
        toolBtn?.state = .on
    }

    private func resetToolAppearance() {
        if let item = activeToolItem {
            if item.itemIdentifier == rectItem.itemIdentifier {
                rectItem.image = NSImage(systemSymbolName: "rectangle", accessibilityDescription: "Draw rectangle")
            } else if item.itemIdentifier == circleItem.itemIdentifier {
                circleItem.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Draw circle")
            } else if item.itemIdentifier == lineItem.itemIdentifier {
                lineItem.image = NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "Draw line")
            } else if item.itemIdentifier == arrowItem.itemIdentifier {
                arrowItem.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: "Draw arrow")
            } else if item.itemIdentifier == textItem.itemIdentifier {
                textItem.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Add text")
            }
        }
        activeToolItem = nil
        overlayView.activeTool = nil
        for btn in toolButtons { btn.state = .off }
    }

    @objc func undoShape() {
        if !overlayView.shapes.isEmpty {
            overlayView.shapes.removeLast()
            overlayView.needsDisplay = true
            undoItem.isEnabled = !overlayView.shapes.isEmpty || !imageUndoStack.isEmpty
            return
        }
        guard let prev = imageUndoStack.popLast() else { return }
        let prevSize = prev.size
        image = prev
        imageView.image = prev
        window?.setContentSize(prevSize)
        imageView.frame = NSRect(origin: .zero, size: prevSize)
        overlayView.frame = NSRect(origin: .zero, size: prevSize)
        overlayView.needsDisplay = true
        window?.title = "Capture  \(Int(prevSize.width))x\(Int(prevSize.height))"
        undoItem.isEnabled = !imageUndoStack.isEmpty
        showToast("Undo resize")
    }

    @objc private func resizeImage(_ sender: NSMenuItem) {
        guard let scale = sender.representedObject as? Double, scale > 0 else { return }

        let source: NSImage
        if !overlayView.shapes.isEmpty {
            source = compositedImage()
        } else {
            source = image
        }

        let newSize = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        let scaled = NSImage(size: newSize)
        scaled.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: newSize))
        scaled.unlockFocus()

        imageUndoStack.append(image)
        image = scaled
        imageView.image = scaled
        overlayView.shapes.removeAll()
        overlayView.needsDisplay = true
        undoItem.isEnabled = true

        window?.setContentSize(newSize)
        imageView.frame = NSRect(origin: .zero, size: newSize)
        overlayView.frame = NSRect(origin: .zero, size: newSize)

        let pct = Int(scale * 100)
        window?.title = "Capture  \(Int(newSize.width))x\(Int(newSize.height))"
        showToast("Resized to \(pct)%")

        if let item = historyItem {
            CaptureController.update(item, image: scaled)
        }
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
            case .arrow:
                let angle = atan2(end.y - start.y, end.x - start.x)
                let len: CGFloat = (10 + s.lineWidth) * sx
                let a: CGFloat = .pi / 6
                let baseDist = len * cos(a)
                let shaftEnd = NSPoint(x: end.x - baseDist * cos(angle), y: end.y - baseDist * sin(angle))
                let apath = NSBezierPath()
                apath.move(to: start)
                apath.line(to: shaftEnd)
                apath.lineWidth = s.lineWidth * sx
                apath.stroke()
                let ahead = NSBezierPath()
                ahead.move(to: end)
                ahead.line(to: NSPoint(x: end.x - len * cos(angle - a), y: end.y - len * sin(angle - a)))
                ahead.line(to: NSPoint(x: end.x - len * cos(angle + a), y: end.y - len * sin(angle + a)))
                ahead.close()
                s.color.setFill()
                ahead.fill()
            case .text:
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: s.fontSize * sx),
                    .foregroundColor: s.color,
                ]
                // The overlay view is flipped (text hangs below the click); this context is not.
                let textHeight = (s.text as NSString).size(withAttributes: attrs).height
                (s.text as NSString).draw(at: NSPoint(x: start.x, y: start.y - textHeight), withAttributes: attrs)
            }
        }
        img.unlockFocus()
        return img
    }

    private func savePNG(_ img: NSImage, to url: URL) throws {
        guard let data = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: data),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try pngData.write(to: url)
    }

    @objc func copyImage() {
        let img = compositedImage()
        let pb = NSPasteboard.general
        pb.clearContents()
        if let data = img.tiffRepresentation {
            let item = NSPasteboardItem()
            item.setData(data, forType: .tiff)
            pb.writeObjects([item])
        }
        showToast("Copied to pasteboard")
        NSSound(named: "Pop")?.play()
    }

    @objc func saveImage() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try savePNG(compositedImage(), to: fileURL)
            showToast("Saved to ~/Pictures/DotMenu")
        } catch {
            showToast("Save failed: \(error.localizedDescription)")
        }
    }

    @objc func saveAsImage() {
        let panel = NSSavePanel()
        panel.title = "Save capture as"
        panel.nameFieldStringValue = fileURL.lastPathComponent
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try savePNG(compositedImage(), to: url)
            showToast("Saved")
        } catch {
            showToast("Save failed: \(error.localizedDescription)")
        }
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

    private func fmtShortcut(keyCode: UInt16, modifiers: UInt) -> String {
        let mods = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        if let source = CGEventSource(stateID: .combinedSessionState),
           let cgEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
           let nsEvent = NSEvent(cgEvent: cgEvent) {
            parts.append(nsEvent.charactersIgnoringModifiers?.uppercased() ?? "?")
        } else {
            parts.append("#\(keyCode)")
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
                    Text("Selection:")
                    Text(fmtShortcut(keyCode: savedHotkeyKeyCode, modifiers: savedHotkeyModifiers))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Full screen:")
                    Text(fmtShortcut(keyCode: savedFullHotkeyKeyCode, modifiers: savedFullHotkeyModifiers))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Window:")
                    Text(fmtShortcut(keyCode: savedWinHotkeyKeyCode, modifiers: savedWinHotkeyModifiers))
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

extension NSColor {
    var hexString: String {
        guard let converted = usingColorSpace(.sRGB) else { return "#000000" }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    var luminance: CGFloat {
        guard let converted = usingColorSpace(.sRGB) else { return 0.5 }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    convenience init?(hexString: String) {
        let h = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard h.count == 6 else { return nil }
        guard let v = Int(h, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
#if DOTMENU_TESTS
exit(runTests())
#else
app.run()
#endif
