# AGENT CONTEXT

Project: PharmaGuide Flutter App
Language: Dart / Flutter
State Management: Riverpod
Navigation: GoRouter
Database: Drift (SQLite) — two databases
  - pharmaguide_core.db (read-only product data)
  - user_data.db (read-write user state, never uploaded)
Backend: Supabase (sync only, no health data)

## Source of Truth

- SPRINT_TRACKER.md — task execution and completion
- CLAUDE.md — project rules and architecture

## Model Stack

| Role | Model | Provider |
|------|-------|----------|
| Chat/Edit/Agent | Gemini 2.5 Pro (free) | Google AI Studio |
| Chat/Edit/Agent (local) | qwen2.5-coder:14b | Ollama |
| Autocomplete | qwen2.5-coder:1.5b | Ollama |
| Next-edit prediction | nate/instinct | Ollama |
| Embeddings | nomic-embed-text:v1.5 | Ollama |
| Final verification | Claude Code / Codex | Anthropic |

## Execution Policy

- Never mark tasks complete without fresh verification evidence
- Prefer smallest safe patch
- File targeting before editing
- Verification after each meaningful implementation step
- Claude Code / Codex are used separately for final audit
- One task at a time, never batch-finish

## Current Sprint

Sprint 0 — see SPRINT_TRACKER.md for details

## Safety Rules

- Never store health data in Supabase
- Never display "safe" when mapped_coverage < 0.3
- Always use severity enum: contraindicated > avoid > caution > monitor > safe
- Always show evidence_level on interaction warnings
- FitScore is NEVER persisted — always computed fresh
