import Foundation
import Observation

struct Todo: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var due: Date?
    var completedAt: Date?
    var snoozedUntil: Date?
    var createdAt: Date = Date()
    /// A single lowercase word from the model, shown as a chip.
    var tag: String?
    /// True while the model's guess is unconfirmed. It looks different until you accept or
    /// touch it, because silent guessing is how people stop trusting the feature.
    var dueUnconfirmed: Bool = false

    var isCompleted: Bool { completedAt != nil }
    var isOverdue: Bool {
        guard !isCompleted, let due else { return false }
        return due < Date()
    }
}

/// Codable with atomic writes rather than SwiftData. A todo list is a small array, and
/// SwiftData buys a schema migration surface and a version risk we have no use for here.
@MainActor
@Observable
final class TodoStore {

    private(set) var todos: [Todo] = []

    /// A completed todo holds its place before leaving, so nothing reflows while you are
    /// still looking at it. After that the undo line names what it is undoing, because an
    /// undo that says only "Undo" is asking you to remember.
    private(set) var lastCompleted: Todo?
    static let completionGrace: Double = 5.0
    private var graceTask: Task<Void, Never>?

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Sill", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            self.fileURL = base.appendingPathComponent("todos.json")
        }
        load()
    }

    // MARK: Reading

    /// What the panel shows: not completed, not snoozed into the future, newest first.
    var visible: [Todo] {
        let now = Date()
        let grace = lastCompleted?.id
        return todos
            .filter { $0.completedAt == nil || $0.id == grace }
            .filter { ($0.snoozedUntil ?? .distantPast) <= now }
            .sorted { a, b in
                switch (a.due, b.due) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.createdAt > b.createdAt
                }
            }
    }

    var openCount: Int { visible.count }
    var hasOverdue: Bool { visible.contains(where: \.isOverdue) }

    // MARK: Writing

    /// Capture never waits on anything. The todo exists the moment this returns.
    @discardableResult
    func add(title: String, due: Date? = nil) -> Todo {
        let t = Todo(title: title, due: due)
        todos.insert(t, at: 0)
        scheduleSave()
        return t
    }

    func complete(_ id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].completedAt = Date()
        lastCompleted = todos[i]
        scheduleSave()

        graceTask?.cancel()
        graceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.completionGrace * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.lastCompleted = nil
        }
    }

    /// Everything is undoable and the undo says what it is undoing.
    func undoLastCompletion() {
        guard let t = lastCompleted else { return }
        graceTask?.cancel()
        uncomplete(t.id)
        lastCompleted = nil
    }

    func uncomplete(_ id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].completedAt = nil
        scheduleSave()
    }

    func updateTitle(_ id: UUID, to title: String) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].title = title
        scheduleSave()
    }

    func setDue(_ id: UUID, to date: Date?) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].due = date
        todos[i].dueUnconfirmed = false
        scheduleSave()
    }

    func snooze(_ id: UUID, until date: Date) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].snoozedUntil = date
        scheduleSave()
    }

    /// Applies what the model returned to a todo that already exists. Never creates one,
    /// never blocks capture, and never overwrites a value the user has since edited.
    func applyEnrichment(_ e: Enrichment, to id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        if let t = e.title, !t.isEmpty { todos[i].title = t }
        if todos[i].due == nil, let d = e.due {
            todos[i].due = d
            todos[i].dueUnconfirmed = e.dueInferred
        }
        if let tag = e.tag { todos[i].tag = tag }
        scheduleSave()
    }

    /// One click confirms the guess. The user's correction is final and the model does not
    /// get to revise it.
    func confirmDue(_ id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].dueUnconfirmed = false
        scheduleSave()
    }

    func delete(_ id: UUID) {
        todos.removeAll { $0.id == id }
        scheduleSave()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        todos = (try? decoder.decode([Todo].self, from: data)) ?? []
    }

    /// Debounced. Flushed synchronously on terminate so nothing is lost on quit.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(todos) else { return }
        // Atomic: a half written file is worse than a stale one.
        try? data.write(to: fileURL, options: .atomic)
    }
}
