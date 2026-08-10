import SwiftUI

/// Seven columns, tabular figures, one click.
///
/// Deliberately not a month grid: a calendar shrunk into a 344pt column is unreadable, and
/// a scaled down calendar is the clearest possible sign that nobody thought about the
/// constraint. Anything further out than a week is typed, which is why the inline path exists.
/// The same control serves both deadlines and snooze, so it is learned once and used twice.
struct WeekStrip: View {
    var selected: Date?
    var onPick: (Date) -> Void

    private var days: [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.timeIntervalSince1970) { day in
                let isSelected = selected.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
                VStack(spacing: Tokens.Space.s4) {
                    Text(Self.letter(day))
                        .font(Tokens.mono(Tokens.TypeSize.monoStamp))
                        .foregroundStyle(Tokens.textTertiary)
                    Text(Self.number(day))
                        .font(Tokens.mono(Tokens.TypeSize.bodyRow))
                        .foregroundStyle(isSelected ? Tokens.accent : Tokens.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Nine in the morning is the assumption. Anything else is typed.
                    let at = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
                    onPick(at)
                }
            }
        }
    }

    private static func letter(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEEE"; return f.string(from: d)
    }
    private static func number(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: d)
    }
}
