# PharmaGuide Agent Instructions

> This file is read by OpenCode, Continue, Cline, Aider, and Gemini CLI.
> It tells any AI agent how to work in this codebase.

## Identity

You are working on PharmaGuide, a consumer supplement safety app built with Flutter/Dart.
This is a health-adjacent product. Accuracy matters more than speed.
Hallucination is not permitted. Do not invent health logic, clinical meaning, contraindications, scoring behavior, or pipeline contracts. Prefer accuracy, speed, and explicit logic in that order.

## Operating Principles

### 1. Think Before Coding

- Do not assume silently. State assumptions explicitly when they matter.
- If multiple interpretations are plausible, surface them instead of picking one invisibly.
- If uncertain, ask or verify rather than guessing.
- Push back when a simpler or safer approach is better.
- If confused, stop and name the confusion clearly.

### 2. Simplicity First

- Write the minimum code that solves the problem.
- Do not add configurability, abstraction, or flexibility that was not requested.
- Do not build single-use abstractions unless they clearly reduce complexity.
- If a solution feels bloated, simplify it before moving on.
- Strong software is preferred over working fluff.

### 3. Surgical Changes

- Touch only what is required for the task.
- Do not refactor adjacent code unless the task requires it.
- Do not change comments, formatting, or unrelated logic as a side effect.
- Remove only the dead code or unused imports created by your own changes.
- If unrelated dead code is noticed, mention it rather than deleting it unprompted.

### 4. Goal-Driven Execution

- Define clear success criteria before editing.
- Prefer verifiable outcomes over subjective “done” states.
- For bug fixes, reproduce with a test when practical, then make it pass.
- For refactors, keep behavior stable and verify before and after.
- For multi-step work, keep a brief plan with a verification step for each stage.

## Architecture

- **Language:** Dart / Flutter
- **State:** Riverpod (explicit, testable providers)
- **Navigation:** GoRouter
- **Database:** Drift ORM (SQLite) — two databases:
  - `pharmaguide_core.db` — read-only product/ingredient data
  - `user_data.db` — read-write user preferences, never uploaded
- **Backend:** Supabase — detail blobs, auth, OTA catalog, and signed-in *supplement stack* sync through the audited path only. Profile, medications, allergens, conditions, goals, and FitScore never leave the device.
- **Tests:** `flutter test`
- **Lint:** `flutter analyze`

## Rules (Non-Negotiable)

**Product safety rules live in `CLAUDE.md` § Safety Rules and § Hard-won rules — that file is
canonical, and you must read it before touching anything that renders a verdict, a score, a
warning, or a sync path.** Only the three stable rendering invariants are mirrored below, as a
tripwire for agents that do not load CLAUDE.md. Everything volatile — what may sync to Supabase,
what copy voice is allowed, which SSOT owns dose safety — is deliberately NOT restated here:
this file once said health data never leaves the device, long after audited supplement-stack sync
shipped, and a contradiction between two rule files is more dangerous than one rule file.

Mirrored invariants (if these ever disagree with CLAUDE.md, CLAUDE.md wins — and fix this file):

- **Severity order is sacred:** contraindicated > avoid > caution > monitor > safe
- **Never display "safe" when `mapped_coverage < 0.3`**
- **FitScore is never persisted** — recomputed fresh from the current profile every time

Agent-behavior rules, which are this file's job:

1. **Read before edit.** Always read a file before changing it. Re-read any file a claim depends on — a stale mental model is how wrong-layer fixes happen.
2. **Minimal diffs.** Change only what the task requires. No drive-by cleanups.
3. **Keep the blast radius small.** Prefer the fewest files that fully solve the task; if a change fans out widely, say why before making it. (This replaces a hard "max 3 files" cap, which forced real fixes to ship half-done.)
4. **Verify after every change.** `flutter analyze` plus the relevant `flutter test` — see CLAUDE.md § Definition of Done for which rung to run.
5. **Never invent health data.** No made-up contraindications, scores, evidence levels, or safety claims.
6. **Never mark a task done without running verification commands** and pasting their output.

## Workflow

For every task:

```
1. PLAN   — Name the files to change and why. (SPRINT_TRACKER.md is 2,900 lines —
            open it only when the task IS a tracked sprint item, not by default.)
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

- `CLAUDE.md` — **canonical** project safety rules, architecture, and Definition of Done
- `SPRINT_TRACKER.md` — sprint board (large; read on demand, not per task)
- `lib/` — App source code
- `test/` — Test files
- `assets/` — Static assets
