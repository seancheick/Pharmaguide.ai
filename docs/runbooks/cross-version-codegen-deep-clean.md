# Runbook: Deterministic deep-clean for cross-version codegen transitions

**Status:** Backlog — captured 2026-05-12 during the dependency-upgrade
PR train. Not urgent; only matters when the team is doing rapid branch
switches that cross drift_dev (or other codegen-using packages)
versions.

## Why this exists

During PR 5 (mobile_scanner) we discovered that `make gen` does not
fully recover from a build_runner state that was last generated against
a different drift_dev version. Specifically, when switching between:

| Branch | drift_dev | drift_dev API style generated |
|---|---|---|
| `chore/pr-2-riverpod-3` and descendants | 2.31.0 (transitively pulled by Riverpod 3) | new TableManager API: `RootTableManager` with 11 type args, `PrefetchHooks`, `BaseReferences` |
| `main` and `fix/*` branches off main | 2.19.1 (project's pinned version) | old TableManager API: 7 type args, no `PrefetchHooks` |

…build_runner's cache in `.dart_tool/build` survived branch switches and
the next `make gen` regenerated code in the OLD format — but
referenced new-API types that drift 2.19 doesn't export. Result:
2,000+ analyze errors that look catastrophic but are pure cache
poisoning.

The diagnostic signal:
```
error • Type 'PrefetchHooks' not found
error • Type 'BaseReferences' not found
error • The type 'RootTableManager' is declared with 7 type parameters, but 11 type arguments were given
```

If you see those three together right after switching branches, it's
almost certainly cache poisoning, not a real code issue.

## What works today (manual recovery)

```bash
# From the project root:
flutter clean                      # drops Flutter build artifacts
rm -rf .dart_tool                  # nukes the build_runner cache
find lib -name "*.g.dart" -delete  # remove stale generated files
flutter pub get                    # rehydrate package metadata
make gen                           # regenerate against current pubspec.lock
flutter analyze                    # should be clean
```

This worked reliably during the train. Total time ~60-90 seconds.

## Recommended workflow improvement (not yet implemented)

Add a Makefile target that bundles the recovery sequence so contributors
don't have to remember it:

```makefile
.PHONY: deep-clean
deep-clean: ## Force a full codegen reset (use when switching between branches with different drift_dev/riverpod_generator versions)
	flutter clean
	rm -rf .dart_tool
	find lib -name '*.g.dart' -delete
	flutter pub get
	$(MAKE) gen
```

Or — more conservatively — add a `gen-fresh` target that does the
minimum needed (cache + .g.dart wipe + regen) without `flutter clean`:

```makefile
.PHONY: gen-fresh
gen-fresh: ## Regenerate .g.dart from scratch (use after switching branches with different codegen versions)
	rm -rf .dart_tool/build
	find lib -name '*.g.dart' -delete
	dart run build_runner build --delete-conflicting-outputs
```

`gen-fresh` is faster (skips Flutter's full clean) and is the typical
case we need.

## When to use which

| Scenario | Command |
|---|---|
| Normal day-to-day work on one branch | `make gen` |
| Switched between branches that have the same drift_dev version | `make gen` |
| Switched between branches with different drift_dev / riverpod_generator versions | `make gen-fresh` (when added) |
| Build is broken and you don't know why | `make deep-clean` (when added) |
| iOS Pods/Xcode in a weird state too | `make deep-clean` + `make pod-install` |

## Why this wasn't fixed in the PR that surfaced it

The PR train rule is "no opportunistic cleanup, surgical scope per PR".
Adding workflow improvements to the dependency PRs that surfaced the
issue would have muddied those diffs. This runbook captures the
context; the actual Makefile change ships when someone picks up this
backlog item.

## Suggested triggers for picking this up

- Next time the team is doing another dependency-upgrade train where
  codegen versions will cross
- Or any time a contributor hits the cache-poisoning symptom and asks
  "why does this happen" — then it's worth the 5-minute Makefile change

Until then, this runbook is the answer when the symptom appears.

## Cross-references

- [drift-2.32-followup.md](drift-2.32-followup.md) — the future drift
  upgrade that will trigger this exact transition again (drift_dev 2.19
  → 2.32+)
- [pr2-ios-device-smoke.md](pr2-ios-device-smoke.md) — combined
  deferred device smoke for the train
- [rename-project-folder.md](rename-project-folder.md) — unrelated
  infrastructure follow-up
