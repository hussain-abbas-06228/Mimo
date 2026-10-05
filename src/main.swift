import AppKit
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildStatusItem()

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
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let img = NSImage(systemSymbolName: "captions.bubble.fill",
                             accessibilityDescription: "LiveTranslate") {
            img.isTemplate = true
            item.button?.image = img
        } else {
            item.button?.title = "🦜"
        }

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

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LiveTranslate",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        showHideItem?.title = (panel?.isVisible == true) ? "Hide Subtitles" : "Show Subtitles"
        startStopItem?.title = (controller?.isRunning == true) ? "Pause Listening" : "Start Listening"
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit LiveTranslate",
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
