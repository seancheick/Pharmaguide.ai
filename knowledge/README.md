# PharmaGuide Knowledge Base

> Map of Content (MOC) for the PharmaGuide Flutter app project.  
> This vault contains institutional knowledge, architectural decisions, and operational patterns.  
> Updated: 2026-04-07

---

## Core References

- [[lessons-learned]] -- Running log of mistakes, root causes, and prevention strategies. Updated by both humans and agents.
- [[architecture-decisions]] -- ADR log documenting key technical decisions and their rationale. Append-only.
- [[pipeline-reference]] -- Quick reference for pipeline data structures, table schemas, enums, and evidence levels.
- [[flutter-patterns]] -- Conventions and patterns specific to this Flutter app (state management, navigation, parsing, etc.).
- [[debugging-playbook]] -- Common issues encountered during development and step-by-step fixes.

---

## How to Use This Vault

1. **Before starting a sprint**, read [[architecture-decisions]] and [[pipeline-reference]] to understand constraints.
2. **When something breaks**, check [[debugging-playbook]] first before investigating from scratch.
3. **After fixing a non-trivial bug**, add an entry to [[lessons-learned]] and [[debugging-playbook]].
4. **When making a technical choice**, document it in [[architecture-decisions]] with context and alternatives considered.
5. **When establishing a new pattern**, add it to [[flutter-patterns]] so future agents and developers follow the same approach.

---

## External References

- Sprint tracking: `../SPRINT_TRACKER.md`
- Build plan: `../BUILD_PLAN.md`
- Pipeline export schema: `../FINAL_EXPORT_SCHEMA_V1.md`
- Flutter data contract: `../FLUTTER_DATA_CONTRACT_V1.md`
- Pipeline repo CLAUDE.md: contains scoring system details, data file inventory, and pipeline commands
