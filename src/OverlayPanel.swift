import AppKit

/// A floating, always-on-top panel that stays above every app — including
/// full-screen Microsoft Teams — without stealing keyboard focus from them.
final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        minSize = NSSize(width: 480, height: 140)
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    // Allow interacting with sliders/buttons without activating the whole app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
