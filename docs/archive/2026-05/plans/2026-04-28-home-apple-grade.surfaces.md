# Home Surface Tier Audit — 2026-04-28

> Companion to `2026-04-28-home-apple-grade.md` (Task B1).

## Tier system (4 valid surfaces, not 3)

The original plan named 3 tiers (`hero`, `standard`, `recessed`). The codebase
actually has **4 valid tiers** because `PGCard` already ships a `highlighted`
variant for the single most-important callout on a screen. Suppressing it
into `recessed` or `plain` would lose semantic intent. The corrected tier
system is:

| Tier | Implementation | Cardinality | Use |
|---|---|---|---|
| **hero** | Bespoke gradient + drop shadow | **1 per screen** | The dominant primary action. Today: `home_scan_cta.dart` only. |
| **standard** | `PGCard(variant: PGCardVariant.plain)` or `.elevated` | Many | Default for any standalone content card. |
| **accent** | `PGCard(variant: PGCardVariant.highlighted)` | **0–1 per screen** | A soft brand-tinted nudge that wants attention but isn't blocking. Today: `home_profile_completeness_card.dart` only. |
| **recessed** | `PGCard(variant: PGCardVariant.recessed)` | Many | Quieter content (empty states, supporting panels). |

**Intra-card layout primitives** (`Container` with `BoxDecoration` *inside*
an already-tiered card — section dividers, tinted info chips, metric strips)
are NOT a fifth tier. They are layout building blocks of the parent card.
The tier rule applies to standalone surfaces.

## Audit findings (home, 2026-04-28)

| File | Line | Surface | Tier | Status |
|---|---|---|---|---|
| home_scan_cta.dart | 33–49 | Gradient + shadow CTA | hero | ✅ KEEP — singular hero confirmed |
| home_search_launcher.dart | 15–19 | `PGSearchField` (external) | standard (delegated) | ✅ KEEP |
| home_profile_completeness_card.dart | 19–82 | `PGCard(highlighted)` | accent | ✅ KEEP — singular accent confirmed |
| home_stack_health.dart | 47–95 | `PGCard(elevated)` empty state | standard | ✅ KEEP |
| home_stack_health.dart | 186–411 | `PGCard(elevated)` populated state | standard | ✅ KEEP |
| home_stack_health.dart | 254–287 | Insight chip — `Container` with `tone.withValues(alpha: 0.08)` background | intra-card primitive | ✅ KEEP — semantic-tinted info chip inside parent card |
| home_stack_health.dart | 293–334 | Micro-metrics row — `Container` with `surfaceContainerLow` + top border | intra-card primitive | ✅ KEEP — Settings-style footer-section pattern, theme-driven colors |
| home_stack_health.dart | 338–381 | Top-issue callout — `Container` with top border | intra-card primitive | ✅ KEEP — same footer-section pattern |
| home_recent_scans.dart | 142–190 | `PGCard(recessed)` empty state | recessed | ✅ KEEP |
| home_recent_scans.dart | 265–329 | `PGCard(plain)` carousel card | standard | ✅ KEEP |
| home_recent_scans.dart | 340–383 | `_OutlineScanButton` — `AnimatedContainer` pill (`radiusFull`) | button (non-card) | ✅ KEEP — pill shape, not a card |
| home_recent_scans.dart | 516–575 | `PGCard(plain)` sheet list tile | standard | ✅ KEEP |
| home_quick_check_cta.dart | 14–69 | `PGCard(plain)` | standard | ✅ KEEP |
| home_citation_strip.dart | 24–29 | `PGCitationStrip` (external) | standard (delegated) | ✅ KEEP |

**Singular-cardinality contracts:**
- ✅ Exactly **1 hero** (scan CTA)
- ✅ Exactly **1 accent** (profile completeness)

## Result

**0 migrations required.** The Sprint 27.18 redesign was already
materially compliant — every visible standalone surface uses one of the four
named tiers, and the cardinality constraints (1 hero, ≤1 accent) hold.

The plan's Task B2 ("Migrate non-conforming surfaces") therefore reduces to
a documentation task: codify the four-tier system in `PGCard`'s doc comments
so the next dev has the rule explicitly written, not just implied by usage.

## Carry-overs

- **B2:** Update `pg_card.dart` doc comments to spell out the four-tier
  contract (hero / standard / accent / recessed) and the "1 hero, ≤1 accent
  per screen" rule. Add a short paragraph in `app_theme.dart` near the
  surfaceContainer ladder pointing to PGCard for tier guidance.
- **B3:** Verify dark-mode surface ladder uses iOS systemGray-equivalent
  values (next task).
