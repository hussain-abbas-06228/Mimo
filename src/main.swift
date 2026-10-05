import AppKit
import Carbon.HIToolbox
import SwiftUI

extension Notification.Name {
    static let ltHidePanel = Notification.Name("ltHidePanel")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var panel: OverlayPanel?
    private var controller: TranscriptionController?
    private var statusItem: NSStatusItem?
    private var showHideItem: NSMenuItem?
    private var startStopItem: NSMenuItem?
    private var shortcutItem: NSMenuItem?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildStatusItem()
        registerHotKey(Self.savedCombo)

        guard let models = Self.findModels() else {
            let alert = NSAlert()
            alert.messageText = "Whisper model not found"
            alert.informativeText = """
            Could not find a ggml-*.bin model file.

            Run scripts/download-model.sh in the project folder, \
            or set the WHISPER_MODEL environment variable to a model path.
            """
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let controller = TranscriptionController(
            translateModelPath: models.translate,
            transcribeModelPath: models.transcribe
        )
        self.controller = controller

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = min(820, screen.width * 0.6)
        let height: CGFloat = 230
        let rect = NSRect(
            x: screen.midX - width / 2,
            y: screen.minY + 60,
            width: width,
            height: height
        )

        let panel = OverlayPanel(contentRect: rect)
        panel.contentView = NSHostingView(rootView: ContentView(controller: controller))
        panel.delegate = self
        panel.setFrameAutosaveName("MimoPanel")  // restores and remembers position/size
        panel.orderFrontRegardless()
        self.panel = panel

        NotificationCenter.default.addObserver(
            forName: .ltHidePanel, object: nil, queue: .main
        ) { [weak self] _ in self?.hidePanel() }

        NSApp.activate(ignoringOtherApps: true)

        // Kick off capture immediately so the permission prompt appears on first launch.
        controller.start()
    }

    // MARK: - Show / hide (the panel hides instead of quitting)

    private func showPanel() {
        panel?.orderFrontRegardless()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    @objc private func toggleVisibility() {
        if panel?.isVisible == true { hidePanel() } else { showPanel() }
    }

    @objc private func toggleListening() {
        guard let controller else { return }
        controller.isRunning ? controller.stop() : controller.start()
        if controller.isRunning || controller.status != .idle { showPanel() }
    }

    /// Red close button on the panel → hide, keep running in the menu bar.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hidePanel()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon brings the subtitles back.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    // MARK: - Menu bar status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.statusIcon()
        item.button?.setAccessibilityLabel("Mimo")

        let menu = NSMenu()
        menu.delegate = self

        let showHide = NSMenuItem(title: "Hide Subtitles",
                                  action: #selector(toggleVisibility), keyEquivalent: "")
        showHide.target = self
        menu.addItem(showHide)
        showHideItem = showHide

        let startStop = NSMenuItem(title: "Pause Listening",
                                   action: #selector(toggleListening), keyEquivalent: "")
        startStop.target = self
        menu.addItem(startStop)
        startStopItem = startStop

        let shortcut = NSMenuItem(title: "Change Show/Hide Shortcut…",
                                  action: #selector(recordShortcut), keyEquivalent: "")
        shortcut.target = self
        menu.addItem(shortcut)
        shortcutItem = shortcut

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Mimo",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    /// Menu-bar version of the mascot: two overlapping orbs with cut-out eyes,
    /// drawn as a template image so macOS tints it for light/dark menu bars.
    private static func statusIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { r in
            let d: CGFloat = 13, y = (r.height - d) / 2
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(ovalIn: NSRect(x: 1.5, y: y, width: d, height: d)).fill()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: r.width - d - 1.5, y: y, width: d, height: d)).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            for x in [r.midX - 2.6, r.midX + 2.6] {
                NSBezierPath(ovalIn: NSRect(x: x - 1.25, y: r.midY - 0.6, width: 2.5, height: 3.4)).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        showHideItem?.title = (panel?.isVisible == true) ? "Hide Subtitles" : "Show Subtitles"
        startStopItem?.title = (controller?.isRunning == true) ? "Pause Listening" : "Start Listening"
    }

    // MARK: - Global show/hide shortcut

    private static var savedCombo: HotKey.Combo {
        UserDefaults.standard.data(forKey: "hotKey")
            .flatMap { try? JSONDecoder().decode(HotKey.Combo.self, from: $0) } ?? .standard
    }

    /// Registers `combo` as the show/hide shortcut. Returns false if another app owns it.
    @discardableResult
    private func registerHotKey(_ combo: HotKey.Combo) -> Bool {
        hotKey = nil  // release the old combination first so it can be re-registered
        hotKey = HotKey(combo) { [weak self] in self?.toggleVisibility() }
        let ok = hotKey != nil
        shortcutItem?.title = ok
            ? "Change Show/Hide Shortcut (\(combo.display))…"
            : "Change Show/Hide Shortcut (\(combo.display) is taken)…"
        return ok
    }

    private var recordMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    /// Records the next key combination pressed as the new shortcut. The prompt
    /// lives in the overlay panel, which can take key presses without
    /// activating the app — a modal alert stays hidden (and freezes the app)
    /// while another app such as Teams is in front.
    @objc private func recordShortcut() {
        // Start after the status menu has closed, or the panel can't become key.
        DispatchQueue.main.async { self.beginRecording() }
    }

    private func beginRecording() {
        guard let panel, let controller, recordMonitor == nil else { return }
        let current = Self.savedCombo
        hotKey = nil  // so pressing the current combination can be recorded too

        showPanel()
        panel.makeKey()
        controller.notice = "Press the new show/hide shortcut: ⌘, ⌥ or ⌃ plus a key. " +
            "Esc cancels (current: \(current.display))."

        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.finishRecording(nil, current: current)
            } else if let combo = HotKey.Combo(event: event) {
                self?.finishRecording(combo, current: current)
            }
            return nil  // swallow keys while recording
        }
        // Clicking elsewhere cancels, so the shortcut is never left unregistered.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.finishRecording(nil, current: current) }
    }

    private func finishRecording(_ combo: HotKey.Combo?, current: HotKey.Combo) {
        if let recordMonitor { NSEvent.removeMonitor(recordMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        recordMonitor = nil
        resignObserver = nil

        var message: String?
        if let combo, combo != current {
            if registerHotKey(combo) {
                UserDefaults.standard.set(try? JSONEncoder().encode(combo), forKey: "hotKey")
                message = "Show/hide shortcut is now \(combo.display)."
            } else {
                registerHotKey(current)
                message = "\(combo.display) is already used by another app. Kept \(current.display)."
            }
        } else {
            registerHotKey(current)
        }
        controller?.notice = message
        if let message {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                if self?.controller?.notice == message { self?.controller?.notice = nil }
            }
        }
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Mimo",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    /// Picks the best available model for each mode.
    ///
    /// EN (translate): "turbo" models cannot translate, so prefer
    /// medium > small > large > base > tiny, excluding anything turbo.
    /// DE (transcribe): turbo is both the most accurate and fast, so prefer
    /// turbo > large > medium > small > base > tiny.
    ///
    /// Lookup dirs: $WHISPER_MODEL (exact file, used for both modes) →
    /// app bundle Resources/models → LTModelDir from Info.plist.
    static func findModels() -> (translate: String, transcribe: String)? {
        let fm = FileManager.default

        if let env = ProcessInfo.processInfo.environment["WHISPER_MODEL"],
           fm.fileExists(atPath: env) {
            return (env, env)
        }

        var dirs: [String] = []
        if let res = Bundle.main.resourcePath {
            dirs.append(res + "/models")
        }
        if let dir = Bundle.main.object(forInfoDictionaryKey: "LTModelDir") as? String {
            dirs.append(dir)
        }

        var bins: [String] = []
        for dir in dirs {
            if let files = try? fm.contentsOfDirectory(atPath: dir) {
                bins += files
                    .filter { $0.hasPrefix("ggml-") && $0.hasSuffix(".bin") }
                    .map { dir + "/" + $0 }
            }
        }
        guard !bins.isEmpty else { return nil }

        func pick(order: [String], excludeTurbo: Bool) -> String? {
            let pool = excludeTurbo ? bins.filter { !$0.contains("turbo") } : bins
            for key in order {
                if let hit = pool.first(where: { ($0 as NSString).lastPathComponent.contains(key) }) {
                    return hit
                }
            }
            return pool.first
        }

        let translate = pick(order: ["medium", "small", "large", "base", "tiny"],
                             excludeTurbo: true)
        let transcribe = pick(order: ["turbo", "large", "medium", "small", "base", "tiny"],
                              excludeTurbo: false)

        guard translate != nil || transcribe != nil else { return nil }
        return (translate ?? transcribe!, transcribe ?? translate!)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
