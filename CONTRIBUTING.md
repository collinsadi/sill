# Contributing

## The one rule

**No silent design deviation.** If something in the design is expensive, slow, or awkward to
implement, say so in the pull request. Do not substitute a fade for the morph, drop a state
because it is fiddly, or simplify a row because it was easier that way. A quiet downgrade is
the only change that will not be accepted.

If you think a design decision is wrong, argue it. That is welcome. Changing it without saying
so is not.

## Before you touch anything

Read `CLAUDE.md`. It records the toolchain lock and the API ceiling.

The installed Xcode does not change. Do not run `xcode-select --install`, `--switch` or
`--reset`, do not accept Xcode's "Update to recommended settings", and do not change
`objectVersion`, `SWIFT_VERSION` or `MACOSX_DEPLOYMENT_TARGET`. The SDK is what decides whether
something compiles, and it is older than the host OS, so `#available` will not rescue an API
that is not in the SDK.

## Adding files

The Xcode project is generated, not hand edited:

```sh
python3 tools/genproj.py
```

Add a `.swift`, `.metal` or `.ttf` under `Sill/` and rerun it. Never edit `project.pbxproj`
by hand, and never commit a change to it that `genproj.py` did not produce.

## Design rules that survive into code

These are enforced by review, not by the compiler:

- **One black.** `Tokens.hardware` is the only surface. No lighter fill may be used for
  elevation, anywhere, for any reason.
- **No literals.** Every colour, space, radius and type size comes from `Tokens`.
- **No em dashes in user facing strings.** Applies to every label, button, notification and
  error. Code comments are exempt.
- **No spinner.** Waiting is a meniscus travelling the waterline.
- **Text commits immediately.** Nothing in the capture path may wait on the network or a model.
- **One accent per screen.** If the accent is on five elements it is a second body colour.

## Before opening a pull request

1. It builds. Run it yourself and paste the result, since "should compile" is not a check.

   ```sh
   xcodebuild -project Sill.xcodeproj -scheme Sill -configuration Release build
   ```

2. Zero new warnings.
3. Run the app and use the thing you changed.
4. Confirm the toolchain is untouched:

   ```sh
   xcodebuild -version && xcrun --sdk macosx --show-sdk-version
   ```

5. If it differs from the design in any way, say so in the description.

## Tests

```sh
./tools/test.sh
```

Compiles the real source files together with the assertions, so a change in the app breaks
the test rather than the test drifting into a copy. There is no test target, because a second
target in a hand generated pbxproj is more fragile than it is worth.

Write them where they earn their place: date parsing, the escalation schedule, store
persistence and undo. Do not write tests for view layout.

## Commits

One line, imperative, one logical change. No long bodies.
