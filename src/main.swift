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

// MARK: - Capture Window Controller

final class CaptureWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    private let image: NSImage
    private let fileURL: URL
    private let toastLabel: NSTextField
    private var copyItem: NSToolbarItem!
    private var saveItem: NSToolbarItem!

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
        window.contentView = imageView
        window.isReleasedWhenClosed = false

        super.init(window: window)

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

        let toolbar = NSToolbar(identifier: "CaptureToolbar")
        toolbar.delegate = self
        window.toolbar = toolbar

        window.delegate = self
        imageView.addSubview(toastLabel)
        toastLabel.frame.origin.x = (imageSize.width - 200) / 2

        NSApp.setActivationPolicy(.regular)
    }

    required init?(coder: NSCoder) { nil }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [copyItem.itemIdentifier, saveItem.itemIdentifier, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [copyItem.itemIdentifier, saveItem.itemIdentifier, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == copyItem.itemIdentifier { return copyItem }
        if identifier == saveItem.itemIdentifier { return saveItem }
        return nil
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        let hasOtherWindows = NSApp.windows.contains { w in
            w != window && w.isVisible
        }
        if !hasOtherWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func copyImage() {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let data = image.tiffRepresentation {
            let item = NSPasteboardItem()
            item.setData(data, forType: .tiff)
            pb.writeObjects([item])
        }
        showToast("Copied to pasteboard")
    }

    @objc private func saveImage() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: data),
               let pngData = rep.representation(using: .png, properties: [:]) {
                try pngData.write(to: fileURL)
            }
        } catch {}
        showToast("Saved to ~/Pictures/DotMenu")
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
