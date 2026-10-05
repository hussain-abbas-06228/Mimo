import Foundation
import Combine
import AppKit

/// Glues audio capture to Whisper inference and publishes text for the UI.
///
/// Streaming strategy: system audio accumulates in a buffer. Every ~1.2 s the whole
/// unprocessed buffer is run through Whisper and shown as a live "partial" line.
/// When the speaker pauses (trailing silence) or the buffer reaches ~9 s, the text
/// is committed to the transcript and the consumed audio is dropped.
///
/// Shared state is guarded by bufferLock, the serial inference queue, or the main queue.
final class TranscriptionController: ObservableObject, @unchecked Sendable {
    enum Status: Equatable {
        case idle
        case loadingModel
        case starting
        case live
        case error(String)
    }

    @Published var committed: [String] = []
    @Published var partial: String = ""
    @Published var status: Status = .idle
    @Published var translateToEnglish: Bool =
        UserDefaults.standard.object(forKey: "translateToEnglish") as? Bool ?? true {
        didSet { UserDefaults.standard.set(translateToEnglish, forKey: "translateToEnglish") }
    }
    @Published var isRunning: Bool = false

    private let capture = AudioCaptureManager()
    private let translateModelPath: String
    private let transcribeModelPath: String
    /// Engines cached by model path — EN and DE modes may use different models.
    private var engines: [String: WhisperEngine] = [:]

    private var buffer: [Float] = []
    private let bufferLock = NSLock()
    private var timer: DispatchSourceTimer?
    private let inferenceQueue = DispatchQueue(label: "mimo.inference", qos: .userInitiated)
    private var inferenceBusy = false

    private let sampleRate = 16000
    private var minSamples: Int { sampleRate * 3 / 2 }        // 1.5 s before first run
    private var splitSamples: Int { sampleRate * 5 }          // after 5 s, commit finished sentences
    private var hardCommitSamples: Int { sampleRate * 20 }    // never-pausing speaker: cut at 20 s
    private var silenceCommitSamples: Int { sampleRate * 5 / 2 } // pause-commit needs ≥ 2.5 s
    private let silenceRMS: Float = 0.0045

    init(translateModelPath: String, transcribeModelPath: String) {
        self.translateModelPath = translateModelPath
        self.transcribeModelPath = transcribeModelPath

        capture.onSamples = { [weak self] samples in
            guard let self else { return }
            self.bufferLock.lock()
            self.buffer.append(contentsOf: samples)
            // Hard safety cap: never hold more than 30 s of audio.
            let cap = self.sampleRate * 30
            if self.buffer.count > cap {
                self.buffer.removeFirst(self.buffer.count - cap)
            }
            self.bufferLock.unlock()
        }
        capture.onError = { [weak self] message in
            DispatchQueue.main.async {
                self?.status = .error(message)
                self?.isRunning = false
            }
        }
    }

    /// Loads (or returns the cached) engine for the current mode.
    /// Must be called on the inference queue.
    private func engineFor(translate: Bool) -> WhisperEngine? {
        let path = translate ? translateModelPath : transcribeModelPath
        if let cached = engines[path] { return cached }

        DispatchQueue.main.async { self.status = .loadingModel }
        guard let e = WhisperEngine(modelPath: path) else {
            DispatchQueue.main.async {
                self.status = .error("Could not load model at \(path)")
            }
            return nil
        }
        engines[path] = e
        DispatchQueue.main.async {
            if self.isRunning { self.status = .live }
        }
        return e
    }

    func start() {
        guard !isRunning else { return }
        let translate = translateToEnglish
        status = .loadingModel

        inferenceQueue.async { [weak self] in
            guard let self else { return }
            guard self.engineFor(translate: translate) != nil else { return }
            DispatchQueue.main.async { self.status = .starting }

            Task {
                do {
                    try await self.capture.start()
                    DispatchQueue.main.async {
                        self.isRunning = true
                        self.status = .live
                        self.startTimer()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.status = .error(Self.friendlyCaptureError(error))
                    }
                }
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        Task { await capture.stop() }
        bufferLock.lock()
        buffer.removeAll()
        bufferLock.unlock()
        isRunning = false
        status = .idle
        if !partial.isEmpty {
            committed.append(partial)
            partial = ""
        }
    }

    func clear() {
        committed.removeAll()
        partial = ""
    }

    // MARK: - Inference loop

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: inferenceQueue)
        t.schedule(deadline: .now() + 1.0, repeating: 1.2)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        guard !inferenceBusy else { return }
        let translate = DispatchQueue.main.sync { translateToEnglish }
        guard let engine = engineFor(translate: translate) else { return }

        bufferLock.lock()
        let window = buffer
        bufferLock.unlock()

        guard window.count >= minSamples else { return }

        let trailing = Array(window.suffix(sampleRate * 7 / 10)) // last 0.7 s
        let trailingSilent = Self.rms(trailing) < silenceRMS
        let wholeWindowSilent = Self.rms(window) < silenceRMS

        // Pure silence: don't waste GPU cycles, just trim the buffer.
        if wholeWindowSilent {
            consume(window.count - sampleRate / 4)
            DispatchQueue.main.async {
                if !self.partial.isEmpty {
                    self.committed.append(self.partial)
                    self.partial = ""
                }
            }
            return
        }

        inferenceBusy = true
        let segments = engine.run(samples: window, translate: translate)
        inferenceBusy = false

        let step = plan(segments: segments, windowCount: window.count, trailingSilent: trailingSilent)
        if step.consume > 0 { consume(step.consume) }
        DispatchQueue.main.async {
            // Skip exact repeats — a stuck Whisper sometimes emits the same line twice.
            if let line = step.commit, line != self.committed.last { self.committed.append(line) }
            if self.committed.count > 300 {
                self.committed.removeFirst(self.committed.count - 300)
            }
            self.partial = step.partial
        }
    }

    /// Decides what to commit to the transcript, how much audio to drop, and
    /// what stays as the live line.
    /// - Speaker paused → commit everything.
    /// - Long stretch without a pause → commit the sentences Whisper has already
    ///   finished and keep the unfinished rest live, so lines end at sentence
    ///   boundaries instead of mid-sentence.
    /// - Hard cap reached (non-stop talking) → commit everything regardless.
    func plan(segments: [WhisperEngine.Segment], windowCount: Int,
              trailingSilent: Bool) -> (commit: String?, consume: Int, partial: String) {
        func clean(_ segs: ArraySlice<WhisperEngine.Segment>) -> String {
            segs.map(\.text).filter { !HallucinationFilter.isFake($0) }.joined(separator: " ")
        }
        let all = clean(segments[...])

        if windowCount >= hardCommitSamples ||
           (trailingSilent && windowCount >= silenceCommitSamples && !segments.isEmpty) {
            return (all.isEmpty ? nil : all, windowCount, "")
        }
        // Split only after a segment that ends a sentence (Whisper's other segment
        // breaks can fall mid-sentence), and only where the next segment's
        // timestamp is plausible — a bad one would drop or repeat audio.
        if windowCount >= splitSamples,
           let cut = segments.indices.dropLast().last(where: {
               segments[$0].text.last.map { ".?!…".contains($0) } ?? false
           }) {
            let next = segments[cut + 1].start
            if next >= sampleRate && next < windowCount {
                let done = clean(segments[...cut])
                return (done.isEmpty ? nil : done, next, clean(segments[(cut + 1)...]))
            }
        }
        return (nil, 0, all)
    }

    /// Drops the first `count` samples from the shared buffer.
    private func consume(_ count: Int) {
        bufferLock.lock()
        buffer.removeFirst(min(count, buffer.count))
        bufferLock.unlock()
    }

    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var acc: Float = 0
        for s in samples { acc += s * s }
        return (acc / Float(samples.count)).squareRoot()
    }

    private static func friendlyCaptureError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" || ns.code == -3801 {
            return "Screen & audio recording permission needed. Open System Settings → Privacy & Security → Screen & System Audio Recording, enable Mimo, then press Start again."
        }
        return ns.localizedDescription
    }
}
