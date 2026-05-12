# Runbook: Rename local project folder

**Status:** DRAFT — not yet executed. Pick a low-traffic moment after the
dependency-upgrade PR train has stabilised.

**Owner:** Sean.

**Estimated time:** 30 minutes including IDE re-open + clean rebuild.

---

## Why

The local project lives at `/Users/seancheick/PharmaGuide ai/`. The space
in the directory name causes recurring toolchain fragility:

1. **CocoaPods (Ruby 3.x):** raises
   `Encoding::CompatibilityError: ASCII-8BIT` because Ruby's
   `unicode_normalize` rejects the path under the default ASCII-8BIT
   locale. Currently worked around by exporting `LANG=en_US.UTF-8` in
   the Makefile (commit `c854c97`), but only `make`-driven workflows
   inherit it.
2. **Xcode (xcodebuild):** internally URL-encodes the path
   (`PharmaGuide%20ai`) and the module resolver can't always find
   Flutter plugins at the encoded path. Manifests as
   `Module 'app_links' not found` (or any other plugin name). The fix
   today is `flutter clean` followed by `flutter pub get`, but the
   problem recurs after any deep-clean of the iOS build dir.
3. **Random shell tools** that don't quote paths will silently break or
   misbehave (e.g. unquoted `find`, `xargs`, third-party scripts).

The space is a single-character problem that has cost real time across
PRs 1 and 2 already. Removing it is a one-time fix.

## What changes (and what doesn't)

| Surface | Effect |
|---|---|
| Git repository | **No effect.** Git tracks content, not the parent dir. History, branches, remote — all preserved. |
| Remote (GitHub) | **No effect.** Remote URL is configured in `.git/config` and is path-agnostic. |
| Build artifacts (`build/`, `.dart_tool/`) | **Wiped intentionally** by `flutter clean` — they cache absolute paths. |
| Xcode workspace | Re-open. Xcode caches workspace paths in `~/Library/Developer/Xcode/UserData/`; opening from the new location refreshes them. |
| iOS Pods (`ios/Pods/`) | Re-installed via `pod install --repo-update`. Same content, fresh paths. |
| IDE state (VS Code workspace, recent projects, breakpoints) | Re-open from new path. Workspace `.code-workspace` files (if any) reference the old path — see Step 5. |
| Shell `~/.bash_history` / `~/.zsh_history` | Old paths remain. Cosmetic only. |
| `CLAUDE.md`, knowledge docs | Need updating if they hard-code the absolute path. See Step 5. |
| `Makefile` | No absolute paths today (`$(HOME)`-based). Safe. |
| `.env` | No absolute paths today. Safe. |
| Sentry source-map uploads | Use relative paths via `sentry.properties`. Safe. |

## Choose a target name

Options the team has used elsewhere; pick one:
- `pharmaguide-flutter/` — explicit framework suffix, matches typical Flutter repo naming
- `pharmaguide-ai/` — keeps the "ai" hint, drops the space
- `pharmaguide/` — shortest, but loses the disambiguation from the `dsld_clean` pipeline repo and the WordPress folder

This runbook assumes **`pharmaguide-flutter`** unless changed.

## Pre-flight

Run these in sequence; **do not** proceed if any check fails.

```bash
# 1. Working tree must be clean (or stashed). Untracked .playwright-mcp/
#    logs and QA screenshots from previous sessions are OK; everything
#    else should be committed.
cd "/Users/seancheick/PharmaGuide ai"
git status

# 2. No background processes holding the directory open
#    (flutter run, gen-watch, simulators serving this app).
lsof +D "/Users/seancheick/PharmaGuide ai" 2>/dev/null | head

# 3. Note the current branch (you'll reopen here).
git branch --show-current

# 4. Close VS Code / Cursor / Xcode windows for this project.
#    Quit the Flutter dev server if running.
```

## Execute

```bash
# 5. Move (instant — same filesystem). NOT cp; we want one canonical copy.
cd /Users/seancheick
mv "PharmaGuide ai" pharmaguide-flutter

# 6. Verify git still works from the new location.
cd pharmaguide-flutter
git status                     # should show same state as pre-flight
git log -1 --format="%h %s"    # should show last commit
git remote -v                  # should show GitHub origin

# 7. Wipe build artifacts that cached the old absolute path.
flutter clean
rm -rf ios/Pods ios/Podfile.lock ios/.symlinks
rm -rf build .dart_tool

# 8. Re-resolve everything.
flutter pub get
make gen                       # Drift + JSON code generation
make pod-install               # iOS native deps
```

## Post-flight verification

```bash
# 9. Static analysis still clean.
make analyze

# 10. Full test suite still passes (~1,465 tests).
make test

# 11. iOS simulator build still works.
flutter build ios --simulator --debug --no-codesign

# 12. Android APK build still works.
flutter build apk --debug

# 13. Real device (connected iPhone) build still works.
flutter build ios --debug --no-codesign
```

If any of 9–13 fail with errors that mention the OLD path
(`PharmaGuide ai` or `PharmaGuide%20ai`), the failure is a cache that
survived step 7 — re-run `flutter clean && rm -rf ios/Pods` and try
again.

## Update path references

Search the repo and `~/.claude/` for hard-coded references to the old
path. Update each.

```bash
# Inside the project
grep -rn "PharmaGuide ai" --include="*.md" .
grep -rn "PharmaGuide ai" --include="*.json" .
grep -rn "PharmaGuide ai" --include="*.yaml" .

# In Claude / IDE config (outside the repo)
grep -rn "PharmaGuide ai" ~/.claude/ 2>/dev/null
grep -rn "PharmaGuide ai" ~/Library/Application\ Support/Code/User/ 2>/dev/null
```

Known files that will need editing (as of 2026-05-12):
- `~/.claude/projects/-Users-seancheick-PharmaGuide-ai/memory/MEMORY.md` and its sibling memory files — Claude's memory dir will need migrating or recreating under the new path
- `~/.claude/CLAUDE.md` if it references the absolute path
- Any VS Code workspace file at the OS level

## Rollback

If anything goes badly wrong:

```bash
cd /Users/seancheick
mv pharmaguide-flutter "PharmaGuide ai"
cd "PharmaGuide ai"
flutter clean
flutter pub get
make pod-install
```

Filesystem `mv` is reversible. The only non-reversible step is the
update of path references in other files — keep a list of what you
edited so you can revert those too.

## When to do this

After the dependency-upgrade PR train (PRs 1–11) has fully landed and
stabilised on `main`. Doing it mid-train risks turning a clean dep
upgrade PR into a path-rename PR, which muddies the diff.

Recommended sequencing:
1. Finish PR 11 (share_plus + connectivity_plus).
2. Land any blockers / hot-fixes.
3. Schedule a dedicated 30-minute slot.
4. Run this runbook.
5. Commit any path-reference updates in a single follow-up PR titled
   `chore(repo): update internal path references after folder rename`.

Not urgent for V1.0 ship, but worth doing before V1.1 work begins so
the cleaner path is in place for the broader team.
