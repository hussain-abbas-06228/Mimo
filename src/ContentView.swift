import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Frosted-glass blur behind the panel content.
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Liquid Glass behind a control on macOS 26+, the old subtle fill before that.
struct ControlGlass<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background(shape.fill(Color.white.opacity(0.07)))
        }
    }
}

/// The Mimo mascot: two overlapping orbs (coral = spoken language, blue = English)
/// sharing one pair of eyes. Same geometry as scripts/make-icon.swift.
struct MimoMark: View {
    var width: CGFloat

    var body: some View {
        let u = width / 330  // design units: orbs 200 wide, centres 130 apart
        ZStack {
            Circle().fill(Color(red: 1, green: 0.44, blue: 0.35))
                .frame(width: 200 * u).offset(x: -65 * u)
            Circle().fill(Color(red: 0.27, green: 0.55, blue: 1).opacity(0.85))
                .frame(width: 200 * u).offset(x: 65 * u)
            HStack(spacing: 34 * u) {
                Ellipse().frame(width: 42 * u, height: 52 * u)
                Ellipse().frame(width: 42 * u, height: 52 * u)
            }
            .foregroundStyle(Color(red: 0.09, green: 0.09, blue: 0.16))
            .offset(y: -22 * u)
        }
        .frame(width: width, height: 200 * u)
    }
}

struct ContentView: View {
    @ObservedObject var controller: TranscriptionController
    @AppStorage("bgOpacity") private var bgOpacity: Double = 0.40
    @AppStorage("fontSize") private var fontSize: Double = 21

    var body: some View {
        ZStack {
            VisualEffectView()
            Color.black.opacity(bgOpacity)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                    .padding(.bottom, 8)

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 1)

                transcript
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .white.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        )
    }

    // MARK: - Header

    /// Full header when there's room; on narrow panels drop the app name and
    /// opacity slider instead of letting SwiftUI wrap labels letter by letter.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            headerRow(compact: false)
            headerRow(compact: true)
        }
    }

    private func headerRow(compact: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                MimoMark(width: 26)
                if !compact {
                    Text("Mimo")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            statusPill

            Spacer(minLength: 8)

            controlButton(
                icon: controller.isRunning ? "pause.fill" : "play.fill",
                tint: controller.isRunning ? .orange : .green,
                help: controller.isRunning ? "Pause listening" : "Start listening"
            ) {
                controller.isRunning ? controller.stop() : controller.start()
            }

            HStack(spacing: 4) {
                languageMenu

                Picker("", selection: $controller.translateToEnglish) {
                    Text("EN").tag(true)
                    Text(originalLabel).tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 92)
                .help("EN = English translation · \(originalLabel) = original-language transcript")
            }

            if !compact {
                HStack(spacing: 5) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                    Slider(value: $bgOpacity, in: 0.0...0.85)
                        .frame(width: 64)
                        .controlSize(.mini)
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .modifier(ControlGlass(shape: Capsule()))
                .help("Background opacity")
            }

            HStack(spacing: 1) {
                controlButton(icon: "textformat.size.smaller", help: "Smaller text") {
                    fontSize = max(13, fontSize - 2)
                }
                controlButton(icon: "textformat.size.larger", help: "Larger text") {
                    fontSize = min(42, fontSize + 2)
                }
            }

            HStack(spacing: 1) {
                controlButton(icon: "doc.on.doc", help: "Copy the whole transcript") {
                    copyTranscript()
                }
                controlButton(icon: "square.and.arrow.down", help: "Save transcript as a text file") {
                    saveTranscript()
                }
            }

            controlButton(icon: "trash", help: "Clear transcript") {
                controller.clear()
            }

            controlButton(icon: "chevron.down", help: "Hide — bring it back with your shortcut (⌥⌘M by default) or the menu-bar icon") {
                NotificationCenter.default.post(name: .ltHidePanel, object: nil)
            }
        }
    }

    // MARK: - Language

    /// Languages offered besides auto-detect; Whisper understands ~100, these are the common ones.
    private static let languages = [
        "ar", "zh", "nl", "fr", "de", "hi", "it", "ja", "ko", "pl",
        "pt", "ru", "es", "sv", "tr", "uk",
    ].sorted { name(of: $0) < name(of: $1) }

    private static func name(of code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    private var originalLabel: String {
        controller.language == "auto" ? "Orig" : controller.language.uppercased()
    }

    private var languageMenu: some View {
        Menu {
            Picker("Spoken language", selection: $controller.language) {
                Text("Auto-detect").tag("auto")
                Divider()
                ForEach(Self.languages, id: \.self) { code in
                    Text(Self.name(of: code)).tag(code)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "globe")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 28, height: 22)
        .modifier(ControlGlass(shape: RoundedRectangle(cornerRadius: 6, style: .continuous)))
        .help("Spoken language: \(controller.language == "auto" ? "auto-detect" : Self.name(of: controller.language))")
    }

    // MARK: - Copy / save

    /// Whole transcript including the live line, or nil (with a beep) if empty.
    private var transcriptText: String? {
        let lines = controller.committed + (controller.partial.isEmpty ? [] : [controller.partial])
        guard !lines.isEmpty else { NSSound.beep(); return nil }
        return lines.joined(separator: "\n\n")
    }

    private func copyTranscript() {
        guard let text = transcriptText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveTranscript() {
        guard let text = transcriptText else { return }

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH.mm"
        let save = NSSavePanel()
        save.allowedContentTypes = [.plainText]
        save.nameFieldStringValue = "Mimo transcript \(stamp.string(from: Date())).txt"
        NSApp.activate(ignoringOtherApps: true)  // the overlay never activates the app itself
        guard save.runModal() == .OK, let url = save.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func controlButton(icon: String, tint: Color = .white,
                               help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint.opacity(tint == .white ? 0.55 : 0.9))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
                .modifier(ControlGlass(shape: RoundedRectangle(cornerRadius: 6, style: .continuous)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(0.8), radius: 3)
            Text(statusLabel)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private var statusColor: Color {
        switch controller.status {
        case .idle: return .gray
        case .loadingModel, .starting: return .orange
        case .live: return .green
        case .error: return .red
        }
    }

    private var statusLabel: String {
        switch controller.status {
        case .idle: return "Paused"
        case .loadingModel: return "Loading…"
        case .starting: return "Starting…"
        case .live: return "Live"
        case .error: return "Error"
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let notice = controller.notice {
                        noticeView(notice)
                    }
                    if case .error(let message) = controller.status {
                        errorView(message)
                    } else if controller.committed.isEmpty && controller.partial.isEmpty {
                        emptyState
                    }

                    ForEach(Array(controller.committed.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: fontSize, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.94))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !controller.partial.isEmpty {
                        Text(controller.partial)
                            .font(.system(size: fontSize, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.50))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: controller.committed.count) {
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom") }
            }
            .onChange(of: controller.partial) {
                proxy.scrollTo("bottom")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            MimoMark(width: 58)
            Text(placeholderText)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
    }

    private func noticeView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "keyboard")
                .foregroundStyle(.white.opacity(0.8))
            Text(message)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.blue.opacity(0.25))
        )
    }

    private func errorView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .textSelection(.enabled)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.18))
        )
    }

    private var placeholderText: String {
        switch controller.status {
        case .loadingModel: return "Warming up the translator…"
        case .starting: return "Connecting to your Mac's audio…"
        case .live:
            return controller.translateToEnglish
                ? "Listening — speech from any app\nwill appear here in English."
                : "Listening — speech from any app\nwill appear here as a transcript."
        default: return "Press ▶ to start live translation."
        }
    }
}
