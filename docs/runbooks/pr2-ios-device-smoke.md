# Deferred: PR 2 (Riverpod 3) — iOS device runtime smoke

**Status:** DEFERRED to next sprint per agreement on 2026-05-12.

**Why deferred:** On 2026-05-12 the connected iPhone was on iOS 26.4 but
Xcode 26.5 was the only SDK available locally. The debug-mode `flutter
run` produced a `dyld: Library not loaded: @rpath/Runner.debug.dylib`
on launch — Flutter's debug build embeds a debug VM dylib whose dyld
expectations can mismatch when the build SDK is a minor version ahead
of the device runtime.

PR 2 has all automated gates green (analyze clean, 1,465/1,465 tests
passing, Android APK + iOS simulator + iOS device builds all produce
artifacts). Only the eyes-on device walkthrough is deferred.

## When to retry

Any of these unblocks the smoke test:
1. iPhone updates to iOS 26.5 (matches the local SDK)
2. Xcode releases an iOS 26.4 SDK component (matches the device)
3. Switch to `flutter run --release` against the device (AOT compile
   skips the debug dylib entirely; loses hot reload but completes the
   smoke)

## What to verify

Walk through the 11-point checklist against the merged `chore/pr-2-riverpod-3`
state (or main once merged):

1. Cold boot — app reaches Home without crash
2. Auth/session restore (guest mode)
3. Auth/session restore (signed-in, if a test account exists)
4. Home load — recent scans + stack health cards populate
5. Search — type a brand/product, FTS results appear
6. Product detail — tap a product, detail screen + warnings render
7. Scan flow — open scan, scan or cancel; state transitions clean
8. Stack — open tab, products listed, tap-through works
9. Stack sync queue — signed-in only: add a supplement, kill data,
   restore, verify sync fires
10. Profile / Settings — modify a field, save, reopen, verify persisted
11. Hot reload — press `r` in the run terminal, completes <1s, no errors

## Riverpod 3 silent behaviour watch list

Confirmed during automated gates but only observable on a running app:

- **Auto-retry on FutureProvider failures**: 16 sites. If an error
  state now flickers/retries that didn't before, note it.
- **`==` equality update filtering**: replaces `identical` in some
  paths. May change rebuild frequency.
- **StreamProvider pausing when listeners pause**: 2 sites. If something
  that should update in real-time (online/offline) doesn't, that's the
  symptom.
- **Notifier instance recreated on rebuild**: 2 sites. Both inspected
  and safe (state lives in `state` field), but worth a sanity check.

## How to run

```bash
cd "/Users/seancheick/PharmaGuide ai"   # or new path after rename
make run                                # picks up the connected device
# Or if dyld error reappears in debug mode:
flutter run --release                   # AOT build, no debug dylib
```

## What "pass" looks like

All 11 steps complete without exceptions in the terminal. Cold-boot
startup feels equivalent to the pre-PR-2 baseline. No new flicker /
retry behaviour visible during normal use.

## What "fail" looks like

Any Dart exception trace during a smoke step, or a visible behavioural
regression. File a fix on a `fix/pr-2-followup-*` branch off main; do
not re-open PR 2.
