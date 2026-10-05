import Foundation
import ScreenCaptureKit
import CoreMedia

/// Captures the Mac's system audio output (everything you hear: Teams, browser, TV apps…)
/// using ScreenCaptureKit, delivered as 16 kHz mono Float32 — exactly what Whisper expects.
final class AudioCaptureManager: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "mimo.audio")

    var onSamples: (([Float]) -> Void)?
    var onError: ((String) -> Void)?

    func start() async throws {
        // Ask explicitly: this registers the app in System Settings → Screen & System
        // Audio Recording and shows the prompt. Relying on SCShareableContent alone
        // sometimes fails without ever listing the app.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "Mimo", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No display found to capture audio from."
            ])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.sampleRate = 16000
        cfg.channelCount = 1
        cfg.excludesCurrentProcessAudio = true
        // We never consume video frames; keep the video side as cheap as possible.
        cfg.width = 2
        cfg.height = 2
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        cfg.showsCursor = false

        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await s.startCapture()
        stream = s
    }

    func stop() async {
        guard let s = stream else { return }
        stream = nil
        try? await s.stopCapture()
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }

        try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
            let buffers = Array(audioBufferList)
            guard let first = buffers.first, let mData = first.mData else { return }

            let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { return }
            let ptr = mData.assumingMemoryBound(to: Float.self)
            var samples = Array(UnsafeBufferPointer(start: ptr, count: count))

            // If the OS hands us more than one channel despite channelCount = 1,
            // mix the remaining channels in.
            if buffers.count > 1 {
                for extra in buffers.dropFirst() {
                    guard let m = extra.mData else { continue }
                    let c = min(count, Int(extra.mDataByteSize) / MemoryLayout<Float>.size)
                    let p = m.assumingMemoryBound(to: Float.self)
                    for i in 0..<c { samples[i] = (samples[i] + p[i]) * 0.5 }
                }
            }
            onSamples?(samples)
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        onError?(error.localizedDescription)
    }
}
