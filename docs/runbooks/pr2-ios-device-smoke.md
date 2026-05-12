# Deferred: device runtime smoke (PR 2 Riverpod 3 + PR 3 drift/sqlite)

**Status:** DEFERRED to a future sprint per agreement on 2026-05-12.

This runbook is the combined eyes-on smoke checklist for two pieces of
work that have all automated gates green but cannot be device-verified
yet on this workstation:

| Origin | What's blocked | Unblock condition |
|---|---|---|
| **PR 2 — Riverpod 2 → 3** | iOS device smoke only. Code merged; automated tests green; Android APK + iOS simulator + iOS device builds all produce artifacts. | iPhone updates to iOS 26.5, OR Xcode adds an iOS 26.4 SDK, OR run with `flutter run --release` (AOT, no debug dylib). |
| **PR 3 — drift 2.32+ + sqlite3_flutter_libs removal** | The whole PR. drift 2.32+ is blocked by the Flutter SDK's meta 1.17 pin (see [drift-2.32-followup.md](drift-2.32-followup.md)). | Flutter SDK upgrade to a release with `meta ^1.18.0`. |

Run the relevant section below once the corresponding work has merged
and the blocker is gone.

## Original PR 2 blocker (2026-05-12)

On 2026-05-12 the connected iPhone was on iOS 26.4 but Xcode 26.5 was
the only SDK available locally. The debug-mode `flutter run` produced
a `dyld: Library not loaded: @rpath/Runner.debug.dylib` on launch —
Flutter's debug build embeds a debug VM dylib whose dyld expectations
can mismatch when the build SDK is a minor version ahead of the
device runtime.

## When to retry (PR 2)

Any of these unblocks the PR 2 smoke test:
1. iPhone updates to iOS 26.5 (matches the local SDK)
2. Xcode releases an iOS 26.4 SDK component (matches the device)
3. Switch to `flutter run --release` against the device (AOT compile
   skips the debug dylib entirely; loses hot reload but completes the
   smoke)

## PR 2 — what to verify

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

---

## PR 3 — drift 2.32+ + sqlite3_flutter_libs removal (also deferred)

PR 3 is deferred entirely (not just the smoke) because the Flutter SDK
pins `meta 1.17.0`, which transitively blocks `drift_dev` 2.32+. See
[drift-2.32-followup.md](drift-2.32-followup.md) for the full
explanation and the exact code/pubspec steps to take when unblocked.

This section is the **device-smoke checklist** that runs after the
drift upgrade PR's automated gates pass — i.e. after `flutter analyze`
is clean, all tests pass, and Android/iOS builds produce artifacts on
the upgraded Flutter SDK.

### When to retry (PR 3)

The Flutter SDK upgrade lands as a dedicated infrastructure PR with
its own QA pass. Once that PR is merged and `flutter_test`'s `meta`
floor is `^1.18.0`, the drift upgrade PR can run. Then this smoke
section gates merge.

### How to run

```bash
cd "/Users/seancheick/PharmaGuide ai"   # or new path after rename
make run                                # device — covers the device path
# Repeat on an Android emulator to verify native binding loading on Android:
flutter emulators --launch Medium_Phone_API_36.0
flutter run -d emulator-5554
```

### Drift / sqlite runtime checklist

1. **Cold boot — DB opens on Android.** App reaches Home; no
   `SqliteException` or `Could not open database` in logs.
2. **Cold boot — DB opens on iOS simulator.** Same.
3. **Cold boot — DB opens on real iPhone.** Same. This is the gold
   standard — it proves the new sqlite3 3.x native binding (loaded
   via Dart build hooks instead of `sqlite3_flutter_libs`) is being
   resolved correctly on a real device.
4. **Migrations run cleanly.** No errors in logs from any of the
   three DBs:
   - `core_database` `beforeOpen._ensureV130Columns` —
     `ALTER TABLE products_core ADD COLUMN` for ~30 columns; safe to
     re-run, each wrapped in try/catch.
   - `user_database` `onUpgrade` — schemaVersion currently 5; check
     migration runs end-to-end on a freshly-installed app and on an
     existing install that came from a pre-5 schema.
   - `interaction_database` — pinned at v1; no upgrade path
     exercised.
5. **FTS5 search.**
   - Type `magnesium`: results appear, ranked, no duplicates.
   - Type `thorne vitamin a` (multi-word cross-column): results
     match against brand `Thorne Research` and product_name
     `Vitamin A` simultaneously.
   - Confirm the LIKE-fallback path still works by inducing an FTS
     parse error (use a query with unbalanced quotes if practical;
     otherwise just verify no fallback was needed and move on).
6. **Barcode lookup (UPC normalization).** Scan or paste a UPC with
   stored spaces (`0 50428 38139 7` format in DB vs `050428381397`
   scanner output). Verify `findByUpc` resolves correctly. Try a
   13-digit UPC-A with leading zero, and a 12-digit value that needs
   a leading zero prepended.
7. **Product detail opens.** Interaction warnings render. The
   personalized interaction warnings provider hits drift via the
   `personalizedInteractionWarningsProvider(dsldId)` family.
8. **Interaction lookup latency feels equivalent.** Compare to baseline
   stack-screen tap-through performance. Not a precise benchmark — a
   "doesn't feel slower" sanity check.
9. **Stack DB path.** Open the Stack tab. Tap a product; navigate.
   For signed-in users: add a supplement, kill connectivity, restore,
   confirm `StackSyncListener` fires its push.
10. **WAL mode (default).** No "database is locked" or
    "BUSY/LOCKED" warnings in logs during normal interaction. Drift
    enables WAL by default on `NativeDatabase`; verify no regression.
11. **Native binding loading — bundle inspection.** After the build:

    ```bash
    # iOS
    ls build/ios/iphoneos/Runner.app/Frameworks/ | grep -i sqlite
    # Expected: NO sqlite3_flutter_libs.framework

    # Android
    unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep -i sqlite
    # Expected: only sqlite3 entries from sqlite3 package's
    # build-hook output; no flutter_libs/.so files
    ```

### Drift codegen watch list

When the drift bump PR is being built, summarize the `.g.dart` diff
explicitly. Drift codegen format changed between 2.19 and 2.31 already
(transitively via PR 2's Riverpod work) so the next bump (2.31 → 2.32+)
should be small. Watch for:

- Generated query method signature changes (semantic — call out)
- New `RootTableManager` type parameter shapes (mechanical — fine)
- Any `customStatement` or `customSelect` signature drift
- Drift deprecation warnings — note them but do not auto-fix beyond
  PR scope

### What "pass" looks like (PR 3)

All 11 steps complete without exceptions. Bundle inspection confirms
`sqlite3_flutter_libs` is gone. Cold-boot DB-open feels equivalent
to baseline.

### What "fail" looks like (PR 3)

- `Could not open database` or any `SqliteException` on cold boot:
  the build-hook native binding didn't load. Check Flutter SDK is at
  the required version (≥ the one that ships `meta ^1.18.0`). Check
  the Android NDK is recent enough for the sqlite3 build hook.
- FTS query returns nothing where it used to: a drift query
  generation regression. Roll back the drift bump; investigate
  separately.
- Stack sync fires when it shouldn't (or doesn't when it should):
  unrelated to drift but covered here because Stack uses drift.
  Likely a PR 2 (Riverpod 3) regression — see Riverpod watch list.
