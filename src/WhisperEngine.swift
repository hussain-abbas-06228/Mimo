import Foundation

/// Thin wrapper around the whisper.cpp C API.
/// Loads a ggml model once and runs inference on chunks of 16 kHz mono Float32 audio.
final class WhisperEngine {
    private var ctx: OpaquePointer?

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
    }

    /// One phrase/sentence as Whisper split it. `start` is in samples from the
    /// beginning of the audio passed to `run`.
    struct Segment {
        let text: String
        let start: Int
    }

    /// Runs Whisper over the given samples.
    /// - translate: true → output English translation, false → transcript in the spoken language.
    /// - language: spoken language code ("de", "fr", …) or "auto" to detect it.
    func run(samples: [Float], translate: Bool, language: String) -> [Segment] {
        guard let ctx, samples.count >= 16000 else { return [] }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = translate
        params.n_threads = 4
        params.no_context = true
        params.single_segment = false
        params.suppress_blank = true
        params.suppress_nst = true    // no "(music)"-style non-speech tokens
        params.no_timestamps = false  // we need segment start times to split at sentence ends

        let status = language.withCString { lang in
            params.language = lang
            return samples.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
        }
        guard status == 0 else { return [] }

        return (0..<whisper_full_n_segments(ctx)).compactMap { i in
            guard let text = whisper_full_get_segment_text(ctx, i) else { return nil }
            return Segment(
                text: String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines),
                start: Int(whisper_full_get_segment_t0(ctx, i)) * 160)  // t0 is in 10 ms units
        }
    }
}
