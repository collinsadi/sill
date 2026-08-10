# Sill — architecture

Six layers. Dependencies point downward only. No layer below Views knows SwiftUI exists,
and Views know nothing about how the window works.

```
Views          SwiftUI. Store driven. Window ignorant.
  |
Render         MorphShape, Metaball, SpecularOverlay.   <- profiled and swappable in isolation
  |
Store          Todos, persistence, undo.        Intelligence   (actor)
  |                                             Scheduling     (reminders, escalation, quiet hours)
Window         NSPanel, notch geometry, screen observation, hit testing.   Pure AppKit.
```

## 1. Window layer — AppKit only, zero app logic

- `NotchPanel: NSPanel` — overrides `canBecomeKey` and `canBecomeMain` to return `true`.
  Without this the capture field silently refuses keystrokes and it reads like a SwiftUI bug.
  `hasShadow = false`, because the design's shadow is drawn in content onto the wallpaper and
  the AppKit one would fight it. `.floating` level above the menu bar,
  `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`.
- `ScreenGeometry` — derives the notch from `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`.
  The notch is the gap between them. Nothing is hardcoded. Returns `.notched(rect)` or `.flat`,
  and the flat case is a first-class path from day one, not a later bolt-on.
- `ScreenObserver` — `NSApplication.didChangeScreenParametersNotification` for display changes,
  lid close, and resolution switches.
- `LSUIElement = true` in Info.plist so there is no Dock icon.

The window layer exposes a frame and accepts a hit-test mask. It never decides what to draw.

## 2. Render layer

- `MorphShape(phase:)` — the silhouette as a pure function of a 0...1 phase, producing one `Path`.
  Bead, bulge, neck, detach and settle are samples along it, not five separate assets.
- `MetaballRenderer` protocol with two conforming implementations:
  `CanvasMetaball` (blur then `GraphicsContext.Filter.alphaThreshold`) and
  `ShaderMetaball` (`.layerEffect` with a Metal threshold). Built Canvas first, measured at M1,
  swapped only if the numbers demand it.
- `SpecularOverlay` — the authored light paths. Shoulder, cove, bottom corners, underside bounce.

Isolating this behind a protocol is the point: the morph is the reason the product exists, so it
has to be measurable and replaceable without touching anything else.

## 3. Store

- `TodoStore` — `@MainActor @Observable`. CRUD, ordering, and a typed undo stack where every
  entry carries its own user-facing description, so the UI never has to compose "Undo what".
- `Persistence` — `Codable` to `~/Library/Application Support/Sill/todos.json`, written
  atomically. Debounced, and flushed on `applicationWillTerminate` and on resign-active.

## 4. Intelligence — an actor

- `IntelligenceBridge: actor`. Resolves the `claude` binary explicitly, because a GUI app does
  not inherit the shell `PATH`. Resolves the symlink at call time, since the version directory
  moves under us.
- Spawns with `--print --output-format stream-json --include-partial-messages
  --json-schema <schema> --allowedTools ""`. Empty allowed tools means a text parser can never
  touch the filesystem.
- Every call is cancellable and carries a wall-clock timeout and an output cap.
  `--max-turns` does not exist in 2.1.226 and with `--print` plus no tools there is no loop to bound.
- Returns `.parsed`, `.failed`, or `.unavailable`. Those are the three designed failure states
  and they are the return type, not an error thrown into a catch block somewhere.

## 5. Scheduling

- `ReminderScheduler` — due detection, the escalation ladder, and its ceiling. Escalation stops
  permanently after the second step by design.
- Quiet hours is **app owned**. Focus state is not readable from a public API and we do not fake it.
  The system suppresses its own notifications; the in-notch channel is ours to hold back.
- `NotificationBridge` — `UNUserNotificationCenter` for the fallback when another space is
  active or the display is asleep.

## 6. Views

SwiftUI, driven by the store. `DesignTokens.swift` generated from the Figma variables: colors,
spacing, radii, the type ramp, and every motion token as a named `Animation`.

---

## The four decisions

**Persistence: `Codable` with atomic writes, not SwiftData.** A todo list is a small array and
SwiftData buys a schema migration surface and a version risk we have no use for at this size.

**Observation: `@Observable`.** Available unguarded at the 14.0 ceiling, no publisher
boilerplate, and per-property tracking so one row changing does not invalidate the whole list.

**Concurrency: Swift 6 language mode, full strict concurrency.** The probe already compiled
clean at `-swift-version 6`, so we start strict rather than retrofitting it later. Store is
`@MainActor`, the bridge is an `actor`, nothing crosses without being `Sendable`.

**Hit testing: fixed-size window, `hitTest` returns nil outside the drawn silhouette.**
Resizing an `NSPanel` every frame fights the animation and stutters, and the morph is the whole
product. The window sits at the union of the notch rect and the maximum expanded panel for the
entire session and never changes size. The mask is fed the **same `Path` the render layer draws**,
so the clickable region cannot drift from the visible one.

## Risks carried into the build

1. `Canvas` with a per-frame blur is the expensive path. Measured at M1 with real numbers before
   any optimisation, because the fix might be a design decision rather than a code one.
2. The panel must not steal focus when it appears for a reminder peek. `becomesKeyOnlyIfNeeded`,
   and the peek is explicitly non-key.
3. Unsandboxed plus `Process` means the binary path is user data. It gets validated before spawn.
