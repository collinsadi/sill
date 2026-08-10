import SwiftUI

/// The completion affordance. The thing people touch most and the emotional payload of the
/// app, so it gets more craft than everything around it combined. At rest it is a meniscus:
/// a ring of surface tension. Completed is a bead of liquid with a crest of light on its
/// upper curve and a mark left in it, not a tick drawn on top of it.
struct ControlView: View {
    enum State { case idle, hover, completed, overdue }
    var state: State
    /// Drives the bloom. Runs once on completion and never repeats.
    var bloom: Double = 0

    var body: some View {
        ZStack {
            // The melt: accent blooms once from the control outward, then is gone.
            if bloom > 0 {
                Circle()
                    .stroke(Tokens.accent, lineWidth: 1.5)
                    .scaleEffect(1 + bloom * 1.6)
                    .opacity(0.55 * (1 - bloom))
            }

            switch state {
            case .completed:
                Circle()
                    .fill(Tokens.controlComplete)
                    .overlay(
                        // The crest of light on the upper curve, which is what turns a flat
                        // disc into a bead.
                        Circle()
                            .trim(from: 0.55, to: 0.95)
                            .stroke(Color.white.opacity(0.45), lineWidth: 1.2)
                            .blur(radius: 0.4)
                            .padding(1)
                    )
                    .overlay(Checkmark().stroke(Tokens.hardware,
                                                style: .init(lineWidth: 1.9,
                                                             lineCap: .round,
                                                             lineJoin: .round))
                        .padding(4.6))
            case .idle:
                Circle().strokeBorder(Tokens.controlRing, lineWidth: Tokens.Geo.controlStroke)
            case .hover:
                Circle().strokeBorder(Tokens.controlRingHover, lineWidth: Tokens.Geo.controlStroke)
            case .overdue:
                Circle().strokeBorder(Tokens.attention, lineWidth: Tokens.Geo.controlStroke)
            }
        }
        .frame(width: Tokens.Geo.control, height: Tokens.Geo.control)
    }
}

private struct Checkmark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY + r.height * 0.06))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.32, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

/// One todo. Three levels of hierarchy and not one fill: title, due date, and state carried
/// by the control plus the title's luminance. There is no divider between rows, because
/// distance does that job, which is the whole point of a 48pt row.
struct RowView: View {
    var todo: Todo
    var isHovered: Bool
    var isFocused: Bool
    var bloom: Double
    var isEditing: Bool
    var isPickingDate: Bool
    var onToggle: () -> Void
    var onBeginEdit: () -> Void
    var onCommitEdit: (String) -> Void
    var onCancelEdit: () -> Void
    var onTapDate: () -> Void
    var onPickDate: (Date) -> Void
    var onSnooze: (Date) -> Void
    var onDelete: () -> Void

    @State private var draft: String = ""
    @FocusState private var editing: Bool

    private var controlState: ControlView.State {
        if todo.isCompleted { return .completed }
        if todo.isOverdue { return .overdue }
        // Focus is strictly stronger than hover: the keyboard state must never read as
        // weaker than the pointer state.
        return (isHovered || isFocused) ? .hover : .idle
    }

    private var titleColor: Color {
        todo.isCompleted ? Tokens.textTertiary : Tokens.textPrimary
    }

    private var dueColor: Color {
        if todo.isOverdue { return Tokens.attention }
        return isHovered ? Tokens.textSecondary : Tokens.textTertiary
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Tokens.Space.s12) {
                // Focus lives out in the panel's padding gutter, so it never shifts content
                // and it is the only accent on the screen while it is showing.
                Capsule()
                    .fill(Tokens.accent)
                    .frame(width: 2, height: 22)
                    .opacity(isFocused ? 1 : 0)
                    .offset(x: -Tokens.Space.s16)
                    .frame(width: 0)
                // Optical lift: cap height sits above the line box centre, so mathematical
                // centring makes the control look low.
                ControlView(state: controlState, bloom: bloom)
                    .padding(.bottom, Tokens.Space.s2)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onToggle)

                if isEditing {
                    // Inline, not a detail expansion. The panel is not a window and a detail
                    // view would be a second screen inside something that has no screens.
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .font(Tokens.body(Tokens.TypeSize.bodyRow))
                        .foregroundStyle(Tokens.textPrimary)
                        .tint(Tokens.accent)
                        .focused($editing)
                        .onSubmit { onCommitEdit(draft) }
                        .onExitCommand(perform: onCancelEdit)
                        .onAppear { draft = todo.title; editing = true }
                } else {
                    Text(todo.title)
                        .font(Tokens.body(Tokens.TypeSize.bodyRow))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onBeginEdit)
                }

                Text(todo.due.map(Self.stamp) ?? (isHovered ? "add date" : ""))
                    .font(Tokens.mono(Tokens.TypeSize.monoStamp))
                    .foregroundStyle(todo.due == nil ? Tokens.textTertiary : dueColor)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTapDate)
            }
            .frame(height: Tokens.Geo.rowHeight)

            if isPickingDate {
                WeekStrip(selected: todo.due, onPick: onPickDate)
                    .padding(.bottom, Tokens.Space.s8)
            }
        }
        .contextMenu {
            // Words, not icons. An icon earns its place only where a word cannot do the job.
            Button("Snooze to tomorrow") { onSnooze(Self.tomorrow9am()) }
            Button("Snooze to next week") { onSnooze(Self.nextWeek9am()) }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    /// Tabular by construction: DM Mono is monospaced, so a changing date never shifts
    /// anything horizontally.
    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(date) ? "'Today' HH:mm" : "EEE HH:mm"
        return f.string(from: date)
    }

    static func tomorrow9am() -> Date {
        let cal = Calendar.current
        let d = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
    }
    static func nextWeek9am() -> Date {
        let cal = Calendar.current
        let d = cal.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
    }
}
