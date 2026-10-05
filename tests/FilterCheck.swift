// Self-check for HallucinationFilter. Run: tests/check.sh
@main struct FilterCheck {
    static func main() {
        let fake = [
            "Thanks for watching!", "Thank you for watching.", "[Music]", "(Musik)",
            "*Applaus*", "♪♪", "...", "you", "Untertitel im Auftrag des ZDF, 2021",
            "Untertitel der Amara.org-Community", "Vielen Dank fürs Zuschauen!",
            "Subtitles by the Amara.org community", "[BLANK_AUDIO]",
        ]
        let real = [
            "Good morning everyone.", "Thank you.", "See you next week.",
            "Can you share your screen?", "Wir schauen uns die Zahlen an.",
            "The new version will be released next week.",
        ]
        for t in fake { assert(HallucinationFilter.isFake(t), "should drop: \(t)") }
        for t in real { assert(!HallucinationFilter.isFake(t), "should keep: \(t)") }
        print("HallucinationFilter: \(fake.count + real.count) checks passed")
    }
}
