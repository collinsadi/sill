import Foundation

/// Pulls a date out of natural language and hands back the title with the date phrase removed.
///
/// This runs locally and instantly. It is NOT the AI layer: capture must never wait on a
/// model, so the cheap deterministic parse happens on the keystroke that commits, and the
/// model only ever refines what is already a working todo.
enum DateParser {

    struct Result {
        var title: String
        var due: Date?
    }

    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue)

    static func parse(_ input: String) -> Result {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Result(title: trimmed, due: nil) }
        guard let detector else { return Result(title: trimmed, due: nil) }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let matches = detector.matches(in: trimmed, options: [], range: range)

        // Take the last match: "email Sam about the invoice before Friday" puts the date at
        // the end, and a leading match is far more likely to be part of the subject.
        guard let match = matches.last, let date = match.date,
              let r = Range(match.range, in: trimmed) else {
            return Result(title: trimmed, due: nil)
        }

        var title = trimmed
        title.removeSubrange(r)
        // Tidy the connective words the date phrase left behind.
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for tail in ["before", "on", "at", "by", "due", "next"] {
            if title.lowercased().hasSuffix(" " + tail) {
                title = String(title.dropLast(tail.count + 1))
            }
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        return Result(title: title.isEmpty ? trimmed : title, due: date)
    }
}
