import SwiftUI
import AppKit

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

struct ContentView: View {
    @ObservedObject var controller: TranscriptionController
    @State private var bgOpacity: Double = 0.40
    @State private var fontSize: Double = 21

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

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Text("🦜").font(.system(size: 15))
                Text("LiveTranslate")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
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

            Picker("", selection: $controller.translateToEnglish) {
                Text("EN").tag(true)
                Text("DE").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 86)
            .help("EN = English translation · DE = German transcript")

            HStack(spacing: 5) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                Slider(value: $bgOpacity, in: 0.0...0.85)
                    .frame(width: 64)
                    .controlSize(.mini)
            }
            .help("Background opacity")

            HStack(spacing: 1) {
                controlButton(icon: "textformat.size.smaller", help: "Smaller text") {
                    fontSize = max(13, fontSize - 2)
                }
                controlButton(icon: "textformat.size.larger", help: "Larger text") {
                    fontSize = min(42, fontSize + 2)
                }
            }

            controlButton(icon: "trash", help: "Clear transcript") {
                controller.clear()
            }

            controlButton(icon: "chevron.down", help: "Hide — reopen from the 💬 icon in the menu bar") {
                NotificationCenter.default.post(name: .ltHidePanel, object: nil)
            }
        }
    }

    private func controlButton(icon: String, tint: Color = .white,
                               help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint.opacity(tint == .white ? 0.55 : 0.9))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
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
            Text("🦜")
                .font(.system(size: 34))
                .opacity(0.9)
            Text(placeholderText)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
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
        case .live: return "Listening — German speech from any app\nwill appear here in English."
        default: return "Press ▶ to start live translation."
        }
    }
}
