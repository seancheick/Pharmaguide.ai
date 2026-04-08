# PharmaGuide Agent Instructions

> This file is read by OpenCode, Continue, Cline, Aider, and Gemini CLI.
> It tells any AI agent how to work in this codebase.

## Identity

You are working on PharmaGuide, a consumer supplement safety app built with Flutter/Dart.
This is a health-adjacent product. Accuracy matters more than speed.

## Architecture

- **Language:** Dart / Flutter
- **State:** Riverpod (explicit, testable providers)
- **Navigation:** GoRouter
- **Database:** Drift ORM (SQLite) — two databases:
  - `pharmaguide_core.db` — read-only product/ingredient data
  - `user_data.db` — read-write user preferences, never uploaded
- **Backend:** Supabase (sync only, NO health data leaves the device)
- **Tests:** `flutter test`
- **Lint:** `flutter analyze`

## Rules (Non-Negotiable)

1. **Read before edit.** Always read a file before changing it.
2. **Minimal diffs.** Change only what the task requires. No drive-by cleanups.
3. **Max 3 files per task.** If you need more, split the task.
4. **Verify after every change.** Run `flutter analyze` and relevant `flutter test` commands.
5. **Never invent health data.** No made-up contraindications, scores, evidence levels, or safety claims.
6. **Never store health data in Supabase.** All health data stays on-device.
7. **Severity enum is sacred:** contraindicated > avoid > caution > monitor > safe
8. **Never display "safe" when mapped_coverage < 0.3**
9. **FitScore is never persisted** — always computed fresh from current profile.
10. **Never mark a task done without running verification commands.**

## Workflow

For every task:

```
1. PLAN   — Read SPRINT_TRACKER.md. Identify the task. List files to change. Explain why.
2. TARGET — Confirm exact files. No new files unless absolutely necessary.
3. EDIT   — Make the smallest safe change. One concern per edit.
4. VERIFY — Run flutter analyze + flutter test. Fix any failures.
5. REPORT — State what changed, what passed, what's left.
```

## What NOT to do

- Don't refactor unrelated code
- Don't add packages without explicit need
- Don't bulk-edit JSON data files
- Don't create documentation files unless asked
- Don't guess at health/safety behavior — ask if unsure
- Don't mark tasks complete without test evidence

## Project Files

- `SPRINT_TRACKER.md` — Source of truth for task execution
- `CLAUDE.md` — Project rules and architecture details
- `lib/` — App source code
- `test/` — Test files
- `assets/` — Static assets
