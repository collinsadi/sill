import SwiftUI

/// A compact reminder that never becomes the full panel.
///
/// One thing, three actions, words rather than icons because no icon beats the word Snooze.
/// It retreats on its own after six seconds. Two or five reminders, it never stacks: it shows
/// the most urgent and counts the rest, because five peeks is five interruptions.
struct PeekView: View {
    var scheduler: ReminderScheduler
    var store: TodoStore
    var progress: Double

    private var reveal: Double { max(0, min(1, (progress - 0.72) / 0.28)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            if let todo = scheduler.active {
                Text(todo.title)
                    .font(Tokens.body(Tokens.TypeSize.bodyRow))
                    .foregroundStyle(Tokens.textPrimary)
                    .lineLimit(1)

                Text("due now")
                    .font(Tokens.mono(Tokens.TypeSize.monoStamp))
                    .foregroundStyle(Tokens.attention)

                if scheduler.queued > 0 {
                    Text("\(scheduler.queued) more came due")
                        .font(Tokens.body(Tokens.TypeSize.labelMeta))
                        .foregroundStyle(Tokens.textTertiary)
                }

                HStack(spacing: Tokens.Space.s16) {
                    action("Complete", "\u{21A9}") {
                        store.complete(todo.id)
                        scheduler.resolve(todo.id)
                    }
                    action("Snooze", "S") {
                        store.snooze(todo.id, until: RowView.tomorrow9am())
                        scheduler.resolve(todo.id)
                    }
                    action("Open", "O") { scheduler.dismissPeek() }
                }
                .padding(.top, Tokens.Space.s4)
            }
        }
        .padding(.horizontal, Tokens.Space.s28)
        .padding(.top, Tokens.Space.s20)
        .opacity(reveal)
    }

    private func action(_ word: String, _ key: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: Tokens.Space.s4) {
                Text(word)
                    .font(Tokens.body(Tokens.TypeSize.bodyRow))
                    .foregroundStyle(Tokens.textSecondary)
                Text(key)
                    .font(Tokens.mono(Tokens.TypeSize.monoStamp))
                    .foregroundStyle(Tokens.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
