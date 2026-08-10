import SwiftUI

/// What lives inside the panel once it has settled.
///
/// Content fades in over the BACK HALF of the settle only, never during the fall, so the
/// panel arrives as an object rather than as a container that filled up on the way down.
struct PanelContentView: View {
    var store: TodoStore
    @Bindable var state: PanelState
    var progress: Double
    var isExpanded: Bool
    @State private var hoveredID: UUID?
    @State private var datePickingID: UUID?
    @State private var bloomID: UUID?
    @State private var bloom: Double = 0
    @State private var snoozeNote: String?
    @State private var draft: String = ""
    @FocusState private var captureFocused: Bool

    private var reveal: Double {
        // Nothing until the drop has landed, then a short fade.
        max(0, min(1, (progress - 0.72) / 0.28))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s36) {
            captureField
            if store.visible.isEmpty {
                emptyState
            } else {
                list
            }
            Spacer(minLength: 0)
            if let note = snoozeNote {
                footer(note)
            } else if let done = store.lastCompleted {
                footer("Completed \u{201C}\(done.title)\u{201D}.", undo: store.undoLastCompletion)
            }
        }
        .padding(.horizontal, Tokens.Space.s28)
        .padding(.top, Tokens.Space.s28)
        .padding(.bottom, Tokens.Space.s28)
        .opacity(reveal)
    }

    /// Type, a caret, and one hairline. No container: a filled input inside a black panel is
    /// a rectangle floating in the bezel and the illusion dies instantly.
    private var captureField: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            TextField("", text: $draft, prompt:
                Text("Add a todo").foregroundStyle(Tokens.textSecondary))
                .textFieldStyle(.plain)
                .font(Tokens.body(Tokens.TypeSize.bodyCapture))
                .foregroundStyle(Tokens.textPrimary)
                .tint(Tokens.accent)
                .focused($captureFocused)
                .onSubmit(commit)
            Rectangle().fill(Tokens.hairline).frame(height: 1)
        }
        .onChange(of: isExpanded) { _, open in
            // The field is focused the instant the panel settles. There is nothing to click.
            state.captureFocused = open
            captureFocused = open
        }
        .onChange(of: state.captureFocused) { _, want in captureFocused = want }
        .onChange(of: captureFocused) { _, has in
            // Clicking into the field takes focus back off any row.
            if has { state.focusedRowID = nil }
        }
        .onChange(of: state.snoozeRequestID) { _, id in
            guard let id, let todo = store.visible.first(where: { $0.id == id }) else { return }
            snooze(todo, until: RowView.tomorrow9am())
            state.snoozeRequestID = nil
            state.focusedRowID = nil
            state.captureFocused = true
        }
        .onAppear { captureFocused = isExpanded }
    }

    /// Text commits the moment Return is pressed. Nothing waits on anything, and the cheap
    /// local date parse happens inline. Enrichment from the model arrives later and only
    /// ever refines a todo that already exists.
    /// The melt. Accent blooms once from the control outward and the row settles.
    /// One bloom, one accent, and it never repeats.
    private func complete(_ todo: Todo) {
        bloomID = todo.id
        bloom = 0
        withAnimation(Motion.rowComplete.animation) { bloom = 1 }
        store.complete(todo.id)
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            bloom = 0
            bloomID = nil
        }
    }

    /// Deferring is not deleting, so the app says where the thing went.
    private func snooze(_ todo: Todo, until date: Date) {
        store.snooze(todo.id, until: date)
        let f = DateFormatter(); f.dateFormat = "EEEE HH:mm"
        snoozeNote = "Snoozed to \(f.string(from: date))."
        Task {
            try? await Task.sleep(nanoseconds: UInt64(TodoStore.completionGrace * 1_000_000_000))
            snoozeNote = nil
        }
    }

    private func commit() {
        let raw = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let parsed = DateParser.parse(raw)
        store.add(title: parsed.title, due: parsed.due)
        draft = ""
    }

    private var emptyState: some View {
        VStack(spacing: Tokens.Space.s6) {
            Text("Nothing on the list.")
                .font(Tokens.display(Tokens.TypeSize.displayEmpty))
                .foregroundStyle(Tokens.textPrimary)
            Text("Type above to add the first one.")
                .font(Tokens.body(Tokens.TypeSize.bodyRow))
                .foregroundStyle(Tokens.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tokens.Space.s48)
    }

    /// One line, at the bottom, for everything that needs confirming. Completion and snooze
    /// share it so there is a single place where the app tells you what just happened, and it
    /// always names the thing rather than saying only "Undo".
    private func footer(_ text: String, undo: (() -> Void)? = nil) -> some View {
        HStack(spacing: Tokens.Space.s8) {
            Text(text)
                .font(Tokens.body(Tokens.TypeSize.labelMeta))
                .foregroundStyle(Tokens.textTertiary)
                .lineLimit(1)
            if let undo {
                Button("Undo", action: undo)
                    .buttonStyle(.plain)
                    .font(Tokens.body(Tokens.TypeSize.labelMeta))
                    .foregroundStyle(Tokens.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .transition(.opacity)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(store.visible) { todo in
                RowView(todo: todo,
                        isHovered: hoveredID == todo.id,
                        isFocused: state.focusedRowID == todo.id,
                        bloom: bloomID == todo.id ? bloom : 0,
                        isEditing: state.editingRowID == todo.id,
                        isPickingDate: datePickingID == todo.id,
                        onToggle: { complete(todo) },
                        onBeginEdit: { state.editingRowID = todo.id; datePickingID = nil },
                        onCommitEdit: { new in
                            let t = new.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !t.isEmpty { store.updateTitle(todo.id, to: t) }
                            state.editingRowID = nil
                        },
                        onCancelEdit: { state.editingRowID = nil },
                        onTapDate: {
                            datePickingID = datePickingID == todo.id ? nil : todo.id
                            state.editingRowID = nil
                        },
                        onPickDate: { d in
                            store.setDue(todo.id, to: d)
                            datePickingID = nil
                        },
                        onSnooze: { d in snooze(todo, until: d) },
                        onDelete: { store.delete(todo.id) })
                    .onHover { hoveredID = $0 ? todo.id : (hoveredID == todo.id ? nil : hoveredID) }
            }
        }
    }
}

/// Light authored onto the surfaces that face it: each shoulder, its corner, and the cove,
/// tapering down the vertical with a round cap. The long straight sides carry nothing,
/// because a vertical edge lit from above catches nothing. A faint continuous line on the
/// underside is bounce from the desktop, and that is what makes the lower boundary readable
/// over a black wallpaper without becoming a border.
struct SpecularOverlay: View {
    var geometry: Silhouette.Geometry
    var insetX: CGFloat
    var progress: Double

    var body: some View {
        Canvas { ctx, _ in
            guard progress > 0.75 else { return }
            let a = min(1, (progress - 0.75) / 0.25)
            let midX = insetX + geometry.panelWidth / 2
            let left = midX - geometry.panelWidth / 2
            let right = midX + geometry.panelWidth / 2
            let nl = midX - geometry.hostWidth / 2
            let nr = midX + geometry.hostWidth / 2
            let nh = geometry.hostHeight
            let r = geometry.hardwareRadius
            let c = geometry.meniscusRadius
            let bottom = geometry.panelHeight

            var shoulders = Path()
            shoulders.move(to: CGPoint(x: left, y: nh + 42))
            shoulders.addLine(to: CGPoint(x: left, y: nh + r))
            shoulders.addArc(tangent1End: CGPoint(x: left, y: nh),
                             tangent2End: CGPoint(x: left + r, y: nh), radius: r)
            shoulders.addLine(to: CGPoint(x: nl - c, y: nh))
            shoulders.addArc(center: CGPoint(x: nl - c, y: nh - c), radius: c,
                             startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)

            var shouldersR = Path()
            shouldersR.move(to: CGPoint(x: right, y: nh + 42))
            shouldersR.addLine(to: CGPoint(x: right, y: nh + r))
            shouldersR.addArc(tangent1End: CGPoint(x: right, y: nh),
                              tangent2End: CGPoint(x: right - r, y: nh), radius: r)
            shouldersR.addLine(to: CGPoint(x: nr + c, y: nh))
            shouldersR.addArc(center: CGPoint(x: nr + c, y: nh - c), radius: c,
                              startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)

            var corners = Path()
            corners.move(to: CGPoint(x: left, y: bottom - 42))
            corners.addLine(to: CGPoint(x: left, y: bottom - r))
            corners.addArc(tangent1End: CGPoint(x: left, y: bottom),
                           tangent2End: CGPoint(x: left + r, y: bottom), radius: r)
            corners.addLine(to: CGPoint(x: left + 52, y: bottom))
            corners.move(to: CGPoint(x: right, y: bottom - 42))
            corners.addLine(to: CGPoint(x: right, y: bottom - r))
            corners.addArc(tangent1End: CGPoint(x: right, y: bottom),
                           tangent2End: CGPoint(x: right - r, y: bottom), radius: r)
            corners.addLine(to: CGPoint(x: right - 52, y: bottom))

            var bounce = Path()
            bounce.move(to: CGPoint(x: left + 14, y: bottom))
            bounce.addLine(to: CGPoint(x: right - 14, y: bottom))

            let style = StrokeStyle(lineWidth: Tokens.Geo.edgeWeight, lineCap: .round)
            ctx.stroke(bounce, with: .color(Tokens.edgeSpecularSoft.opacity(a)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round))
            for p in [shoulders, shouldersR, corners] {
                ctx.stroke(p, with: .color(Tokens.edgeSpecular.opacity(a)), style: style)
            }
        }
        .allowsHitTesting(false)
    }
}
