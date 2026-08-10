# Sill — build constraints

macOS notch todo app. Design lives in Figma file `ZWqBL9a3tCQ45MaK0sE7tg`.

## TOOLCHAIN LOCK — DO NOT MODIFY

The installed Xcode stays exactly as it is. We are a guest on this machine.

**Never run:** `xcode-select --install/--switch/--reset`, any Xcode or Command Line Tools
install/update/switch, Xcode's "Update to recommended settings", `brew upgrade` on anything
toolchain adjacent. Never change `objectVersion`, `SWIFT_VERSION`, `MACOSX_DEPLOYMENT_TARGET`,
or the project format version. Never add a Swift Package whose `swift-tools-version` exceeds
what is installed.

Verified 2026-08-10:

```
Xcode 16.4 (Build 16F6)
Apple Swift 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)
xcode-select -p  ->  /Applications/Xcode.app/Contents/Developer
macOS SDK        ->  15.5   (/Applications/Xcode.app/.../MacOSX15.5.sdk)
Host OS          ->  macOS 26.0 (25A354)
```

## THE API CEILING

**SDK 15.5 determines what compiles. Deployment target determines what runs.**
The host OS is 26.0 but the SDK is 15.5, so **no macOS 26 API will build**, `#available` or not.
Nothing in this design needs one.

Consequence worth keeping: an app built against the 15.5 SDK does **not** receive macOS 26
Liquid Glass restyling. That is desirable here. The design draws every surface itself and
forbids system materials.

Deployment target: **macOS 14.0**. Everything below compiles unguarded at that target.

Verified by actual compilation (`swiftc -typecheck -target arm64-apple-macos14.0 -swift-version 6`),
exit 0, no warnings:

| Feature | Since | Compiles at 14.0 | Guard needed |
|---|---|---|---|
| `@Observable` | 14.0 | yes | no |
| `PhaseAnimator` | 14.0 | yes | no |
| `.layerEffect` / `.distortionEffect` | 14.0 | yes | no |
| `SwiftData` | 14.0 | yes | no |
| `Canvas` + `GraphicsContext.Filter.alphaThreshold` | 12.0 | yes | no |
| `.scrollTargetBehavior` | 14.0 | yes | no |
| `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` | 12.0 | yes | no |
| `NSPanel.canBecomeKey` override | always | yes | no |
| Swift 6 language mode, strict concurrency | Swift 6.1.2 | yes | n/a |
| `MeshGradient` | **15.0** | yes | **`@available(macOS 15.0, *)`** |

`MeshGradient` is the only item above the deployment target, and the design does not use it.

**Every API decision for the rest of this build checks against this table.**

## CLAUDE CLI BRIDGE

Binary is **not** on a GUI app's `PATH`. Resolve explicitly and fail gracefully when absent.

```
/Users/0xadi/.local/bin/claude  ->  ~/.local/share/claude/versions/2.1.226
```

Confirmed flags in 2.1.226: `--print`, `--output-format {text,json,stream-json}`,
`--include-partial-messages`, `--json-schema`, `--allowedTools`, `--permission-mode`.

**`--max-turns` does not exist in 2.1.226.** Bound calls with a wall-clock timeout and an
output cap instead. With `--print` and `--allowedTools ""` there is no agentic loop to bound.

## LOCKED BUILD DECISIONS (2026-08-10, approved)

- **Unsandboxed.** Local utility, not Mac App Store. The app spawns `claude` directly: one hop,
  one failure mode, no XPC helper and no second crash domain.
- **Carbon `RegisterEventHotKey`** for the global hotkey. No permission prompt of any kind, so
  the hotkey works on first launch. `NSEvent.addGlobalMonitorForEvents` was rejected because it
  demands Input Monitoring, a System Settings trip, and a relaunch.
- **Hand-written `Sill.xcodeproj`, `objectVersion = 56`.** Xcode 16.4 opens this without ever
  offering "Update to recommended settings", which is the prompt the toolchain lock forbids.
  Gives a real app bundle for `LSUIElement`, Info.plist and entitlements.

## DESIGN RULES THAT SURVIVE INTO CODE

- One black. `Color.hardware` is `#000000` and is the only surface. No lighter surface may ever
  be used for elevation. Hierarchy is type, spacing, and hairlines only.
- Panel outer corner radius is the notch's own radius and does **not** grow with the panel.
- The one shadow falls on the wallpaper, never on the panel. `window.hasShadow = false`.
- Text commits on Return, immediately, always. Nothing waits on the model.
- No em dashes in any user-facing string. Applies to every label, button, notification, error.
- No spinner. Waiting is a meniscus travelling the waterline.
