import Foundation

/// Whisper sometimes invents text during silence, music or noise — mostly
/// phrases from the YouTube/TV subtitles it was trained on. None of them belong
/// in a meeting transcript, so matching lines are dropped.
enum HallucinationFilter {
    /// A line containing any of these (after normalising) is dropped.
    static let fragments = [
        "for watching", "subscribe to", "like and subscribe",
        "subtitles by", "amara org", "transcribed by", "translated by",
        "untertitel im auftrag", "untertitel der amara", "untertitel von",
        "untertitelung", "fürs zuschauen", "für s zuschauen", "fürs zusehen",
        "copyright wdr", "copyright swr",
    ]
    /// A line that is exactly one of these is dropped.
    static let wholeLines: Set<String> = [
        "you", "bye", "music", "musik", "applause", "applaus",
        "silence", "stille", "blank audio",
    ]

    static func isFake(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Sound annotations like "[Music]", "(Musik)", "*Applaus*", "♪♪".
        if let first = t.first, let last = t.last,
           "[(*♪♫".contains(first), "])*♪♫".contains(last) {
            return true
        }
        let n = normalize(t)
        return n.isEmpty || wholeLines.contains(n) || fragments.contains { n.contains($0) }
    }

    /// Lowercased, punctuation turned into spaces, whitespace collapsed.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ")
            .joined(separator: " ")
    }
}
