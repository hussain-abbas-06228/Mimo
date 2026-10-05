import Foundation

/// Thin wrapper around the whisper.cpp C API.
/// Loads a ggml model once and runs inference on chunks of 16 kHz mono Float32 audio.
final class WhisperEngine {
    private var ctx: OpaquePointer?
    private let language = strdup("de")

    init?(modelPath: String) {
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        guard let c = whisper_init_from_file_with_params(modelPath, cparams) else {
            return nil
        }
        ctx = c
    }

    deinit {
        if let ctx { whisper_free(ctx) }
        free(language)
    }

    /// Runs Whisper over the given samples.
    /// - translate: true → output English translation, false → German transcript.
    func run(samples: [Float], translate: Bool) -> String {
        guard let ctx, samples.count >= 16000 else { return "" }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = translate
        params.language = UnsafePointer(language)
        params.n_threads = 4
        params.no_context = true
        params.single_segment = false
        params.suppress_blank = true
        params.no_timestamps = true

        let status = samples.withUnsafeBufferPointer { buf in
            whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        }
        guard status == 0 else { return "" }

        var out = ""
        let n = whisper_full_n_segments(ctx)
        for i in 0..<n {
            if let text = whisper_full_get_segment_text(ctx, i) {
                out += String(cString: text)
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
