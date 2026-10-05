import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut that works while other apps (e.g. Teams) are
/// in front. Uses Carbon's RegisterEventHotKey, which — unlike global event
/// monitors — needs no Accessibility permission. The app uses only one.
final class HotKey {
    struct Combo: Codable, Equatable {
        var keyCode: UInt32
        var modifiers: UInt32  // Carbon mask: cmdKey | optionKey | controlKey | shiftKey
        var key: String        // printable key for display, e.g. "M"

        static let standard = Combo(keyCode: UInt32(kVK_ANSI_M),
                                    modifiers: UInt32(cmdKey | optionKey), key: "M")

        /// From a key press; nil unless it includes ⌘, ⌥ or ⌃ — a plain key
        /// would hijack normal typing in every app.
        init?(event: NSEvent) {
            let f = event.modifierFlags
            var m: UInt32 = 0
            if f.contains(.command) { m |= UInt32(cmdKey) }
            if f.contains(.option) { m |= UInt32(optionKey) }
            if f.contains(.control) { m |= UInt32(controlKey) }
            guard m != 0 else { return nil }
            if f.contains(.shift) { m |= UInt32(shiftKey) }
            let chars = event.charactersIgnoringModifiers ?? ""
            // Function/arrow keys come through as private-use characters.
            let printable = chars.unicodeScalars.allSatisfy { !(0xF700...0xF8FF).contains($0.value) }
            let name = chars == " " ? "Space" : chars.uppercased()
            self.init(keyCode: UInt32(event.keyCode), modifiers: m,
                      key: printable && !chars.isEmpty ? name : "Key \(event.keyCode)")
        }

        init(keyCode: UInt32, modifiers: UInt32, key: String) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.key = key
        }

        var display: String {
            var s = ""
            if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
            return s + key
        }
    }

    private static var onPress: (() -> Void)?
    private static let installHandler: Void = {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.onPress?()
            return noErr
        }, 1, &spec, nil, nil)
    }()

    private var ref: EventHotKeyRef?

    /// Fails (nil) if another app already owns this combination.
    init?(_ combo: Combo, onPress: @escaping () -> Void) {
        _ = Self.installHandler
        let id = EventHotKeyID(signature: OSType(0x4D494D4F), id: 1)  // "MIMO"
        guard RegisterEventHotKey(combo.keyCode, combo.modifiers, id,
                                  GetApplicationEventTarget(), 0, &ref) == noErr else {
            return nil
        }
        Self.onPress = onPress
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }
}
