# PharmaGuide Flutter App

Consumer-facing supplement safety app. Offline-first, privacy-first. Medical-grade accuracy required.

## Commands

```bash
make run          # flutter run + all --dart-define secrets injected from .env
make test         # flutter test
make check        # analyze + test (CI gate)
make gen          # dart run build_runner build --delete-conflicting-outputs
make verify-supabase  # confirm anon key is live
```

## Architecture

- **State:** Riverpod | **Nav:** GoRouter | **DB:** Drift (SQLite)
- `pharmaguide_core.db` — read-only, 180K products, 88 cols, replaced via OTA
- `user_data.db` — read-write, user profile/stack/cache, never touched by OTA
- Supabase — detail blob fetch + auth only. Health data never leaves device.

## Safety Rules (non-negotiable)

- NEVER store health data in Supabase
- NEVER display "safe" when `mapped_coverage < 0.3`
- ALWAYS use severity order: `contraindicated > avoid > caution > monitor > safe`
- ALWAYS show `evidence_level` on interaction warnings
- FitScore is NEVER persisted — computed fresh from current profile every time
- All JSON parsing must handle null/missing fields gracefully

## Knowledge Base

Deep context lives in `knowledge/` — read these when relevant, not by default:
- `architecture-decisions.md` — ADR log (append-only)
- `lessons-learned.md` — mistakes + root causes
- `flutter-patterns.md` — project conventions
- `debugging-playbook.md` — common issues + fixes
- `pipeline-reference.md` — pipeline data structures + enums
- `sentry-autofix-playbook.md` — guardrails when fixing Sentry-flagged issues

## Knowledge Graph

A navigable graph of the entire codebase + knowledge base lives in `graphify-out/`.
- `graph.json` — 2,772 nodes, 6,669 edges, 96 communities
- `graph.html` — interactive visualization (open in browser)
- `obsidian/` — full Obsidian vault with backlinks

Before answering architecture or "what connects to X" questions, query the graph:
```
/graphify query "your question"
/graphify path "NodeA" "NodeB"
/graphify explain "NodeName"
```
After code changes, the git hook auto-rebuilds for code files.
For doc/knowledge changes, run `/graphify . --update`.
