import Foundation

/// What the model extracted. Everything is optional because a partial answer is still useful
/// and the todo already exists regardless.
struct Enrichment: Codable, Sendable, Equatable {
    var title: String?
    var due: Date?
    var tag: String?
    /// True when the model inferred the date rather than reading it explicitly. Unconfirmed
    /// is a visual state: silent guessing is how people stop trusting the feature.
    var dueInferred: Bool = false
}

/// The three designed failure states, returned as values rather than thrown. A designed state
/// should never arrive through a catch block, because that is how it ends up rendered as a
/// generic alert.
enum EnrichmentOutcome: Sendable, Equatable {
    case parsed(Enrichment)
    case failed(String)
    case unavailable(String)
}

/// Bridges to a locally authenticated Claude session.
///
/// It is local, which means it can be slow and it can be absent. Both are design states, not
/// edge cases, and the app stays a working todo list in all of them.
actor IntelligenceBridge {

    enum Phase: Sendable, Equatable { case idle, thinking, streaming }

    /// A GUI app does not inherit the shell PATH, so the binary is resolved explicitly.
    /// The symlink is resolved at call time because the version directory moves under us.
    private static let candidates = [
        "~/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "/usr/bin/claude"
    ]

    static func resolveBinary() -> URL? {
        for c in candidates {
            let path = (c as NSString).expandingTildeInPath
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            return FileManager.default.isExecutableFile(atPath: resolved.path)
                ? resolved : URL(fileURLWithPath: path)
        }
        return nil
    }

    private let timeout: Duration = .seconds(60)

    private static let prompt = """
    Extract structured data from this todo. Reply with ONLY a JSON object, no prose, no fences.
    Keys: title (string, the todo with any date phrase removed and tightened, keep the user's
    wording), due (ISO8601 datetime or null), tag (a single lowercase word or null),
    dueInferred (boolean, true only if you guessed the date rather than reading it explicitly).
    Todo:
    """

    /// Runs one enrichment. Cancellable, bounded by a wall clock timeout, and with tools
    /// disabled so a text parser can never touch the filesystem.
    func enrich(_ text: String, onPhase: @escaping @Sendable (Phase) -> Void) async -> EnrichmentOutcome {
        guard let binary = Self.resolveBinary() else {
            return .unavailable("Claude is not connected. Type /connect to set it up.")
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "-p", Self.prompt + " " + text,
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            "--allowedTools", "",
            // Parsing one line of text does not need a frontier model. Inheriting the
            // session default cost 0.16 USD and 4.7s per todo, which is indefensible.
            "--model", "haiku"
        ]
        let out = Pipe()
        process.standardOutput = out
        // Discarded at the OS level rather than through a pipe. An undrained pipe deadlocks
        // the child once its buffer fills, and draining it with a blocking read inside a Task
        // starves the cooperative pool, which deadlocks us instead.
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .unavailable("Claude is not connected. Type /connect to set it up.")
        }

        onPhase(.thinking)

        let work = Task { () -> EnrichmentOutcome in
            var sawContent = false
            var assembled = ""
            var streamed = ""
            do {
                for try await line in out.fileHandleForReading.bytes.lines {
                    guard !Task.isCancelled else { break }
                    guard let data = line.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { continue }

                    // First token back flips thinking into streaming. The distinction is real:
                    // thinking means nothing has arrived, streaming means results are landing.
                    if !sawContent, Self.carriesContent(obj) {
                        sawContent = true
                        onPhase(.streaming)
                    }
                    if let result = obj["result"] as? String { assembled = result }
                    // Accumulate streamed text so a missing result event is survivable.
                    if let event = obj["event"] as? [String: Any],
                       let delta = event["delta"] as? [String: Any],
                       let text = delta["text"] as? String {
                        streamed += text
                    }
                }
            } catch {
                return .failed("Could not reach Claude. The todo saved exactly as you typed it.")
            }
            // Fall back to the assembled assistant text when no result event arrived.
            guard let e = Self.decode(assembled) ?? Self.decode(streamed) else {
                return .failed("Could not reach Claude. The todo saved exactly as you typed it.")
            }
            return .parsed(e)
        }

        let guard_ = Task {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { work.cancel(); process.terminate() }
        }
        let outcome = await work.value
        guard_.cancel()
        process.terminate()
        return outcome
    }

    private static func carriesContent(_ obj: [String: Any]) -> Bool {
        if obj["type"] as? String == "stream_event" { return true }
        if obj["type"] as? String == "assistant" { return true }
        return false
    }

    /// The model returns a bare date as often as a datetime, and ISO8601DateFormatter
    /// rejects a bare date outright, so every date would silently vanish without this.
    /// A date with no time means nine in the morning, matching the week strip.
    static func parseDate(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }
        if let d = ISO8601DateFormatter().date(from: raw) { return d }

        let dayOnly = DateFormatter()
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        dayOnly.timeZone = .current
        dayOnly.dateFormat = "yyyy-MM-dd"
        if let d = dayOnly.date(from: raw) {
            return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
        }

        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return local.date(from: raw)
    }

    /// Lenient on purpose: a model that wraps JSON in prose should not cost the user a todo.
    private static func decode(_ raw: String) -> Enrichment? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") else { return nil }
        let slice = String(raw[start...end])
        guard let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var e = Enrichment()
        e.title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        e.tag = (obj["tag"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        e.dueInferred = obj["dueInferred"] as? Bool ?? false
        if let due = obj["due"] as? String, !due.isEmpty {
            e.due = Self.parseDate(due)
        }
        if e.title?.isEmpty == true { e.title = nil }
        if e.tag?.isEmpty == true { e.tag = nil }
        return e
    }
}
