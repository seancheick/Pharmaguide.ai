@AGENTS.md

# Claude Code delta

AGENTS.md above is imported on purpose. This repo has a CLAUDE.md, so Claude Code's default mode
(`claude-md-or-agents-md`) would otherwise skip AGENTS.md, which is the canonical rule file for every
agent. Keep shared rules there; this file holds only Claude-specific extras.

## Session flow

- The SessionStart hook prints the branch, HEAD and handoff age. If a handoff exists, run
  `/pg-resume` before editing.
- At a phase boundary, run `/handoff` and recommend a fresh session to Sean rather than compacting.

## Project commands (`.claude/commands/`)

`/triage-feedback`, `/fix-sentry-issue`, `/record-autofix-lesson`, `/triage-missing-upcs`.
Before fixing a Sentry issue, read `knowledge/sentry-autofix-playbook.md`.

## Knowledge base (read on demand)

- `knowledge/architecture-decisions.md`: the ADR log (append-only).
- `knowledge/lessons-learned.md`: mistakes and their root causes.
- `knowledge/flutter-patterns.md`: project conventions.
- `knowledge/debugging-playbook.md`: common issues and fixes.
- `knowledge/pipeline-reference.md`: pipeline data structures and enums.

## Knowledge graph (`graphify-out/`)

- `graph.json` is navigation, not evidence. Compare its `built_at_commit` with `git rev-parse HEAD`
  before trusting it.
- `/graphify query "…"`, `/graphify path "A" "B"`, and `/graphify explain "X"` answer
  "what connects to X".
- The `post-commit` hook rebuilds the graph for code changes (log: `~/.cache/graphify-rebuild.log`).
  For doc changes, run `/graphify . --update`.
- `git lfs install` overwrites the post-commit and post-checkout hooks, which removes the graphify
  rebuild. After any LFS (re)install, run `graphify hook install` and confirm it with
  `graphify hook status`.
