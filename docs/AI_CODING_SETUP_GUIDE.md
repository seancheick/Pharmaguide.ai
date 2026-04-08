# PharmaGuide AI Coding Setup Guide

> Complete reference for all AI coding tools, models, and workflows.
> Last updated: 2026-04-08

---

## Table of Contents

1. [The Big Picture](#the-big-picture)
2. [All Your Tools Explained](#all-your-tools-explained)
3. [All Your Models Ranked](#all-your-models-ranked)
4. [How to Use Each Tool (Step by Step)](#how-to-use-each-tool)
5. [When to Use What](#when-to-use-what)
6. [Daily Workflow](#daily-workflow)
7. [Model Routing Cheat Sheet](#model-routing-cheat-sheet)
8. [Quick Commands Reference](#quick-commands-reference)
9. [OpenCode Agents](#opencode-agents)
10. [Costs Summary](#costs-summary)

---

## The Big Picture

You have TWO tiers of AI coding tools:

**Tier A (Primary -- paid, best quality):**
- Claude Code Max (Anthropic) -- best coding AI, your main tool
- Codex / ChatGPT (OpenAI) -- second best, use when Claude is down

**Tier B (Backup -- free/cheap, for when Tier A tokens run out):**
- Gemini CLI -- free frontier model in terminal (1000 req/day)
- OpenCode -- open source terminal agent with any model
- Continue -- VS Code extension with local/cloud models
- Cline -- VS Code agentic extension
- Aider -- terminal pair programmer with git integration
- `ollama launch claude` -- Claude Code interface with free models

**The strategy:** Use Tier A until tokens run out. Switch to Tier B. Use Tier A to verify/audit when it resets.

---

## All Your Tools Explained

### Claude Code (your primary tool)
- **What:** Anthropic's official terminal coding agent
- **Brain:** Claude Opus 4.6 (best coding model available)
- **Launch:** `claude` in terminal
- **Strengths:** Best reasoning, best code quality, largest context (200K), multi-agent spawning
- **Limit:** Token-based on your Max plan
- **When:** Always use first. It's the best.

### Codex / ChatGPT
- **What:** OpenAI's coding agent
- **Brain:** GPT-5 / o3
- **Strengths:** Good reasoning, alternative perspective
- **When:** When Claude is down or for second opinion

### Gemini CLI
- **What:** Google's terminal coding agent (open source)
- **Brain:** Gemini 2.5 Pro (frontier model, 1M token context)
- **Launch:** `gemini` in terminal
- **Cost:** FREE -- 1000 requests/day with personal Google account login
- **Strengths:** Frontier quality, massive context, built-in web search, MCP support
- **When:** #1 choice when Claude tokens run out. Best free option.
- **Note:** Uses your Google account login, NOT the API key. Different quota.

### OpenCode
- **What:** Open source terminal coding agent (TUI interface)
- **Brain:** Any model you configure (Gemini, Groq, Ollama local, etc.)
- **Launch:** `cd "PharmaGuide ai" && opencode`
- **Cost:** Free (you provide the model)
- **Strengths:** 75+ model providers, custom agents, beautiful TUI, file editing, bash
- **Switch models:** `/models` inside OpenCode
- **Switch agents:** `Tab` key cycles through agents
- **When:** When you want to use local models or Groq with a full agent interface

### `ollama launch claude`
- **What:** The real Claude Code app, but powered by a free Ollama model instead of Anthropic's API
- **Brain:** Whatever Ollama model you select (Gemma4, Kimi K2.5, Qwen3.5, etc.)
- **Launch:** `ollama launch claude` -> select a model
- **Cost:** Free (local models) or Ollama cloud free tier
- **Strengths:** Same Claude Code interface you know, but free. File editing, terminal, multi-step.
- **Weakness:** Local models are much less capable than real Claude Opus
- **When:** When Claude tokens are out AND you prefer the Claude Code interface over OpenCode
- **Best models for it:** kimi-k2.5:cloud (best quality), gemma4 (best local)

### `ollama launch opencode`
- **What:** Same as `opencode` but Ollama auto-configures the model for you
- **Launch:** `ollama launch opencode` -> select a model
- **When:** Quick way to start OpenCode without editing opencode.json

### Continue (VS Code Extension)
- **What:** AI coding assistant inside VS Code (like GitHub Copilot but open source)
- **Brain:** Multiple models configured (Gemini Flash, Groq, Local 14B, Local 1.5B)
- **Strengths:** Autocomplete, inline edit, chat sidebar, agent mode, codebase indexing
- **When:** Always running in VS Code for autocomplete and quick edits

#### How to Use Continue:

**Reload VS Code first:** Cmd+Shift+P -> "Reload Window"

**Select your model:** Click the model dropdown at top of Continue panel:
- Gemini 2.5 Flash -- daily driver (free, 250 req/day via API)
- Gemini 2.5 Pro -- complex tasks (free, 100 req/day via API)  
- Groq Llama 3.3 70B -- ultra-fast (free, 1000 req/day)
- Local Qwen 14B -- offline, unlimited
- Local Autocomplete -- always-on tab completion (1.5B)

**Three modes:**

| Mode | Shortcut | What it does |
|------|----------|-------------|
| **Chat** | Cmd+L | Ask questions, get explanations |
| **Edit** | Cmd+I | Inline code changes with diff view |
| **Agent** | Switch dropdown to "Agent" | Autonomous multi-file tasks |

**Using Chat:**
1. Select code in editor
2. Press Cmd+L
3. Ask your question
4. It answers with full codebase context

**Using Edit:**
1. Select code in editor
2. Press Cmd+I
3. Describe the change: "add error handling" or "convert to async"
4. Review the diff -> Accept or Reject

**Using Agent Mode:**
1. Open Continue chat panel
2. Switch dropdown at bottom from "Chat" to "Agent"
3. Type your task: "Read SPRINT_TRACKER.md and implement the next task"
4. Agent will read files, make edits, run commands
5. Approve or reject each action

**Context shortcuts (type in chat box):**
- `@file` -- reference a specific file
- `@code` -- reference selected code
- `@codebase` -- search entire codebase
- `@docs` -- search indexed docs (SPRINT_TRACKER, CLAUDE.md)
- `/sprint_plan_mode` -- use planning prompt
- `/sprint_execute_mode` -- use execution prompt

### Cline (VS Code Extension)
- **What:** Agentic AI extension for VS Code
- **Brain:** Configure in settings (Ollama, Gemini, etc.)
- **Strengths:** Very agentic -- reads/writes files, runs terminal, browses web
- **When:** Alternative to Continue Agent mode. Some prefer its UI.

#### How to Use Cline:

1. Click Cline icon in sidebar (or Cmd+Shift+P -> "Cline: Open")
2. Settings (gear icon):
   - API Provider: **Ollama** (or Google Gemini)
   - Base URL: `http://localhost:11434`
   - Model ID: `gemma4:latest` (or `qwen2.5-coder:14b`)
3. Type your task naturally
4. Cline shows every action -- Approve or Reject each one

### Aider (Terminal)
- **What:** Terminal-based AI pair programmer with git integration
- **Brain:** Configurable (defaults to Gemini Flash via .aider.conf.yml)
- **Launch:** `cd "PharmaGuide ai" && aider`
- **Strengths:** Auto-commits, full codebase map, multi-file edits, git-native
- **When:** Multi-file refactors where you want clean git history

#### How to Use Aider:

```bash
# Default (uses Gemini Flash)
cd "PharmaGuide ai" && aider

# With local model
aider --model ollama/gemma4:latest

# With Groq (ultra-fast)
aider --model groq/llama-3.3-70b-versatile

# Add specific files to context
aider lib/features/profile/profile_provider.dart test/features/profile/

# Common commands inside aider:
/add <file>     # Add file to context
/drop <file>    # Remove file from context  
/run <command>  # Run a shell command
/diff           # Show current changes
/undo           # Undo last change
/commit         # Commit changes
```

---

## All Your Models Ranked

### Cloud Models (Free Tier)

| Rank | Model | Provider | Quality | Speed | Free Limit | Best For |
|------|-------|----------|---------|-------|------------|----------|
| 1 | **Gemini 2.5 Pro** | Gemini CLI (Google login) | Excellent | Fast | 1000 req/day | Complex tasks, architecture |
| 2 | **Gemini 2.5 Flash** | API (Google AI Studio) | Very Good | Very Fast | 250 req/day | Daily coding, edits |
| 3 | **Groq Llama 3.3 70B** | Groq | Good | Ultra-Fast (800 tok/s) | 1000 req/day | Quick edits, fast iteration |
| 4 | **Kimi K2.5 (cloud)** | Ollama cloud | Good | Fast | Free tier varies | Agent tasks via ollama launch |

### Local Models (Unlimited, Free Forever)

| Rank | Model | Size | Context | Tools | Thinking | Best For |
|------|-------|------|---------|-------|----------|----------|
| 1 | **gemma4** | 8B (9.6 GB) | 128K | Yes | **Yes** | Best overall local agent (tools + thinking + long context) |
| 2 | **qwen2.5-coder:14b** | 14.8B (9 GB) | 32K | Yes | No | Code-specific tasks (trained on code) |
| 3 | **qwen3.5** | 9.7B (6.6 GB) | 256K | Yes | No | General reasoning, longest context |
| 4 | **qwen2.5-coder:1.5b** | 1.5B (986 MB) | 4K | No | No | Autocomplete only (fastest) |
| 5 | **nate/instinct** | 7B (4.7 GB) | 32K | Yes | No | Next-edit prediction in Continue |

### Why Gemma4 is the best local model for agent work:

1. **Tool calling + thinking** -- the only local model you have that does BOTH. This is critical for agents (OpenCode, Cline, ollama launch claude) because they need the model to decide when to read files, write files, run commands.
2. **128K context** -- 4x more than qwen2.5-coder:14b (32K). Can hold more of your codebase.
3. **Google made Dart/Flutter** -- Gemma4 has strong Flutter/Dart training data.
4. **Same RAM** as qwen2.5-coder:14b (~9.6 GB vs 9 GB).

### When to use qwen2.5-coder:14b instead:

- Pure code completion (it's trained specifically on code)
- Continue autocomplete/edit (not agent mode)
- When you don't need tool calling or thinking

### Models NOT worth running on 16GB:

- **qwen3-coder:30b** (18 GB) -- will swap to disk, painfully slow
- Any 27B+ dense model -- won't fit alongside your OS

---

## When to Use What

### Decision Tree:

```
Claude Code tokens available?
  YES -> Use Claude Code (best quality)
  NO  -> What kind of task?
           |
           ├── Complex multi-file task?
           |     -> gemini (Gemini CLI, 1000 free/day)
           |
           ├── Quick edit or question?
           |     -> Continue + Groq in VS Code (fastest)
           |
           ├── Multi-file refactor with git?
           |     -> aider (git integration)
           |
           ├── Need full agent (read/write/bash)?
           |     -> opencode + gemma4 or Groq
           |     -> OR: ollama launch claude + gemma4
           |
           ├── Offline / no internet?
           |     -> opencode + gemma4 (local, unlimited)
           |     -> OR: Continue + Local Qwen 14B
           |
           └── Need verification of AI work?
                 -> Wait for Claude Code reset
                 -> OR: gemini (Gemini 2.5 Pro is close to Opus)
```

### By tool location:

| Location | Tools Available |
|----------|----------------|
| **VS Code (always running)** | Continue (autocomplete + chat + agent), Cline |
| **Terminal (on demand)** | `gemini`, `opencode`, `aider`, `ollama launch claude` |
| **Terminal (primary)** | `claude` (when tokens available) |

---

## Daily Workflow

### Morning (Claude tokens fresh):
1. Open `claude` -- work on hardest sprint tasks
2. Use Continue for autocomplete while coding
3. When Claude hits limit, note where you stopped

### Claude tokens exhausted:
1. **For complex tasks:** Open new terminal -> `gemini`
   - Same agentic quality, 1000 free requests
2. **For quick edits:** Use Continue with Groq (ultra-fast)
3. **For offline work:** `opencode` with gemma4
4. **For multi-file refactors:** `aider`

### When Claude resets:
1. Review what the free tools built
2. Use Claude to audit: "Review the changes in the last 3 commits against SPRINT_TRACKER.md"
3. Fix any issues Claude finds
4. Move to next sprint task

---

## Model Routing Cheat Sheet

| Task Type | Best Model | Tool | Why |
|-----------|-----------|------|-----|
| Architecture design | Claude Opus | `claude` | Needs deep reasoning |
| Multi-file feature | Gemini 2.5 Pro | `gemini` | Frontier quality, free |
| Single file edit | Groq Llama 3.3 | Continue | Ultra-fast |
| Bug fix | Gemini Flash | Continue Agent | Good + fast |
| Code completion | qwen2.5-coder:1.5b | Continue autocomplete | Instant, always-on |
| Offline coding | gemma4 | `opencode` or `ollama launch claude` | Tools + thinking |
| Test writing | Gemini Flash | Continue Agent | Good at test patterns |
| Refactor (multi-file) | Gemini Flash | `aider` | Git integration |
| Code review | Claude Opus | `claude` | Best judgment |
| Sprint planning | Gemini 2.5 Pro | `gemini` | Large context for docs |

---

## Quick Commands Reference

```bash
# ============================================================
# PRIMARY (when Claude tokens available)
# ============================================================
claude                                    # Best quality, your main tool

# ============================================================
# BACKUP (when Claude tokens exhausted)  
# ============================================================

# Best free cloud agent (1000 req/day, Gemini 2.5 Pro, 1M context)
gemini

# Open source terminal agent (multiple models)
cd "PharmaGuide ai" && opencode
# Inside: /models to switch, Tab to switch agents

# Claude Code interface with free models
ollama launch claude                      # Select gemma4 or kimi-k2.5:cloud

# Terminal pair programmer with git
cd "PharmaGuide ai" && aider              # Uses Gemini Flash by default
aider --model ollama/gemma4:latest        # Use local model
aider --model groq/llama-3.3-70b-versatile  # Use Groq (fast)

# ============================================================
# VS CODE (always running)
# ============================================================
# Cmd+L        -> Continue chat
# Cmd+I        -> Continue inline edit  
# Tab          -> Accept autocomplete
# Model dropdown -> Switch between Gemini/Groq/Local

# ============================================================
# OLLAMA MODEL MANAGEMENT
# ============================================================
ollama list                               # See installed models
ollama pull <model>                       # Download a model
ollama rm <model>                         # Remove a model
ollama run <model>                        # Quick chat with model
ollama show <model>                       # Show model details
```

---

## OpenCode Agents

OpenCode has built-in and custom agents. Switch with **Tab** key.

### Built-in Agents:

| Agent | Mode | Can Edit? | Use For |
|-------|------|-----------|---------|
| **Build** | Primary | Yes | General coding, implementation |
| **Plan** | Primary | No (read-only) | Analysis, exploration, planning |

### Custom Agents (created for PharmaGuide):

| Agent | Mode | Can Edit? | Use For |
|-------|------|-----------|---------|
| **Sprint Worker** | Primary | Yes | Sprint task execution with safety rules |
| **Verifier** | Primary | No | Checking work against Definition of Done |

Custom agent files live in: `.opencode/agents/`

### Using agents in OpenCode:

1. Launch: `opencode`
2. Press **Tab** to cycle through agents
3. Or type `@agent-name` to invoke a subagent
4. `/models` to switch the underlying model

---

## Costs Summary

### What you're already paying:
- Claude Code Max plan (Anthropic) -- your primary tool
- Codex / ChatGPT (OpenAI) -- secondary
- Gemini Pro subscription ($19.99/month) -- consumer chat, does NOT include API

### What's FREE:
| Tool/Model | Cost | Limit |
|-----------|------|-------|
| Gemini CLI | $0 | 1000 req/day (Google login) |
| Gemini 2.5 Flash API | $0 | 250 req/day |
| Groq API | $0 | 1000 req/day |
| All Ollama local models | $0 | Unlimited |
| OpenCode | $0 | Open source |
| Continue | $0 | Open source |
| Cline | $0 | Open source |
| Aider | $0 | Open source |
| Ollama cloud models | $0 | Free tier varies |

### Not worth paying for (you have enough):
- xAI Grok API -- no more free credits, and you have Gemini
- OpenCode Go ($5-10/month) -- you already have Gemini + Groq + local
- Gemini API paid tier -- you have Gemini CLI which is free and better

### Your total extra cost: $0

---

## File Locations Reference

```
PharmaGuide ai/
├── AGENTS.md                          # Universal agent instructions (all tools read this)
├── CLAUDE.md                          # Project rules for Claude Code
├── SPRINT_TRACKER.md                  # Source of truth for tasks
├── opencode.json                      # OpenCode model config
├── .aider.conf.yml                    # Aider defaults
├── .env                               # API keys (gitignored)
├── .env.example                       # Template for API keys
├── .continue/
│   ├── config.yaml                    # Continue workspace config (rules, prompts, context)
│   ├── AGENT_CONTEXT.md               # Project context for agents
│   ├── IMPLEMENTATION_NOTES.md        # Execution log
│   ├── rules/                         # Auto-loaded rules for Continue
│   │   ├── 00-pharmaguide-core.md
│   │   ├── 01-pharmaguide-sprint.md
│   │   ├── 02-pharmaguide-safety.md
│   │   ├── 03-pharmaguide-flutter.md
│   │   └── 04-pharmaguide-file-targeting.md
│   ├── checks/                        # PR review checks
│   │   ├── sprint-dod-review.md
│   │   ├── deterministic-logic-review.md
│   │   ├── health-safety-review.md
│   │   └── flutter-task-scope-review.md
│   └── mcpServers/
│       └── playwright.yaml
├── .opencode/
│   └── agents/                        # Custom OpenCode agents
│       ├── sprint-worker.md
│       └── verifier.md
└── docs/
    └── AI_CODING_SETUP_GUIDE.md       # This file

Global configs:
~/.continue/config.yaml                # Continue models (Gemini, Groq, Local)
~/.continue/.continuerc.json           # Continue settings
~/.local/share/opencode/auth.json      # OpenCode API keys
~/.zshrc                               # API keys as env vars
~/.config/last30days/.env              # Research tool config
```

---

## API Keys Location

All stored in `~/.zshrc` (loaded on every terminal):
```
GEMINI_API_KEY                         # Continue, Aider
GOOGLE_API_KEY                         # Gemini CLI
GOOGLE_GENERATIVE_AI_API_KEY           # OpenCode
GROQ_API_KEY                           # Continue, Aider, OpenCode
```

Also in `.env` (project-level, gitignored):
```
GEMINI_API_KEY, GROQ_API_KEY, INCEPTION_API_KEY
UMLS_API_KEY, OPENFDA_API_KEY, PUBMED_API_KEY
DSLD_API_KEY, USDA_API_KEY
SUPABASE_URL, SUPABASE_ANON_KEY
```

---

## Troubleshooting

**Continue doesn't show models:**
- Models must be in `~/.continue/config.yaml` (global), not workspace
- Cmd+Shift+P -> "Reload Window" after config changes

**OpenCode says Google API key missing:**
- Make sure `GOOGLE_GENERATIVE_AI_API_KEY` is in `~/.zshrc`
- OR add `"apiKey"` field in `opencode.json` under the google provider
- Close terminal, open new one, try again

**Gemini CLI rate limited:**
- Uses Google account login, separate from API quota
- If limited, switch to `opencode` with Groq or local model

**Local model too slow:**
- Use Groq instead (cloud, free, 800 tok/s)
- Or reduce context: smaller files, fewer references

**ollama launch claude quality is bad:**
- Local models ARE less capable than Claude Opus
- Use kimi-k2.5:cloud for better quality (cloud model)
- For critical work, wait for Claude Code token reset
