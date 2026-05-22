# Self-Healing Setup (Layer 1: Sentry MCP + Seer)

This is the lowest-risk layer of the self-healing system: Sentry's Seer
analyzes new issues and posts a root-cause diagnosis; AI agents (Claude
Code, Continue, Cursor, etc.) attached to this repo can query Sentry
directly via MCP. **No code is auto-generated or auto-merged at this layer.**

Layer 2 (auto-PR pipeline) and Layer 3 (safety-invariant CI gate) are
designed but not yet enabled. See the recommendation thread on branch
`claude/self-healing-sentry-agents-ugeW5` for the full plan.

## What this layer does

1. **Seer Autofix** (Sentry-side, no code) — Sentry's AI ingests every new
   issue, builds a root-cause analysis, and posts it as a comment on the
   Sentry issue. Optionally posts the same analysis on the affected GitHub
   commit/PR.
2. **Sentry MCP server** (this repo) — `.mcp.json` registers the official
   hosted Sentry MCP server (`https://mcp.sentry.dev/mcp`). Any agent that
   speaks MCP gains tools to query Sentry issues, events, releases, and
   trigger Seer on demand.
3. **Agent guardrails** — `knowledge/sentry-autofix-playbook.md` defines the
   medical-safety invariants every agent must preserve when proposing a fix.

## One-time setup

### 1. Enable Seer in Sentry (UI, ~5 min)

Requires a Sentry Owner/Manager/Admin role.

1. Sentry → **Settings → Integrations → GitHub** — connect if not already.
   Seer only works with cloud GitHub, not self-hosted.
2. Sentry → **Settings → Seer SCM Settings** — add this repo
   (`seancheick/pharmaguide.ai`).
3. Sentry → **Settings → Seer Project Settings** — link the PharmaGuide
   project to the repo.
4. (Optional, recommended) Enable **"PR creation"** off — keep it off for
   now. Layer 2 will add a gated workflow that does this correctly for a
   medical app.

That's it. Seer will start posting root-cause analyses on new issues
within minutes.

### 2. Sentry MCP server (already configured)

`.mcp.json` is committed. The hosted server uses OAuth — the first time
an agent calls a Sentry tool it'll open a browser for you to authorize.
No token needs to live in this repo.

If you'd rather pin a token (e.g. for CI), swap `.mcp.json` to the
self-host form:

```json
{
  "mcpServers": {
    "sentry": {
      "command": "npx",
      "args": ["@sentry/mcp-server"],
      "env": {
        "SENTRY_ACCESS_TOKEN": "${SENTRY_ACCESS_TOKEN}",
        "EMBEDDED_AGENT_PROVIDER": "anthropic",
        "ANTHROPIC_API_KEY": "${ANTHROPIC_API_KEY}"
      }
    }
  }
}
```

### 3. Environment variables (only if you swap to the token form above)

The Flutter app already uses these — they're built into the Makefile and
do not need to change:

| Variable              | Used by                              | Where it lives |
|-----------------------|--------------------------------------|----------------|
| `SENTRY_DSN`          | App runtime (event ingestion)        | `.env` (local) + GitHub Actions Secrets |
| `SENTRY_ENVIRONMENT`  | App runtime (event tagging)          | `.env` (local) + GitHub Actions Secrets |
| `SENTRY_RELEASE`      | App runtime (release tagging)        | `.env` (local) + GitHub Actions Secrets |

The MCP server adds two more (only required if you self-host the MCP):

| Variable               | Used by                                | Where it lives |
|------------------------|----------------------------------------|----------------|
| `SENTRY_ACCESS_TOKEN`  | Sentry MCP server (API reads)          | `.env` (local) — **never commit** |
| `ANTHROPIC_API_KEY`    | Sentry MCP server (embedded analysis)  | `.env` (local) |

For GitHub Actions you only need `SENTRY_ACCESS_TOKEN` once Layer 2 lands.
Don't add it as a repo Secret yet — wait until the auto-PR workflow exists
to consume it.

Get the token at: **Sentry → Settings → Account → API → Auth Tokens**.
Scopes required: `event:read`, `project:read`, `org:read`, `member:read`.
Do **not** grant write scopes for Layer 1.

## How to use it

From any agent that reads `.mcp.json` (Claude Code, Claude Code on the Web,
Continue, Cursor, opencode):

> "Pull the top 5 unresolved Sentry issues from the last 7 days and rank
>  them by user impact. For the top one, run Seer and summarize the
>  root cause — don't write any code yet."

Or for a specific issue:

> "Investigate Sentry issue `PHARMAGUIDE-XYZ`. Read the stack trace, the
>  Seer analysis, and the breadcrumb trail. Tell me what's broken and
>  what a minimal fix would touch. Don't open a PR."

The agent will use the Sentry MCP tools to fetch real data instead of
guessing. Every Sentry-driven fix must follow
`knowledge/sentry-autofix-playbook.md`.

## What's intentionally not in Layer 1

- **No auto-PR.** Layer 2 will add a GitHub Action that opens a draft PR
  from a Sentry issue, but only after the safety-invariant test suite
  (Layer 3) is in place.
- **No auto-merge, ever.** Even with all gates green, a human always
  merges Sentry-driven fixes in this repo. See the playbook for why.
- **No website coverage.** The marketing site is in a separate repo;
  the same pattern will be applied there once you point me at it.

## Verifying it works

1. Trigger any test exception in dev: `throw Exception('test self-healing');`
   from any dev-only path, hit it once, then back out the change.
2. Within ~5 minutes the issue appears in Sentry with a Seer analysis.
3. In Claude Code (any surface), ask "what's the latest Sentry issue?"
   The agent should call `find_issues` via MCP and return real data.

If step 3 doesn't work, the MCP server isn't reachable from your agent —
check that `.mcp.json` is in the project root and your agent has been
restarted since adding it.
