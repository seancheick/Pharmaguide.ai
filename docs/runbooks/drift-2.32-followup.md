# Deferred: drift 2.32+ upgrade + sqlite3_flutter_libs removal

**Status:** DEFERRED — blocked on a Flutter SDK upgrade.

**Originally scheduled as:** PR 3 of the 2026-05 dependency-upgrade
train. Investigation during PR 3 setup confirmed the work is
fundamentally unreachable at the current Flutter SDK and was
deferred per agreement on 2026-05-12 to preserve the train's
"infrastructure correctness, no patch-over-patch" rule.

## Current state (as of 2026-05-12)

| Package | Resolved | Why this version |
|---|---|---|
| drift | 2.31.0 | Transitively pulled to its highest analyzer-^9-compatible release by PR 2's Riverpod 3 work |
| drift_dev | 2.31.0 | Same |
| sqlite3 (Dart) | 2.9.4 | drift 2.31.x depends on `sqlite3 ^2.4.3` (the 2.x line) |
| sqlite3_flutter_libs | 0.5.42 | Required as long as drift uses sqlite3 2.x — the 2.x line does NOT use Dart build hooks for native binding loading |

## Why the cleanup is blocked

The two changes we need land in the **same drift release**:

| drift version | sqlite3 dep | analyzer dep |
|---|---|---|
| ≤ 2.31.x | `sqlite3 ^2.4.3` (2.x) | `analyzer ^9.0.0` ✅ compatible |
| **2.32.0** ← target | **`sqlite3 ^3.1.5` (3.x)** ← the native-binding switch | `analyzer ^10.0.0` ❌ blocked |
| 2.32.1+ | `sqlite3 ^3.1.5` (3.x) | `analyzer >=10.0.0 <13.0.0` ❌ blocked |
| 2.33.0 | `sqlite3 ^3.x` | `analyzer >=10.0.0 <13.0.0` ❌ blocked |

Why analyzer ≥10.0.0 is blocked:

```
flutter_test (Flutter SDK 3.41.7) → pins meta 1.17.0   (immovable)
analyzer ≥10.0.2                  → needs meta ^1.18.0
```

The Flutter SDK pin on `meta 1.17.0` propagates through `flutter_test`
to the whole project. There is no way to lift analyzer past 10.0.1
while we're on Flutter 3.41.7. The drift 2.32.x line all requires
`analyzer ≥10.0.0`, so even 2.32.0 is unreachable here.

Conclusion: **the sqlite3 2.x → 3.x switch and the analyzer ≥10
requirement happened in the same drift release (2.32.0)**, so there's
no compatible version that gives us one without the other.

## Unblock condition

Any one of these unblocks the work:

1. **Flutter SDK upgrade** to a release that ships `flutter_test`
   depending on `meta ^1.18.0`. Pin to that release. Re-run
   `flutter pub upgrade` and the drift 2.32+ family will resolve.
2. Flutter publishes a `flutter_test` patch bumping its meta floor.
   (Less likely; SDK upgrade is the canonical path.)
3. A `riverpod_generator` release that explicitly carries a
   shim/compat path letting analyzer ≥10 coexist with the current
   meta. (Hypothetical; not on any roadmap as of 2026-05-12.)

The Flutter SDK upgrade is the realistic path. Don't run it inside
this dependency-upgrade train — its blast radius is bigger than any
single Dart-package upgrade. It deserves its own focused PR with its
own QA pass.

## What to do when unblocked

Run the following sequence in a dedicated PR after the Flutter SDK
upgrade has landed and stabilised:

### 1. Bump drift and drift_dev

```yaml
# pubspec.yaml
dependencies:
  drift: ^2.33.0     # or whatever's latest by then
dev_dependencies:
  drift_dev: ^2.33.0
```

### 2. Remove sqlite3_flutter_libs

In `pubspec.yaml` under `dependencies`, delete the line:

```yaml
sqlite3_flutter_libs: ^0.5.0
```

…and any explanatory comment around it. drift's `sqlite3` 3.x
dependency loads the native binding via Dart build hooks
automatically; no Flutter-side helper package is needed.

### 3. Resolve and regenerate

```bash
flutter pub get
make gen
```

### 4. Check for SqliteException constructor changes

`sqlite3` 3.0.0 switched `SqliteException`'s constructor signature
from positional to named parameters. Search before the build:

```bash
grep -rn "SqliteException(" lib test --include="*.dart"
```

As of 2026-05-12 there are zero direct constructor call sites in this
codebase (only a comment in `lib/data/database/core_database.dart`
mentioning the type for documentation). Re-verify before committing
the upgrade in case any get added later.

### 5. Run the standard gates

```bash
flutter analyze       # must be clean
flutter test          # all 1,465+ tests must pass
flutter build apk --debug
flutter build ios --simulator --debug --no-codesign
flutter build ios --debug --no-codesign
```

### 6. Spot-check the device runtime (the deferred-smoke checklist)

Use [pr2-ios-device-smoke.md](pr2-ios-device-smoke.md), specifically
the drift/sqlite section, which was extended for this work:

- DB opens on Android emulator
- DB opens on iOS simulator
- DB opens on connected iPhone
- Migrations run cleanly (core_database `_ensureV130Columns`,
  user_database onUpgrade through schema v5, interaction_database
  pinned at v1)
- WAL behaviour (drift's default mode) — no warnings in logs
- FTS5 search returns ranked results (multi-word cross-column queries
  via `products_fts MATCH`)
- LIKE fallback path still triggers when FTS table is missing
- UPC barcode lookup with stored-spaces normalization
- Stack DB path: add → query → remove cycle
- Interaction lookup latency feels equivalent to baseline

If any drift codegen diff in this future PR shows a *semantic* query
change (not just type-inference or formatting), call it out
explicitly in the PR description before merge.

### 7. Verify native binding loading

The whole point of this upgrade. After the build runs on a device,
inspect the app bundle to confirm `sqlite3_flutter_libs.framework`
(or its Android equivalent) is no longer present:

```bash
# iOS
ls build/ios/iphoneos/Runner.app/Frameworks/ | grep -i sqlite
# Should NOT show sqlite3_flutter_libs.framework

# Android
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep -i sqlite
# Should only show sqlite3-related entries from the sqlite3 package's
# build-hook output, not from the flutter_libs package
```

## What this PR will look like (when it runs)

Estimated diff: ~5 lines in `pubspec.yaml`, full `pubspec.lock`
refresh, regenerated `.g.dart` files (gitignored). Possibly small
edits if any `SqliteException(` constructor sites have appeared by
then. No application-logic changes expected.

Risk: medium. Native binding loading is the riskiest part. Mitigation
is the device smoke from step 6.

## Cross-references

- [pr2-ios-device-smoke.md](pr2-ios-device-smoke.md) — combined
  deferred-smoke checklist (also covers Riverpod 3 watch list)
- [rename-project-folder.md](rename-project-folder.md) — unrelated
  infrastructure follow-up
