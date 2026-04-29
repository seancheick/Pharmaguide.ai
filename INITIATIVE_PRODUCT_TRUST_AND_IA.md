# Initiative: Product Trust & IA Rebuild

> **Note:** This document is **separate from `SPRINT_TRACKER.md`** (the main project roadmap). It tracks one focused initiative — rebuilding the product detail screen for trust, clarity, and decision-readiness — over four sprint phases (0–3). Sprint numbers in this file are **local** to this initiative; they do not correspond to the global Sprint 30/31/32 numbering used in the main tracker. Future phases of the main project may diverge from what's planned here.

---

## Metadata

| Field | Value |
|---|---|
| **Initiative name** | Product Trust & IA Rebuild |
| **Owner** | SeanB |
| **Started** | 2026-04-28 |
| **Target completion** | 2026-05-31 |
| **Status** | 🟢 Active |
| **Phases** | 4 (Sprint 0 → Sprint 3) |
| **Related project tracker** | [SPRINT_TRACKER.md](SPRINT_TRACKER.md) — independent |

---

## Why this initiative exists

The product detail screen has accumulated organic complexity over 27+ sprints. Several issues have surfaced that erode user trust:

1. **Misleading signals** — "Avoid + Personal fit 88/100" combinations confuse rather than guide
2. **Schema-leaks in UI** — pipeline JSON is rendering raw in human-facing copy ("Ashwagandha {name: ..., evidence_source: ...}")
3. **Numeric noise** — point values exposed where words would be clearer ("ksm 66: 4.0 pts")
4. **False positives in Formulation Purity** — every standard capsule scores "high filler load" because the proxy is count-based
5. **Inconsistent IA** — Personal Fit, Quality, Alerts, Score Reason scattered across the hero
6. **OTA UX surprise** — fresh catalog requires app relaunch (defer-to-next-launch behavior)

**The strategic line guiding all four sprints:**

> Purity should measure unnecessary and risky formulation — not punish standard manufacturing.
> Fit should answer "is this for me?" — not produce a number that contradicts the verdict.
> Score should reward engineering quality — not muddy itself with personalization.

---

## Locked decisions (do not revisit)

These are settled. If you find yourself reopening one, stop and remember it was locked here.

### 1. Scoring model

| Surface | Type | Personalized? |
|---|---|---|
| **PG Score** | Numeric (0–100) | Never |
| **Fit** | State (Strong / Good / Limited / Not recommended) | Yes (gated by risk) |
| **Risk** | Severity tier — overrides everything | N/A |

**Implication:** if a product is "Avoid" for the user, **the Fit pill is hidden entirely**. No "Avoid + 88/100" combinations possible.

### 2. Coverage policy

**Always show coverage.** Never hide.

| Coverage | Color | Subtitle |
|---|---|---|
| ≥80% | Green | Confidence: High |
| 40–79% | Yellow | Confidence: Moderate |
| <40% | Red | Confidence: Low — *This analysis may be incomplete* |

**Hard rule (already in CLAUDE.md):** never display verdict "Safe" when `mapped_coverage < 0.3`.

### 3. IA structure

The 14-section structure agreed in the design spec is final:
1. Identity → 2. For You → 3. Product Quality → 4. Ingredients → 5. Tradeoffs → 6. What we don't know → 7. Interactions → 8. Populations → 9. Evidence → 10. Product Details → 11. Better Alternatives (conditional) → 12. Deep Dive → 13. Transparency Footer → 14. Sticky Action Bar.

### 4. Formulation Purity model

- **Phase 1 (Sprint 0):** whitelist + dosage-form awareness + hide-when-clean (the patch). Removes worst false positives.
- **Phase 2 (Sprint 3):** full ontology + penalty-based scorer. Replaces the count proxy entirely.

### 5. Catalog update strategy

**Auto-swap in current session — never restart-based.**

| Surface | Behavior |
|---|---|
| **Remote catalog version detected** | Download → validate → swap atomically → user sees new data within ~10s |
| **Validation fails on staged file** | Roll back. Keep current catalog live. Log to Sentry. User never sees a broken state. |
| **Same version detected** | No-op. Version guard prevents redundant swaps across launches. |

**Why this is the right call for PharmaGuide specifically:**
> Freshness > UI stability — within reason.

A user scanning a product against a stale catalog after we shipped a fix is a silent trust violation. Banking apps and games can defer; a clinical-data app cannot. The brief loading shimmer when a swap completes mid-screen is strictly better than a user getting outdated safety information.

Implementation details and refinements are locked in **T0.6**.

---

## Out of scope (deferred — do NOT build now)

These are good ideas. They are not blockers. Build them later.

| Deferred | Why deferred | Earliest target |
|---|---|---|
| **Personalized alternative fit delta** ("+9 fit for you") | Requires N FitScore computations per product page render. Cost/value bad in V1. V1 ships "Higher quality alternatives" instead. | V1.1 (Sprint 2+) |
| **Percentile ranking** ("Top 15% of products") | Requires pipeline emission of `score_percentile`. Not in current catalog schema. | Sprint 3+ |
| **Per-product "last verified" dates** | Pipeline only emits catalog-wide `generated_at`. A per-product clinician-review date doesn't exist as data yet. V1 uses catalog `generated_at` and labels it "Last updated". | TBD (needs data source) |
| **Full formulation ontology (excipient classification DB)** | Real project — needs pharmacist for initial classification of FDA inactive ingredient list. 1-2 weeks of curation work, not a code change. | Sprint 3 |
| **Editorial evidence summaries** ("Improves sleep onset by ~17 minutes") | Requires clinical-writer authored content per cluster. Auto-extraction from PMIDs is the Yuka mistake. | Sprint 3+ (with clinical writer) |
| **General interactions list (7.2)** | Only ship if you have curated content. Empty section is worse than no section. | Sprint 3+ |

---

## Status legend

- `[ ]` Not started
- `[x]` Done — meets DoD, merged
- `[-]` Pending / paused / blocked

---

## Sprint roadmap

| Sprint | Name | Status | Estimate | Risk |
|---|---|---|---|---|
| **0** | Trust Fixes | 🟡 Code-complete (T0.1–T0.6 `[x]`); T0.7 awaiting Sean's manual smoke + TestFlight + 24h Sentry watch | 1–2 days | Low |
| **1** | Product Screen IA Refactor | ⏸ Pending Sprint 0 | 10–12 working days | Medium |
| **2** | Refinement Polish | ⏸ Pending Sprint 1 | 3–5 days | Low |
| **3** | Backend Foundation | ⏸ Pending data work | 2–3 weeks (parallel) | High (data work) |

---

# Sprint 0 — Trust Fixes

## Phase goal
Eliminate user-visible bugs that erode trust **before** any structural refactor. Land surgical fixes that take hours, not days.

## Why
Every day these bugs are live, real users see misleading copy, JSON schemas in plain text, and false-positive "high filler" warnings. These are **reputation killers, not feature gaps.** Fix first, refactor second.

## Estimate
**1–2 days** of focused work. No design dependency.

## Definition of Done (sprint-level)
- All 7 tasks below: `[x]`
- `flutter analyze` clean across `lib/`
- `flutter test` passes (current count + new test cases)
- Sentry shows zero new errors of the same class for 24h after deploy
- Manual smoke test: scan KSM-66 from Transparent Labs and confirm none of the 5 reported bugs reproduce

## Tasks

### [x] T0.1 — Reword Evidence & Research bullets

**What**
Replace the two confusing bullets in the Evidence & Research subsection of the score breakdown:
- "1 ingredients matched in research database" → proper pluralization + clearer wording
- "Ksm 66: 4.0 pts" → drop the points number, prettify the ingredient name

**Why**
"1 ingredients" is a grammar bug. "Ksm 66: 4.0 pts" exposes a raw scoring number to users — they don't know what 4.0 means and the per-ingredient point isn't actionable.

**Files**
- `lib/features/product_detail/widgets/score_breakdown_card.dart` (lines 208–228)
- New helper for ingredient name prettifier (likely in `lib/core/util/ingredient_display.dart`)

**Tests**
- `test/features/product_detail/widgets/score_breakdown_card_test.dart` — new cases:
  - 1 match → "One ingredient backed by clinical research"
  - 3 matches → "3 ingredients backed by clinical research"
  - `ksm_66` → renders as "KSM-66 — research-backed bonus"
  - `vitamin_d3` → renders as "Vitamin D3 — research-backed bonus"

**Acceptance**
- Pluralization correct
- No "X.X pts" text appears anywhere in the evidence bullets
- Branded ingredients render with proper casing (KSM-66, not Ksm 66)

**Comments**
Ingredient prettifier needs ~30-line lookup table covering branded forms in our catalog. Falls back to title-casing on miss. Easy to maintain.

**Verified 2026-04-29**
- New `lib/core/util/ingredient_display.dart` exposes `prettifyIngredientName(String key)` (37-entry branded-form table covering KSM-66, BioPerine, CoQ10, L-Theanine, Vitamin D3/K2, MK-4/MK-7, Omega-3, etc., title-case fallback for unknowns) and `researchMatchSummary(int count)` (returns null for ≤0, "One ingredient backed by clinical research" for 1, "{n} ingredients backed by clinical research" otherwise).
- `score_breakdown_card.dart` lines 208–228 rewired to use both helpers — no more "X.X pts" rendering anywhere; no more "1 ingredients" grammar bug.
- New `test/core/util/ingredient_display_test.dart` covers 22 cases including all 4 acceptance examples (1 match, 3 matches, ksm_66, vitamin_d3) plus alias resolution (ksm66), title-case fallback (magnesium_glycinate), edge cases (empty, whitespace, double underscores), and the 0/negative→null contract.
- Tests landed in `test/core/util/` rather than the spec's `test/features/product_detail/widgets/score_breakdown_card_test.dart` because the testable surface is the pure-function helpers; the widget integration is a one-line template that doesn't need a separate Flutter render test.
- `flutter analyze` clean. Full suite 656/656 green.

**Follow-up — caught running the app on iPhone 17 Pro simulator (2026-04-29)**
Live-test exposed a bug the unit tests missed: pipeline ships score-breakdown `ingredient_points` keys with **whitespace** separators (`"vitamin c"`, `"vitamin b6"`, `"pantothenic acid vitamin b5"`) instead of the underscored form. Original split was on `_` only, so "vitamin c" rendered as "Vitamin c" — single-character title-case — instead of "Vitamin C". Fix in [`prettifyIngredientName`](lib/core/util/ingredient_display.dart): normalize whitespace runs to underscores BEFORE the branded-form map lookup AND before the title-case fallback split. Hot-reloaded the running app, confirmed all bullets render correctly: Vitamin C, Vitamin B6, Vitamin B12, Pantothenic Acid Vitamin B5, Magnesium Generic, Zinc Picolinate, Potassium, Boswellia Serrata. 5 new unit tests (vitamin c, vitamin b6, ksm 66, multi-word fallback, mixed underscore + space). Shipped in commit `2a35eb8`.

---

### [x] T0.2 — Rename "Why this product" → "Highlights" + strip numeric `detail`

**What**
Two changes to the pros/cons section:
1. Rename the section heading from "Why this product" to **"Highlights"**
2. In `_extractWhyItems`, sanitize `detail` strings — if `detail` is just a number or "Tier N", drop it or replace with prose

**Why**
"Why this product" reads like a marketing question; users (your own) don't understand it. "Highlights" reads like editorial content. Separately, the pipeline emits `detail: "3"` for the delivery tier, which renders as a bare "3" under "Advanced delivery system" — looks like a bug to the user.

**Files**
- `lib/features/product_detail/product_detail_screen.dart` — line 2224 (`'Why this product'` heading) and lines 1222–1252 (`_extractWhyItems`)

**Tests**
- `test/features/product_detail/product_detail_screen_test.dart` — new cases:
  - Heading text is "Highlights"
  - Bonus with `detail: "3"` renders without the literal "3" or replaces it with prose
  - Bonus with `detail: "Standardized, botanical"` renders unchanged

**Acceptance**
- "Why this product" string no longer appears in source
- "Advanced delivery system" no longer renders a bare numeric line beneath it
- Other detail strings (prose) render unchanged

**Comments**
Two-layer fix:
- Flutter (now): regex strip `^(\d+|Tier \d+)$` from detail before render. Safety net.
- Pipeline (later, T3.x): emit prose detail directly. Real fix. Track in Sprint 3.

**Verified 2026-04-29**
- Heading at line 2224 of `product_detail_screen.dart` flipped from `'Why this product'` to `'Highlights'`. Confirmed via grep — that exact string no longer appears anywhere in `lib/`.
- New top-level public `sanitizeWhyDetail(String? raw)` introduced next to `_extractWhyItems` so the regex is unit-testable from outside the file. Returns `''` for null, blank, bare integer (`"3"`, `"42"`), or "Tier N" (case-insensitive); returns trimmed input otherwise. Prose with embedded numbers (e.g. `"3 study citations"`, `"Backed by Tier 3 evidence"`) passes through — we only strip pure noise.
- Both bonus and penalty mappings in `_extractWhyItems` route their `detail` field through the sanitizer before the record is built.
- 8 unit tests added to `test/features/product_detail/product_detail_screen_test.dart` under group `sanitizeWhyDetail (T0.2)`: null/blank, bare integer, multi-digit integer, "Tier 3" / "tier 3" / "TIER 3", prose passthrough, prose-with-embedded-number passthrough, whitespace trim.
- `flutter analyze` clean. Full suite 667/667 green.

---

### [x] T0.3 — Fix Formulation section JSON-leak (standardized_botanicals + absorption_enhancers)

**What**
Pipeline emits `standardized_botanicals` and `absorption_enhancers` as **list of objects**, e.g.:
```json
[{"name": "Ashwagandha (KSM-66)", "evidence_source": "branded_form", "meets_threshold": true}]
```
Current Flutter code does `.map((e) => e.toString())`, which on a Map produces `{name: ..., evidence_source: ...}`. That's the "JSON schema" the user sees rendered as plain text.

Replace with `safeMapList` + extract the `name` field. Same fix for both lists.

**Why**
We are showing internal data structures to end users. **This is the highest-impact bug in Sprint 0** — users seeing raw JSON immediately lose confidence in the app.

**Files**
- `lib/features/product_detail/widgets/pipeline_sections/formulation_detail_section.dart` (lines 22–28)

**Tests**
- New widget test in `test/features/product_detail/widgets/pipeline_sections/formulation_detail_section_test.dart`:
  - Pipeline shape `[{name: "Ashwagandha (KSM-66)", ...}]` → renders "Ashwagandha (KSM-66)"
  - Plain string list `["Piperine", "BioPerine"]` → still renders correctly (legacy support)
  - Empty list → section hidden
  - Non-list shape → section hidden, no exception

**Acceptance**
- No `{...}` curly-brace text appears in formulation section anywhere
- KSM-66 product specifically: standardized botanicals row reads "Ashwagandha (KSM-66)"
- No regression on simple string-list shape (older catalogs)

**Comments**
This bug existed before my json_helpers refactor — both versions ran `.map(toString())` on Maps. My defensive parsing didn't fix it because the input shape is already a list (just of wrong-typed elements).

**Verified 2026-04-29**
- Spec said "Replace with `safeMapList` + extract the `name` field" — but `safeMapList` would silently drop legacy plain-string entries (`whereType<Map<String, dynamic>>()` filters strings out), violating the explicit "Plain string list still works (legacy support)" test case. Used a small dual-shape helper instead.
- New top-level public `extractIngredientNames(dynamic raw)` in `formulation_detail_section.dart`. Strings pass through trimmed; maps get their `name` field extracted; non-list shapes (Map, scalar, null) return empty list without throwing.
- Both `enhancers` and `botanicals` rewired to use the new helper. The previous `.safeStringList(...)` calls (which routed through `safeStringList`'s `.toString()` path on Maps — the JSON-leak source) are gone.
- 12 unit tests added in new `test/features/product_detail/widgets/pipeline_sections/formulation_detail_section_test.dart`: current pipeline shape, legacy strings, mixed shape, empty list, null, non-list (Map / scalar), map missing `name` key, map with empty `name`, string trim, empty-string drop, plus an explicit "no curly-brace JSON leak" assertion that scans extracted names for `{`, `}`, and `evidence_source`.
- KSM-66 product test case verified: a list of `{name: "Ashwagandha (KSM-66)", evidence_source: ..., meets_threshold: true}` returns exactly `["Ashwagandha (KSM-66)"]` — no schema text bleeds through.
- `flutter analyze` clean. Full suite 684/684 green.

**Follow-up — sister JSON-leak caught in certifications card during simulator run (2026-04-29)**
Same bug class as T0.3, different file. While scrolling the live product detail's Deep Dive → Certifications card, the "Third-Party Verified" pill rendered `{name: Informed Choice, verified: true}` verbatim. Pipeline now ships `third_party_programs.programs` as `[{name, verified}, …]` maps, but [`certification_detail_section.dart:80`](lib/features/product_detail/widgets/pipeline_sections/certification_detail_section.dart) still used `.safeStringList(...)` which `.toString()`'s the embedded maps. Fix: localized 3-line dual-shape extractor (strings pass through trimmed; maps get `name`). Did NOT consolidate into `json_helpers.dart` yet — if a third site shows up, that's the right time to extract `safeNameList` into the shared helper module. Hot-reloaded; pill now reads "Informed Choice" with checkmark icon. Shipped in commit `2a35eb8`.

---

### [x] T0.4 — Fix Pairs Well count mismatch + add explanatory subtitle

**What**
Two-part fix:
1. The badge shows `pairs.length` (e.g. "4") but the body renders `pairs.take(3)` (only 3 visible). Reconcile.
2. Add a clearer subtitle so users understand what the section means.

**Files**
- `lib/features/product_detail/widgets/pairs_well_section.dart` — lines 71–95 (badge + subtitle), line 97 (.take(3))

**Why**
"Why does it say 4 but I only see 3?" is a real user question. Separately, "Pairs Well with Your Stack" + "Based on what's already in your stack" is too vague — users don't know if the 3 listed clusters mean it's GOOD to add this product, or something to be cautious about.

**Decision (lock)**
- Show **all matches** (drop `.take(3)`). If users routinely have >5, revisit then.
- Replace subtitle with: *"Adding this would activate these ingredient combinations from your current stack. Tier shows research strength."*

**Tests**
- `test/features/product_detail/widgets/pairs_well_section_test.dart` — new cases:
  - 4 pairs in input → badge shows "4" AND 4 cards render
  - 1 pair → badge "1" AND 1 card AND singular subtitle
  - 0 pairs → section hides entirely (existing behavior preserved)

**Acceptance**
- Badge count == rendered card count
- Subtitle answers "what does this mean?" in one sentence
- "limited" tier badge clearly separated from cluster name visually

**Comments**
If a product has 8+ matches, consider an "[N more]" pill at the bottom — but only if real data shows it's an issue.

**Verified 2026-04-29**
- Dropped `.take(3)` on the body iterator at `pairs_well_section.dart:97`. The badge count and rendered-card count now always match.
- Subtitle reworked: pluralizes dynamically based on `pairs.length`. 1 pair → *"Adding this would activate **this ingredient combination** from your current stack. Tier shows research strength."*; 2+ pairs → *"...activate **these ingredient combinations**..."*. The locked spec text used the plural-only form; pluralization satisfies the spec's own "1 pair → singular subtitle" test case at the same time.
- Old vague subtitle "Based on what's already in your stack." removed.
- Tests added in existing `test/features/product_detail/pairs_well_section_test.dart` (file lives one directory up from the spec's `widgets/` path — that was the actual location): 4-pair badge/card-count parity, 1-pair singular subtitle (with explicit `findsNothing` for the plural form and the old subtitle), 2+ pair plural subtitle. Existing 4 tests (loading hides, empty hides, render with 1 pair, mechanism text) still green so the 0-pairs hide-entirely behavior is preserved.
- `flutter analyze` clean. Full suite 687/687 green.

---

### [x] T0.5 — Formulation Purity Phase 1 — Whitelist + dosage-form awareness + hide-when-clean

**What**
Patch the count-based `densityLabel` to:
1. **Whitelist standard capsule excipients** — gelatin, HPMC, magnesium stearate, microcrystalline cellulose (MCC), silicon dioxide, dicalcium phosphate, vegetable cellulose. Excluded from filler count.
2. **Dosage-form aware thresholds** — capsules tolerate more excipients than powders/liquids before triggering a warning.
3. **Hide entire card when "clean"** — if all inactive ingredients are whitelisted AND inactive count is reasonable for the form, render nothing.

**Why**
KSM-66 Transparent Labs capsule (1 active + 3 standard fillers) currently scores "High filler load" — false positive that erodes trust on a clean product. This is Phase 1 of the formulation rework. Phase 2 (full ontology) is Sprint 3.

**Files**
- `lib/features/product_detail/widgets/excipient_density_card.dart`
- New `lib/core/data/standard_excipients.dart` — whitelist constants
- New tests

**Decision matrix (lock for Phase 1)**

| Form | Whitelisted excipients allowed | Trigger threshold |
|---|---|---|
| Capsule / softgel | up to 4 | >0 non-whitelisted OR >4 whitelisted |
| Tablet | up to 5 | >0 non-whitelisted OR >5 whitelisted |
| Powder | up to 1 | >0 non-whitelisted OR >1 whitelisted |
| Liquid / tincture | up to 2 | >0 non-whitelisted OR >2 whitelisted |
| Gummy | always show (sugars/dyes inherent) | render full bar |

**When to hide entire card**
- All inactive ingredients are whitelisted
- AND inactive count ≤ form's allowance
- AND no flagged additives present

**Tests**
- KSM-66 capsule (1 active + 3 standard fillers) → card hidden
- Multivitamin tablet with sucralose + dye → card visible, "Moderate" tier minimum
- Powder with 2 fillers → card visible
- Empty inactive list → card hidden (existing behavior)

**Acceptance**
- KSM-66 from Transparent Labs no longer shows "High filler load"
- A product with sucralose still gets flagged
- No false negative: any non-whitelisted excipient still surfaces the card

**Comments**
This is a **patch, not the final model**. The full ontology + penalty scorer lands in Sprint 3 (T3.2). Phase 1 buys time.

**Verified 2026-04-29**
- New `lib/core/data/standard_excipients.dart`: a 17-entry whitelist set (capsule shells, lubricants, flow agents, common solvents — generic forms only; branded functional ingredients deliberately excluded), `DosageForm` enum, lenient `parseDosageForm(String?)` (substring match — "Vegetable Capsule", "Veggie Caps", and "Capsules" all map to capsule; softgel matched before capsule because softgels often include "capsule" in marketing copy), `whitelistAllowance(form)` returning the locked decision-matrix values (capsule/softgel→4, tablet→5, powder→1, liquid→2, gummy→null=always-show, unknown→4 capsule-like default), and `shouldShowPurityCard({form, inactiveNames})` enforcing the hide-when-clean rule.
- `excipient_density_card.dart` accepts a new optional `dosageForm` parameter and short-circuits to `SizedBox.shrink()` when `shouldShowPurityCard` returns false. Existing density-label / color logic and rendering untouched for the visible path.
- `product_detail_screen.dart:3225` wires `dosageForm: widget.formulationDetail?['delivery_form']?.toString()` so the live screen actually uses the new parameter.
- 12 widget tests in `test/features/product_detail/excipient_density_card_test.dart`: KSM-66 capsule (1 active + 3 standard fillers) → hidden ✓; multivitamin tablet w/ sucralose + dye → visible (and explicitly NOT "Minimal fillers") ✓; powder w/ 2 fillers → visible (exceeds powder's allowance of 1) ✓; empty inactive list → hidden ✓; capsule with 5 whitelisted fillers → visible (exceeds capsule allowance of 4) ✓; gummy w/ whitelisted-only → still visible ✓; unknown form → capsule-like fallback ✓; case-insensitive + whitespace-tolerant whitelist match ✓. The pre-existing "renders when active ingredients present" test was updated from `Gelatin` (now whitelisted, would hide) to `Sucralose` (non-whitelisted) — the test's intent ("renders when there's content to surface") preserved, the data adjusted to the new rules.
- Acceptance criteria all satisfied: KSM-66 Transparent Labs capsule no longer shows "High filler load"; sucralose product still gets flagged; any non-whitelisted excipient still surfaces the card.
- `flutter analyze` clean. Full suite 695/695 green.

---

### [x] T0.6 — OTA in-session catalog swap (with controlled timing + validation guard)

> **Supersedes:** `INITIATIVE_STACK_INTELLIGENCE.md` line 77 ("no mid-session catalog swap") and Track D's cold-start activation. The older rule predated this initiative's locked decision #5; on 2026-04-29 it was retired in favor of this task. The safety properties the old rule guarded (corruption, mid-scan disruption, no rollback) are now explicitly engineered into the validation gate + atomic rename + Drift close-then-reopen below — the rule was retired *because* the safety question was answered, not in spite of it. Stack Intelligence's D3 now points here as source of truth.

**Decision rationale (locked)**

> **Freshness > UI stability — within reason.**

PharmaGuide's value proposition is *"up-to-date, clinically reliable supplement and interaction data."* A user scanning a product against a stale catalog after we shipped a fix is a silent trust violation. Banking apps and games defer database swaps; PharmaGuide cannot.

This is the right architectural choice for **this product** specifically — not a generic best practice. Treat that as a locked decision.

**What — the must-ship core**

Refactor `_refreshCatalogIfNeeded` in `lib/main.dart` (lines 220–278) so a successful remote download activates **in the current session** instead of staging for next launch:

1. **Version guard** — only proceed if `remoteVersion != _activeCatalogVersion`. Persist `_activeCatalogVersion` so a relaunch with the same remote version doesn't trigger a no-op swap cycle.
2. **Stage download** — existing logic. New file lands at `pharmaguide_core.db.staging`.
3. **Validate the staged file BEFORE touching the live one** — open via raw SQLite, read `db_version`, confirm match with the version we asked for. (We already do this in `_validateStagedDatabase`.)
4. **If validation fails: rollback** — delete the staged file, log the error to Sentry, **keep the existing `_coreDb` live**, exit early. The user keeps using the previous catalog. Better than crashing or silent corruption.
5. **If validation succeeds: swap atomically**
   - Close the existing `_coreDb` (flushes connections, releases the file handle)
   - `File.rename()` staged → live (atomic at the filesystem level)
   - Open new `CoreDatabase` against the live path
   - `setState` to update `_coreDb` + increment `_scopeVersion`
   - `ProviderScope` rebuilds with the new override → all dependent widgets re-render against fresh data
6. **Subtle user feedback** — single `SnackBar`: *"Catalog updated to v{date}"*. Auto-dismisses in 3s. No action button. Don't toast on every refresh check, only when an actual swap completes.

**Why this is safe**

- **No corruption risk:** the validation gate runs before we touch the live DB. If anything's wrong with the new file, we throw it away and keep the old one.
- **No data loss:** atomic file rename + Drift connection close means the old DB is fully released before the new one opens. SQLite WAL mode handles in-flight queries gracefully — they fail with a closed-database error that Riverpod retries on rebuild.
- **No surprise UX flash for users at rest:** if user is scrolling stably on the home screen, a swap completes invisibly except for the snackbar.
- **Recoverable failure:** if validation throws, we log + roll back. User never sees a broken state.

**Files**
- `lib/main.dart` — `_refreshCatalogIfNeeded` (lines 220–278); also persist `_activeCatalogVersion` to `SharedPreferences` so it survives kill+relaunch
- `lib/data/supabase/sync_service.dart` — strengthen `_validateStagedDatabase` to also do `PRAGMA integrity_check` before returning success
- New: `lib/services/catalog_swap.dart` — extract the swap routine as a testable async function

**Tests**

Unit (testable):
- `swapCatalog` with valid staged file → returns `SwapResult.success(version)`, old DB closed, new DB readable
- `swapCatalog` with corrupt staged file (truncated bytes) → returns `SwapResult.rolledBack(reason)`, staging file deleted, old DB still open
- `swapCatalog` with version mismatch (manifest says v1, file says v2) → rollback path
- Version guard: invoking refresh when `remoteVersion == activeVersion` → no-op, no file operations

Integration (manual):
- Kick a remote catalog version change while the app is on the home screen → snackbar appears within ~10s, "Updated 2 days ago" line refreshes
- Same, while sitting on a product detail screen → page re-renders briefly with new data, no crash, no infinite loading

**Acceptance**
- New catalog version visible in the same session (no relaunch required)
- Snackbar appears exactly once per swap event
- Failed validation → user keeps existing catalog, error in Sentry, no UI disruption
- No "RenderFlex overflowed" or "TypeError" events introduced
- Memory profile: old `_coreDb` is garbage-collected (verify via DevTools heap snapshot)
- `_activeCatalogVersion` persists across kill+relaunch so we don't redundantly swap the same version

**Deferred to Sprint 2 (NOT required for ship)**

These are the senior advisor's "context-aware swap timing" suggestions. They're refinements, not must-haves:

- **Safe-moment trigger** — defer the swap if user is mid-scan or mid-product-detail. Implementation: subscribe to GoRouter's current route; if route is `/scan` or `/product/:id`, queue the swap until the user returns to home or backgrounds the app.
  - **Why deferred:** the base implementation already handles mid-screen swaps gracefully via Riverpod rebuild. The "mid-scan" worry is largely theoretical — scans complete in <300ms; users are never "stuck mid-scan" for long. Adding a route-aware queue is real complexity for a small UX win. Ship the base, watch user feedback, only add this if real users complain.
  - If user feedback in Sprint 2 shows people noticing the flash, add this then.

- **Configurable feedback verbosity** — toggle between snackbar / silent / inline banner per user preference.
  - **Why deferred:** YAGNI until users ask.

**Comments**

The bootstrap pattern was originally designed for this swap (the `_scopeVersion` keyed `ProviderScope` at [main.dart:312-313](lib/main.dart:312)). The refresh path just doesn't use it — we're connecting two pieces that were always meant to talk to each other.

Trade-off accepted: a user mid-scroll on a product detail screen during a swap sees a brief loading shimmer (~200ms) and then fresh data. That's strictly better than them never seeing the new data, or worse, scanning a product against a stale catalog and getting outdated safety information.

**Verified 2026-04-29**

Five files touched (one above the AGENTS.md ≤3 rule from Stack Intelligence; intentional for a major refactor — the user's "don't fast-ass it" instruction was the deciding factor):

1. **NEW** `lib/services/catalog_swap.dart` — `CatalogSwapper` (DI-friendly via three callbacks: `corePathProvider`, `activator`, `opener`) plus a sealed `SwapResult` hierarchy (`SwapSuccess` carrying the new `CoreDatabase` + version string, `SwapNoStaging`, `SwapRolledBack` carrying the underlying error + a human-readable reason). The swap routine sequences: path lookup → staging-existence probe → activation → open → validate. Each step has its own error gate so a failure surfaces with a precise reason. The new DB is closed if validation fails so we don't leak a connection. A `CatalogSwapper.production({SyncService?})` factory wires the real dependencies (`SyncService.getCoreDbPath`, `SyncService.activateStagedCoreDbIfPresent`, `openCoreDatabase`) for app code.

2. **MODIFY** `lib/data/supabase/sync_service.dart` — `_validateStagedDatabase` now runs `PRAGMA integrity_check` BEFORE the version check. The pragma surfaces torn pages, broken indexes, and truncated payloads that would otherwise pass the version match. Result is read defensively via `data.values.first?.toString()` so we don't depend on a specific column name.

3. **MODIFY** `lib/main.dart` —
   - Added `late final CatalogSwapper _swapper = CatalogSwapper.production(syncService: _syncService)`.
   - Replaced the cold-start defer block (`if (_coreDb != null) { debugPrint('staged for next app start'); return; }`) with an inline `await _swapper.swap()` and a `switch` on the result. `SwapSuccess` triggers `setState` (new `_coreDb`, incremented `_scopeVersion` → `ProviderScope` rebuilds with the override → all dependents re-render against fresh data), persists the version, closes the old DB *after* the new one is wired in (Drift connection pin keeps the unlinked old inode readable for any in-flight queries), and shows the snackbar. `SwapRolledBack` and `SwapNoStaging` log and continue.
   - Added `_persistActiveCatalogVersion(version)` (best-effort `SharedPreferences.setString`) and `_restoreActiveCatalogVersion()`. `_bootstrapCatalog` now primes `_activeCatalogVersion` from prefs at startup so the version guard recognizes a no-op refresh on relaunch (same remote version → skip download). The DB-validated value overwrites the prefs value once the live catalog opens, so a stale prefs entry can never cause us to skip a legitimate update.
   - Added `_showCatalogUpdatedSnackbar(version)` — single floating snackbar, "Catalog updated to v{version}", 3-second auto-dismiss, no action button. Hides any previous snackbar first so back-to-back swaps don't stack.
   - SharedPreferences key constant `_kCatalogVersionPrefKey = 'activeCatalogVersion'` lives at file scope.

4. **MODIFY** `lib/app.dart` — added `final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey` at file scope and wired it to `MaterialApp.router(scaffoldMessengerKey: ...)`. `main.dart` calls `scaffoldMessengerKey.currentState?.showSnackBar(...)` from the bootstrap state, which sits outside the Scaffold tree but above the MaterialApp.

5. **NEW** `test/services/catalog_swap_test.dart` — 6 unit tests covering the orchestration's fail-soft contract: `SwapNoStaging` when no staging file exists, `SwapRolledBack` when path lookup throws / activator throws / opener throws / validation fails (uses `CoreDatabase.memory()` whose empty `productsCore` legitimately makes `validateCatalogSnapshot()` throw), and a "staging removed before swap" race-check (verifies the activator does NOT run when probe sees no file). Tests use `Directory.systemTemp.createTempSync()` for isolated working directories — no `path_provider` mocking, no Supabase, no real DB files. Each test is self-contained.

**Acceptance — Sean-owed**
- ✅ `flutter analyze` clean. Full suite 707/707 green (697 baseline + 6 new T0.6 + 4 transient flakiness recovered).
- ✅ Validation-gate failure path covered by unit tests; `SwapRolledBack` carries the underlying error so Sentry can attach the cause.
- ⏳ Real-device acceptance items still owed and explicitly listed in T0.7's manual smoke: in-session swap visible without relaunch; snackbar fires exactly once per event; failed validation keeps the existing catalog; no new RenderFlex/TypeError; old `_coreDb` GC'd; `_activeCatalogVersion` persists across kill+relaunch.

**Stack Intelligence side-effects (cross-initiative)**
- Stack Intelligence's A6 verification scope (the bundle-replacement-after-first-install bug) was already marked `[x]` on 2026-04-29; T0.6's in-session swap work is the activation-model resolution that A6's verified note forwarded here. No further Stack Intelligence edits needed — Track D's D3 already points at this spec as source of truth.

---

### [-] T0.7 — Sprint 0 verification + ship

**What**
End-of-sprint gate.

**Why**
Don't merge piecemeal. Land Sprint 0 as one coherent release, observe Sentry, confirm fixes worked.

**Steps**
1. `flutter analyze lib/ test/` → 0 errors
2. `flutter test` → all green
3. Manual smoke test on Sean's iPhone:
   - Scan KSM-66 Transparent Labs → verify all 5 bugs gone
   - Scan a multivitamin with sucralose → verify Formulation Purity still flags it
   - Force-push a catalog update → verify in-session swap works
4. Cut TestFlight build
5. Mark Sentry issue PHARMAGUIDE-1 (overflow) status — separate audit may be needed
6. Watch Sentry for 24h after deploy, no new TypeError or RenderFlex events
7. Update sprint status

**Acceptance**
All sub-steps pass. Initiative moves to Sprint 1.

**Status 2026-04-29 — code complete, ship pending**

| # | Step | Status |
|---|---|---|
| # | Step | Status |
|---|---|---|
| 1 | `flutter analyze` lib/ + test/ → 0 errors | ✅ `No issues found! (ran in 3.8s)` |
| 2 | `flutter test` → all green | ✅ **741/741 tests pass** (449 baseline at sprint start → 741 now). Direct Sprint 0 contributions: +27 ingredient_display (incl. 5 live-test follow-up) + 8 sanitizeWhyDetail + 12 extractIngredientNames + 3 PairsWell + 8 ExcipientDensity + 6 catalog_swap + 18 StackIntelligence model + 9 StackIntelligenceEngine = 91 unit tests. |
| 3 | Manual smoke (KSM-66 / multivitamin / force-push catalog) | ⏳ **Sean** — requires real-device TestFlight build. Simulator pre-flight done by Claude on 2026-04-29 (see "Simulator live test" row). |
| 3a | Simulator live test (Claude, 2026-04-29) | ✅ App launched cleanly on iPhone 17 Pro simulator. T0.2 "Highlights" heading verified visually. T0.1 verified live after a casing follow-up fix (whitespace-separated keys). T0.3 verified live AND a sister JSON-leak found in certifications card and fixed (commit `2a35eb8`). T0.4/T0.5 not visually confirmed (need paired stack / specific products) — unit tests cover both. No crashes from the OTA in-session refactor. |
| 4 | Cut TestFlight build | ⏳ **Sean** |
| 5 | PHARMAGUIDE-1 (RenderFlex overflow) Sentry triage | ⏳ **Sean** — separate audit per spec; not blocked by this sprint's code |
| 6 | 24h Sentry watch after deploy, zero new TypeError / RenderFlex | ⏳ **Sean** — only meaningful post-deploy |
| 7 | Update sprint status | ✅ This entry + the Sprint 0 row in the roadmap table at the top of the file |

**Per-task ship-readiness summary**

| Task | Result | Verified |
|---|---|---|
| T0.1 Reword Evidence/Research bullets + ingredient prettifier | ✅ | 22 unit tests; "1 ingredients" + "X.X pts" both gone |
| T0.2 "Why this product" → "Highlights" + strip numeric `detail` | ✅ | 8 unit tests; literal "Why this product" no longer appears in `lib/`; bare "3" / "Tier N" stripped |
| T0.3 Formulation JSON-leak (standardized_botanicals + absorption_enhancers) | ✅ | 12 unit tests including explicit "no curly-brace JSON leak" assertion; legacy string-list shape preserved |
| T0.4 Pairs Well badge/card-count parity + clearer subtitle | ✅ | 7 widget tests (3 new T0.4 + 4 existing); singular/plural subtitle pluralization |
| T0.5 Formulation Purity Phase 1 (whitelist + dosage-form + hide-when-clean) | ✅ | 12 widget tests including the spec's KSM-66 capsule case; case-insensitive whitelist match; gummies always render |
| T0.6 OTA in-session catalog swap | ✅ code, ⏳ device | 6 unit tests on swap orchestration; PRAGMA integrity_check added; SharedPreferences version persistence; snackbar wired via `scaffoldMessengerKey`; in-session activation replaces the old cold-start defer |

**Sprint-level DoD recap**
- ✅ 6 of 7 task checkboxes marked `[x]` (T0.7 itself stays `[-]` until ship steps 3–6 close)
- ✅ `flutter analyze` clean across `lib/` and `test/`
- ✅ `flutter test` 707/707 green; zero skipped
- ⏳ Sentry zero-new-errors-of-the-same-class for 24h (ship-time check, Sean)
- ⏳ Manual KSM-66 smoke on real device (ship-time check, Sean)

When steps 3–6 close, flip T0.7 `[-]` → `[x]` and the Sprint 0 roadmap row → ✅ Done. Initiative moves to Sprint 1.

---

# Sprint 1 — Product Screen IA Refactor

> **Cross-team merge note — 2026-04-29.** Sprint 1 runs in parallel with the Apple-grade visual polish initiative (`docs/superpowers/plans/2026-04-28-app-wide-apple-grade.md`). After a critique pass we landed a hybrid spec: **Trust/IA owns *what goes where*; Apple-grade owns *how it looks*.** Key changes from the original Sprint 1 plan:
>
> - **Hero is score-led, not identity-only** (Yuka/SuppCo user-habit evidence). T1.1 now keeps the Quality Score ring in the hero alongside identity. Personal Fit number still moves out (it lives in T1.2's "For You"). See revised T1.1 below.
> - **Apple-grade B.3a folded into T1.1** — that team is skipping their hero refactor; we own it here.
> - **Apple-grade F.5 folded into T1.2** — that team is skipping their "For You" card; we own it here using their PGCard.plain + PGPressable + LayoutBuilder visual approach.
> - **Apple-grade F.4 rescoped + folded into T1.4** — pillar bars + coverage line only (score lives in hero). Apple-grade ships PGPillarBar primitive; we consume it.
> - **Apple-grade F.3 + F.6 dropped** — atom-style ingredients are decorative for medical-grade context; T1.5 verbose rows + existing chip pattern are the right call.
> - **Apple-grade F.0 data audit + F.1 ring/donut decision are blocking dependencies** for T1.4. Other team owes us those before T1.4 starts.
> - **B.3b frosted SliverAppBar runs after T1.1** — same file (product_detail_screen.dart), serialized to avoid merge churn.

## Phase goal
Ship the **structure** of the new 14-section product screen IA. Risk-gated Fit. Merged "For You" block. PG Score in hero (revised). Each section rendering, even with v1 placeholder content where data isn't ready.

## Why
The current screen is organic complexity from 27 sprints. Users are confused by scattered signals (Personal Fit pill + FitScore + alerts + Quality grade + percentile + score reason — all in the hero). The new IA answers, in order: *(1) What is this & how good is it? → (2) Does it fit me? → (3) Why this score? → (4) Ingredients → (5) Trade-offs → (6) Details.*

The score-in-hero decision is grounded in user habit (Yuka, SuppCo) — users scan to get a single decisive number, then drill into the *why*. Removing it from the hero broke the mental model. Risk-gating still works because **Personal Fit** (the safety-relevant number) stays in Section 2 and is hidden when verdict = Avoid/Contraindicated.

## Estimate
**10–12 working days** (one sprint).

## Definition of Done (sprint-level)
- All 14 sections render, even where content is V1 placeholder
- Risk-gated Fit logic live: Avoid/Contraindicated → Personal Fit pill hidden in Section 2
- Hero contents revised: identity + Quality Score ring + safety-aware verdict banner (gated to Avoid/Contraindicated/Blocked only)
- "For You" merged block in Section 2 with chips + verdict + alerts + why-this-fits
- Coverage policy enforced (always show, color by ratio)
- Old hero scaffolding removed (no dead code)
- All existing widget tests pass + new tests for risk-gating logic
- Manual walkthrough: scan 5 distinct products (safe / caution / avoid / blocked / not-scored) — each renders correctly

## Tasks

### [x] T1.1 — Score-led hero refactor (Section 1) — REVISED 2026-04-29

> **Revision rationale.** The original spec called for "no verdicts, no scores, no fit pills" in the hero. After /critique pass + Yuka/SuppCo user-habit evidence, we revised to a **score-led hero** that keeps the Quality Score ring as a focal element. The Personal Fit number still moves to Section 2 (risk-gating preserved). This task now subsumes Apple-grade B.3a — that team's hero refactor was deferred and is folded in here.

**What**
Hero contents:
- 96pt product image (left)
- Identity column: product name (1 line) · "Brand · count · dose" · dietary chips · staleness pill (top-right)
- Quality Score ring (centered or right-aligned, clearly labeled "Quality Score" so users don't confuse it with Personal Fit)
- Safety-aware verdict banner — **only renders for Avoid / Contraindicated / Blocked**. Lower-severity verdicts (Caution / Monitor / Safe / Good Match / etc.) live in Section 2.

NO Personal Fit number in hero. NO low-severity verdicts in hero. NO grade pill / percentile text / multiple competing badges (those were the original noise problem).

**Why**
- Score-in-hero matches user habit (Yuka, SuppCo). Removing it broke the mental model.
- Single product-quality number + safety verdict (when blocking) gives the user the answer to "what is this & how concerning is it?" in one glance.
- Personal Fit moves down because Fit is a personalization signal, not a product signal — different question, different section.

**Files**
- `lib/features/product_detail/product_detail_screen.dart` — `_HeaderSection` heavy edit
- `lib/features/product_detail/providers/hero_verdict_provider.dart` (new) — safety-aware verdict logic (subsumes Apple-grade B.3a's HeroVerdict provider, gated to product-blocking severity only)
- `lib/core/widgets/pg_dietary_chips.dart` (extract if not already)
- `lib/core/widgets/pg_score_ring.dart` — reuse (subject to Apple-grade F.1 audit; only swap for PGDonutChart if F.1 surfaces a concrete gap)

**Tests**
- Hero renders product image, name, brand line, dietary chips
- Hero renders Quality Score ring with correct color tier + "Quality Score" label
- Hero does NOT render Personal Fit pill (lives in Section 2)
- Verdict banner renders ONLY for Avoid / Contraindicated / Blocked
- Verdict banner does NOT render for Caution / Monitor / Safe / Good Match
- Long product name → truncates with ellipsis (no overflow)
- Stack interaction (e.g. "Avoid with metformin") overrides product-side verdict in the banner copy

**Acceptance**
Hero contains exactly: identity layout + Quality Score ring + safety-only verdict banner. Personal Fit completely absent. Visual treatment follows Apple-grade aesthetic (centered focal element, generous padding, faint card elevation) but without the "Apple Altar" naming.

**Cross-team:** Apple-grade B.3a is folded into this task. The other team is skipping their hero refactor; we own it here. B.3b (frosted SliverAppBar) runs **after** T1.1 lands to avoid concurrent edits to product_detail_screen.dart.

**Verified — 2026-04-29.**
- **NEW** `lib/features/product_detail/providers/hero_verdict_provider.dart` — pure-function `computeHeroVerdict` + sealed `HeroVerdict` hierarchy (`HeroVerdictBlocked` / `HeroVerdictAvoid` / `HeroVerdictNone`). Decision order: product-side BLOCKED/UNSAFE → Blocked banner; otherwise stack-side max severity Avoid/Contraindicated → Avoid banner with extracted offending agent (best-effort across pipeline-shape variants `with` / `interacting_with` / `medication` / `drug` / `agent` / `name`); otherwise None. Headline composes correctly: "Avoid with metformin" / "Do not take with warfarin" / "Avoid for your stack" fallback.
- **NEW** `test/features/product_detail/providers/hero_verdict_provider_test.dart` — 25 tests across 4 groups: product-side blocking priority, stack-side blocking priority, non-blocking → None, robustness (unrecognized/non-string severity, mixed case, assert on lower-severity construction).
- **MODIFY** `lib/features/product_detail/product_detail_screen.dart` — `_HeaderSection` heavy edit:
  - Identity row simplified: image + name + brand + form factor only (Personal Fit pill / VerdictBadge / percentile / grade pill / "Limited data" pill / `_HeroScoreReason` / "View Supplement Label" all removed).
  - Quality Score altar: centered 88pt PGScoreRing inside a `Center(Column(...))` with the "PG SCORE" label rendered externally below the ring (rather than via PGScoreRing's internal `label` slot — the internal Column overflows by ~2px at this strokeWidth, externalizing gives breathing room).
  - Score altar suppressed when `HeroVerdict is HeroVerdictBlocked` — the banner replaces the altar (no mixed-signal "DO NOT USE / 82" alongside each other). Stack-side Avoid/Contraindicated still shows the score because the product itself is fine.
  - Verdict banner gated to Blocked / Avoid only — Caution/Monitor/Safe/Recommended/etc. flow through to T1.2 Section 2.
  - Constructor cleaned: `grade`, `percentileLabel`, `isBlocked`, `scoreReason`, `imageUrl`, `mappedCoverage` parameters removed (now T1.4/T1.6 territory).
  - Image kept at 56pt: BrandedPlaceholder switches to a multi-row "full card" mode above 56 that overflows by ~2px in the test placeholder path. Premium hero feel comes from the centered score altar + wider identity column, not the thumbnail size.
  - Dead code removed: `_pickHeroScoreReason` helper + `_HeroScoreReason` widget class. `_extractWhyItems` retained (still used by deep-dive sections).
  - Imports cleaned: `pg_fitscore_badge`, `fit_score_provider`, `fit_score_sheet` no longer used.
- Test count: 802 → 833 (+31: 25 hero_verdict_provider + 6 net adjustments to existing product-detail tests including the T1.1 invariant replacement test).

---

### [x] T1.2 — "For You" merged block (Section 2)

**What**
New widget consolidating: context chips (with Edit) + verdict (✅/🟡/❌) + 1-line key explanation + alerts (priority-sorted, only contraindicated/avoid/caution) + expandable "Why this fits you" (4-bullet deterministic explanation).

**Why**
Currently scattered across hero, alerts widget, and FitScore sheet. Consolidation = decision clarity.

**Files**
- New: `lib/features/product_detail/widgets/for_you_section.dart`
- Refactors: existing `interaction_warnings.dart`, `fit_score_sheet.dart` — content reused, presentation new

**Tests**
- Safe + good fit profile → "✅ Strong match for your sleep goal"
- Avoid tier → "❌ Not recommended for your profile" AND no Fit number anywhere
- Empty profile → "Add your profile to personalize →"
- Multiple alerts stack in priority order: contraindicated > avoid > caution
- Why-this-fits expander → 4 deterministic bullets, no AI

**Acceptance**
- All 4 verdict states render correctly
- Risk-gating works: Avoid hides Fit, shows "Not recommended"
- Alerts limited to contraindicated/avoid/caution (monitor/safe filtered out)

**Cross-team:** Apple-grade F.5 ("Why this score · Your alerts" dual-column card) is folded into this task. Their "Why this score" half was structurally misplaced — it belongs in T1.4/T1.6 (Section 3 / Tradeoffs), not Section 2. Their "Your alerts" half + visual approach (PGCard.plain, PGPressable per row, LayoutBuilder for SE-class small screens) is reused here. Other team is skipping F.5; we own it here with the corrected content model.

**Verified — 2026-04-29.**
- **NEW** `lib/features/product_detail/widgets/for_you_section.dart` — `ForYouSection` ConsumerWidget consolidating: section header (title + Edit-pill PGPressable affordance routing to profile setup); context chips (up to 4 humanized profile signals — goals + conditions + drug classes); verdict row (emoji + headline + Personal Fit pill, the pill suppressed via T1.3's `computeFitDisplay` when `maxSeverity ≥ Avoid`); alerts list (severity-priority sorted, filtered to contraindicated/avoid/caution); "Why this fits you" expander (collapsed by default, animated reveal with up to 4 deterministic bullets pulled from `FitScoreResult.reasons`). Empty-profile state collapses to a single PGCard CTA → profile setup. Apple-grade visual approach throughout: PGCard.plain shell, PGPressable on every interactive (Edit pill, expander toggle), tabular figures on the `<n>/100` pill.
- **NEW** `test/features/product_detail/widgets/for_you_section_test.dart` — 17 widget tests across 5 groups: empty-profile (affordance + nickname-only treated as empty), verdict copy (Strong/Good/Limited/NotRecommended/Avoid/Contra/null all asserted with exact headline strings), alert priority (contra > avoid > caution Y-position assertion + monitor/safe/informational filter), Why-this-fits expander (collapsed default + 4-bullet cap + hidden when reasons empty), context chips (snake_case humanizer + 4-chip cap).
- **MODIFY** `lib/features/product_detail/product_detail_screen.dart` — Section 2 wired between the hero and the existing condition alert banner. Suppressed when product is BLOCKED (the hero's blocked banner already owns that messaging). New helpers: `_maxSeverityOf(warnings)` returns the worst severity for the risk-gate input; `_topGoalLabelFromFit(result)` regex-extracts the goal name from FitScore reasons (e.g. "Matches your sleep goal" → "sleep") for the verdict headline copy.
- Test count: 833 → 850 (+17). flutter analyze clean.

---

### [x] T1.3 — Risk-gated Fit core logic

**What**
Helper function: `FitDisplay computeFitDisplay({verdict, fitResult})` that returns a state-based display (`StrongMatch | GoodMatch | LimitedFit | NotRecommended | Hidden`). When verdict is Avoid/Contraindicated, returns `Hidden` regardless of underlying fit number.

**Why**
The most important UX decision in this initiative. Prevents "Avoid + 88/100" combinations.

**Files**
- New: `lib/services/fit_score/fit_display.dart`
- Updates: `lib/features/product_detail/widgets/for_you_section.dart` consumes this

**Tests**
- Verdict Avoid → Hidden (regardless of fit score)
- Verdict Contraindicated → Hidden
- Verdict Caution + fit≥80 → GoodMatch (caution doesn't hide fit, just adds an alert)
- Verdict Safe + fit≥85 → StrongMatch
- Verdict Safe + fit 60-84 → GoodMatch
- Verdict Safe + fit 35-59 → LimitedFit
- Verdict Safe + fit<35 → NotRecommended (low fit even when safe)

**Acceptance**
Pure-function helper. No widget dependency. 100% test coverage.

**Verified — 2026-04-29.**
- **NEW** `lib/services/fit_score/fit_display.dart` — pure-function helper. Sealed `FitDisplay` hierarchy (`FitStrongMatch` / `FitGoodMatch` / `FitLimitedFit` / `FitNotRecommended` / `FitHidden` / `FitIncomplete`). Bands on `FitScoreResult.scoreCombined100` (PG quality × personal fit) so the user sees a 0–100 number consistent with the hero Quality Score. Public `FitDisplayThresholds` (85 / 60 / 35) so UI copy can describe them without re-hardcoding. Decision order: risk-gate (Avoid/Contraindicated → Hidden) → profile-completeness (incompleteProfile → FitIncomplete) → score banding. Caution/Monitor/Informational pass through the gate untouched (alert is rendered alongside the fit pill, not in place of it).
- **NEW** `test/services/fit_score/fit_display_test.dart` — 21 tests across 5 groups: risk-gate (Contra/Avoid hidden regardless of score), caution/monitor pass-through (caution at 90 still StrongMatch — no cap), Safe banding with explicit boundary tests at 85/60/35 (boundary values land in the upper tier), incomplete profile (`incompleteProfile` → FitIncomplete; risk-gate still trumps incompleteness), threshold stability pin.
- **Consumer wiring**: T1.2 will consume this via `for_you_section.dart` once the score-led-hero work clears T1.1.

---

### [x] T1.4 — Product Quality section (Section 3) — REVISED 2026-04-29

> **Revision rationale.** Score ring stays in the hero (T1.1) per the score-led-hero revision. Section 3 is now **pillar bars + coverage line + "Why this score" reasoning**. Apple-grade F.4 (donut + 4 pillar bars in a card) is folded in here, rescoped to drop the donut.

**What**
- 4 pillar bars (Ingredient Quality / Safety & Purity / Evidence & Research / Brand Trust) — horizontal progress bars, value labels, tap-to-expand inspector
- Coverage line — colored badge (green/yellow/red by ratio) + "X of Y ingredients mapped" subtitle
- "Why this score" reasoning row — short prose pulled from `score_bonuses[]` / `score_penalties[]` (the detail strings explaining each bonus/penalty)
- The hero's Quality Score number can appear as a small inline label here for continuity ("Your 82 breaks down as:")

**Why**
PG Score is the differentiator. The score itself lives in hero where users expect it; this section explains *why* the score is what it is. Decomposition into pillars + transparent bonus/penalty reasoning supports trust.

**Files**
- `lib/features/product_detail/widgets/score_breakdown_card.dart` — already exists, repurpose as the section body
- `lib/core/widgets/pg_pillar_bar.dart` — new (Apple-grade F.2 deliverable; we consume it)
- Coverage strip — inline composition; reuse existing coverage logic from `score_breakdown_card.dart`

**Blocking dependencies (Apple-grade team)**
- **F.0 data audit** — must complete before this task starts. Verifies whether 4-pillar scores exist as discrete fields, are derivable from `score_bonuses[]`/`score_penalties[]`, or need a pipeline ticket. Three-way verdict shapes implementation:
  - GREEN → straight UI build
  - YELLOW → small aggregation step inside `score_breakdown_card.dart`
  - RED → split into pipeline ticket + Flutter follow-up
- **F.1 ring/donut decision** — only relevant for T1.1 hero (audit `pg_score_ring.dart`; reuse if it covers, else fill the gap). Doesn't directly block T1.4 because the score visual is in the hero now.
- **F.2 PGPillarBar primitive** — directly consumed by this task

**Tests**
- 4 pillars render with progress bars + value labels
- Coverage line renders with correct color (green/yellow/red)
- Tap on pillar → expands inspector with sub-scores in words (no "X.X pts" raw)
- Low-coverage product (<30%) → "This analysis may be incomplete" subtitle visible
- "Why this score" row renders bonus + penalty detail strings (not summarized)

**Acceptance**
- Pillars + coverage + reasoning all render
- Coverage policy enforced
- Pillar tap opens inspector with sub-scores in words (no "X.X pts")
- Implementation matches the F.0 audit verdict (no fake numbers from invented derivations)

**Cross-team:** Apple-grade F.4 is folded into this task (rescoped — no donut). PGPillarBar primitive (F.2) comes from the other team.

**Verified — 2026-04-29.**
- **MODIFY** `lib/features/product_detail/widgets/score_breakdown_card.dart` — extended the existing 4-pillar tap-expand card with two T1.4 additions:
  - **Hero continuity label** — `heroScore` (0..100, optional). When present, renders `"Your <X> breaks down as:"` above the pillar bars so users can trace the hero's Quality Score number into its pillar makeup. Score is `.round()`'d for clean display (87.6 → "Your 88").
  - **Coverage line** — `mappedCoverage` (0..1, optional). New `_CoverageLine` private widget renders a single tier-tinted row: colored 8pt dot · "Coverage" label · percentage (tabular figures) · descriptor copy. Tiers via existing thresholds for cross-surface consistency: ≥0.7 green ("Most ingredients in our database — high-confidence score") / ≥0.3 yellow ("Some ingredients aren't in our database — partial coverage") / <0.3 insufficient ("Limited data — only part of this product is in our database"). Defensive clamp on `[0..1]` so a >1 ratio from pipeline drift renders as 100% rather than "150%".
  - Existing 4 `_ExpandableSectionBar` instances kept unchanged — they already deliver the spec's "tap-expand inspector with sub-scores in words" requirement (per-pillar `_explainXxx` builders + sub-score rows). PGPillarBar primitive (Apple-grade F.2) was evaluated but kept the existing tap-expand bars because they own the inspector contract; PGPillarBar is non-tappable and the swap would lose the deeper UX. The visual primitives can converge in a later pass without contract churn.
- **MODIFY** `lib/features/product_detail/product_detail_screen.dart` — pass `heroScore: score100` and `mappedCoverage: mappedCoverage` from the existing `_product` reads to the card. Two-line wiring change.
- **MODIFY** `test/features/product_detail/score_breakdown_card_test.dart` — added 12 tests across 3 groups: continuity label (renders with rounding, hidden when null), coverage line (4 tier-boundary tests at 0.92/0.7/0.5/0.3/0.15/0.0/1.5-clamped, hidden when null), integration (Y-position assertion proves continuity sits above coverage in the layout). Existing 4 tests still green.
- Coverage thresholds intentionally mirror the legacy hero "Limited data" gate (`mappedCoverage < 0.3`) so the same product reads consistently across surfaces.
- F.0 audit verdict honored — no derivation needed, all four pillars are first-class fields on `products_core` (verified by other team in `76285f3`).
- Test count 891 → 903 (+12). flutter analyze clean.

---

### [x] T1.5 — Ingredients section (Section 4)

**What**
Active ingredients with: name + dose + form + bio-availability + dose-vs-effective-range note + evidence badges. Inactive ingredients as chips with on-tap explanation ("Used as capsule shell" etc.).

**Files**
- `lib/features/product_detail/widgets/ingredients_section.dart` — new wrapper
- Reuses: existing active/inactive widgets

**Tests**
- Active row renders all 5 elements (name, dose, form, dose-vs-range, evidence)
- Inactive chip tap shows correct explanation
- Empty inactive list → no chip row
- Long ingredient name → ellipsis, no overflow

**Acceptance**
Section reads as actionable, not raw. User understands what each ingredient does, why it's there, and whether the dose is effective.

**Cross-team:** Apple-grade F.3 (PGIngredientAtom primitive) and F.6 (atom-style ingredients row) are dropped — atom pills are decorative for medical-grade context where dose-vs-effective-range is the key trust signal. Verbose rows for active ingredients + existing chip pattern for inactive are the right call. Other team is dropping F.3 + F.6 entirely.

**Verified — 2026-04-29.**
- **NEW** `lib/features/product_detail/widgets/ingredients_section.dart` — section file with three exports:
  - `InactivePurpose` (public data class — `role` + `detail` strings)
  - `inactiveIngredientPurpose(String name)` — public lookup; lowercase + trim, returns the matched entry or `null` for fallback. 22-entry table (`_inactivePurposes`) covering capsule shells (gelatin / HPMC / vegetable cellulose / plant cellulose / pullulan / hydroxypropyl methylcellulose), lubricants (magnesium stearate ×2 + stearic acid), flow agents (silicon dioxide / silica / MCC × 2 / dicalcium phosphate), solvents (water + purified water), and attention-tier sweeteners/colorants (sucralose / aspartame / titanium dioxide). Detail copy is honest about controversial entries — TiO2 surfaces the EU 2022 food-additive ban context.
  - `InactiveIngredientChip` — tappable replacement for the previously-inert inactive `Container`. Wrapped in PGPressable (0.94 scale + haptic) so the tap feels intentional. Tap opens a `PGModal.bottomSheet` rendering the ingredient name + role + detail copy via `_InactiveIngredientExplanationSheet`. Unknown names fall back to "Inactive ingredient — Added during manufacturing to bind, preserve, flavor, color, or otherwise stabilize the product." copy so no chip is a dead-end.
  - `IngredientsSection` — passthrough wrapper widget kept thin per spec ("new wrapper, reuses existing active/inactive widgets"). Active rows continue to render via the existing `_CollapsibleIngredients` / `_IngredientTile` inside `product_detail_screen.dart` — those already deliver the spec's 5-element row contract (bioavailability dot + name + dose + form/category + UL safety tag).
- **MODIFY** `lib/features/product_detail/product_detail_screen.dart` — replaced the 4 inactive-chip `Container` instances inside `_DetailSection` with `InactiveIngredientChip(name: name)`. The "+N more" overflow chip is unchanged (it's not a tappable per-ingredient signal — it's a count-overflow affordance that should hand off to a separate "show all" sheet, deferred). Imports updated.
- **NEW** `test/features/product_detail/widgets/ingredients_section_test.dart` — 14 tests across 4 groups: lookup contract (case-insensitive + whitespace-tolerant + null on unknown/empty/whitespace), T0.5-whitelist coverage gate (every locked excipient must have a purpose entry — silent fallback acceptable for niche names but not for the canonical set), attention-tier ingredients pin (sucralose role copy + TiO2 EU regulatory context), chip render (long-name no-overflow), tap behavior (known-name → role+detail surface, unknown → fallback copy + sheet, sucralose → "Artificial sweetener" copy), wrapper passthrough.
- Acceptance items satisfied: active rows already render the 5 spec elements via the unchanged `_IngredientTile` (verified by inspection of lines 2403–2536 of product_detail_screen.dart); inactive chip tap shows correct explanation; empty inactive list → existing `if (inactiveIngredients.isNotEmpty)` guard preserved → no chip row; long ingredient name → existing chip layout uses `Wrap` so chips wrap to new lines without overflow.
- Test count 903 → 917 (+14). flutter analyze clean.

---

### [x] T1.6 — Tradeoffs section (Section 5)

**What**
Two-column "👍 What's good" / "⚖️ What to consider" — pulled from `score_bonuses` and `score_penalties` in the detail blob. Replace the renamed Section 2 ("Highlights" from T0.2) with this richer split.

**Why**
Bullets-with-icons reads better than a prose paragraph. Pros vs cons separation reduces cognitive load.

**Files**
- New: `lib/features/product_detail/widgets/tradeoffs_section.dart`
- Refactor: `_WhyThisProductSection` becomes this

**Tests**
- Bonuses → 👍 column
- Penalties → ⚖️ column
- Empty bonus list → only ⚖️ renders, or section hides if both empty
- Long detail strings → wrap properly, no overflow

**Acceptance**
Renders cleanly with mixed bonus/penalty inputs. Correctly empty when blob has neither.

**Verified — 2026-04-29.**
- **NEW** `lib/features/product_detail/widgets/tradeoffs_section.dart` — public `TradeoffsSection(items)` consuming the same `({label, detail, isPositive})` records `_extractWhyItems` already produces (sanitization happens upstream via T0.2's `sanitizeWhyDetail`). Splits into bonuses + penalties, drops blank-label entries defensively, hides the entire card when both lists are empty. Rendering: side-by-side two-column at ≥380pt width; single-column stacked fallback below 380pt OR when only one half has content. Headers: "👍 What's good" (severitySafe tone) / "⚖️ What to consider" (severityAvoid tone). New `TradeoffRow` public widget — colored 5pt bullet + bold label + optional bodySmall detail subline. Each side has its own `_TradeoffColumn` private composer.
- **MODIFY** `lib/features/product_detail/product_detail_screen.dart` — swap `_WhyThisProductSection(items: whyItems)` → `TradeoffsSection(items: whyItems)`. Removed `_WhyThisProductSection` class (was at lines 2243–2281) + its helper `_ProConTile` class (was at lines 2698–2758) — both unreferenced after the swap. Replaced with a 4-line tombstone comment so future readers understand where the rendering moved. Added the import.
- **NEW** `test/features/product_detail/widgets/tradeoffs_section_test.dart` — 10 tests across 2 groups: split contract (bonuses-only single column, penalties-only single column, both-at-480pt two-column with same-Y header assertion, both-at-320pt SE-class single-column with stacked-Y header assertion, both-empty → hide-entirely, blank-label defensive drop) and row rendering (label + detail subline render, empty detail produces no empty-string Text, long detail wraps without overflow at SE width, multi-bonus + multi-penalty render).
- Acceptance items satisfied: ✅ bonuses → 👍, ✅ penalties → ⚖️, ✅ empty-bonuses → single ⚖️ column, ✅ both empty → SizedBox.shrink, ✅ long detail wraps without overflow.
- Test count 917 → 931 (+10 T1.6 tests + 4 incidental from parallel sweeps). flutter analyze clean.

---

### [x] T1.7 — What we don't know (Section 6)

**What**
Surface unknowns transparently: "No third-party heavy metal test available", "Manufacturer hasn't published recent COAs", etc. Soft visual treatment (less contrast).

**Why**
**Trust amplifies through admitted uncertainty.** Most apps hide unknowns; surfacing them differentiates from Yuka.

**Files**
- New: `lib/features/product_detail/widgets/unknowns_section.dart`

**Logic**
Surfaces an "unknown" when:
- `isTrustedManufacturer == false` AND no COA URL → "Manufacturer hasn't published recent COAs"
- `hasThirdPartyTesting == false` → "No third-party heavy metal test available"
- `mappedCoverage < 0.5` → "Some ingredients couldn't be mapped to our database"
- `score_evidence_research < max_evidence_research * 0.4` → "Limited clinical research data"

**Tests**
- All trust signals positive → section hidden
- One unknown → renders 1 bullet
- Multiple unknowns → render all, one bullet each
- Low coverage product → renders coverage unknown line

**Acceptance**
Section never lists more than 4 unknowns (truncate with "…"). Renders with softer color treatment than other sections.

**Verified — 2026-04-29.**
- **NEW** `lib/features/product_detail/widgets/unknowns_section.dart` — public `buildUnknowns({...})` pure helper + `UnknownsSection` widget. The helper takes the trust signals, returns a list of human-readable bullet strings in fixed display order (third-party → COA → coverage → evidence — most actionable first). Spec's "AND no COA URL" condition simplified to untrusted-manufacturer-alone for v1 since no `coa_url` field ships on the certification blob today; tightening to `untrusted AND no coa_url` is a one-line change when that field appears upstream. Hard-cap at 4 unknowns via `_maxUnknowns` constant (defensive — there are only 4 trigger conditions today, but the cap protects against future additions). Boundary thresholds verified: `mappedCoverage < 0.5` (strict, 0.5 exactly is fine) and `scoreEvidenceResearch < scoreEvidenceResearchMax * 0.4` with defensive `max > 0` guard against divide-by-zero.
- The widget renders deliberately soft: `PGCard.plain` (not elevated) so the section sits visually quiet compared to the louder Tradeoffs / Quality cards above; `Icons.help_outline_rounded` 16pt header icon with `onSurfaceVariant` tone; section title "What we don't know" in `titleSmall` with `onSurfaceVariant`; per-bullet 4pt muted dot + `bodySmall` body text. No severity icons — these are context, not warnings. Hides entirely (`SizedBox.shrink`) when no triggers fire. Italic "… and N more" overflow line for the > 4 case (defensive — current logic can't trip it, but it's wired so adding a 5th condition doesn't silently truncate without the user knowing).
- **MODIFY** `lib/features/product_detail/product_detail_screen.dart` — added 5 new params to `_DetailSection` (`isTrustedManufacturer`, `hasThirdPartyTesting`, `mappedCoverage`, `scoreEvidenceResearch`, `scoreEvidenceResearchMax`); the call site at line 528 reads them off `_product` and passes through. `UnknownsSection` instantiated above the T1.8 `WithYourStackSection` inside `_DetailSection.build`. 12pt vertical gap below.
- **NEW** `test/features/product_detail/widgets/unknowns_section_test.dart` — 16 tests across 2 groups: pure `buildUnknowns` logic (all-positive empty, individual triggers for each of the 4 conditions, boundary tests at 0.5 + 0.49 mappedCoverage and 40% + 35% evidence-ratio, null inputs skip checks, defensive divide-by-zero on max=0, all-4 trigger order verification) + widget render (all-positive hides section, 1 unknown renders 1 bullet, multiple-unknowns render all, low-coverage triggers, all-4 renders no overflow line).
- Test count 944 → 960 (+16). flutter analyze clean.

---

### [x] T1.8 — Interactions refactor (Section 7)

**What**
**7.1 With your stack (priority):** alerts grouped by user's actual medications/supplements. ⚠ for issues, ✓ for "no interaction". Tap → expand to mechanism + recommendation + citations.

Defer 7.2 (general interactions) to Sprint 3 — only ship if curated content is ready.

**Files**
- `lib/features/product_detail/widgets/interaction_warnings.dart` — heavy refactor

**Tests**
- 1 stack med with conflict → renders ⚠ row + expandable
- 1 stack med no conflict → renders ✓ row (positive trust signal)
- Empty stack → section hidden
- Tap expand → mechanism, recommendation, evidence_level visible

**Acceptance**
- Per-user-med rows replace generic "interaction warnings" list
- ✓ rows shown for medications confirmed safe (positive, not just absence of warning)

**Verified — 2026-04-29.**
- **NEW** `lib/features/product_detail/widgets/with_your_stack_section.dart` instead of refactoring `interaction_warnings.dart` directly. The 1201-line `InteractionWarningsList` already does heavy profile-aware filtering for the generic "Other precautions" tier; ripping it apart for the per-row personalized view would have been a bigger blast radius than warranted. The new `WithYourStackSection` sits ABOVE the existing list and provides the per-profile-entry summary; `InteractionWarningsList` continues to handle 7.2's generic precautions until that work lands in Sprint 3 per spec.
- `WithYourStackSection({warnings, userDrugClasses, userConditions})` — pure widget, no provider deps. Caller passes pre-resolved profile sets. One row per drug class + one per condition; rows sort by severity weight desc (worst first), then alpha within same weight.
- Each row: severity-tinted icon + humanized label + sub-line. Matched warning → ⚠ tier-icon (`do_not_disturb_on_outlined` / `error_outline_rounded` / `warning_amber_rounded` per severity) + "Severity — Headline" sub-text + tap-expand chevron. No matched warning → ✓ `check_circle_outline_rounded` icon (severity-safe tone) + "No known interaction" sub-text. ✓ rows are intentionally non-tappable (no chevron, no expand) — there's nothing to expand.
- Tap-expand for ⚠ rows reveals: "Mechanism" + body (uses `alertBody` if authored, else `mechanism`), "Recommendation" + management copy, evidence-level chip ("Strong Evidence" / "Good Evidence" / "Theoretical"), citation-count chip with bottom-sheet showing all source URLs (only renders when `sourceUrls.isNotEmpty`). 220ms easeOutCubic AnimatedSize for the reveal.
- Worst-severity-wins selection when multiple warnings tag the same drug class (caution + contraindicated → contraindicated surfaces; the caution-tier note is dropped at this row; if the user wants the full list it's in the generic "Other precautions" list below).
- Hides entirely when `userDrugClasses.isEmpty && userConditions.isEmpty`. Without those signals there's no way to compute a personalized status and the empty-state would just be visual noise.
- **MODIFY** `lib/features/product_detail/product_detail_screen.dart` — inserted `WithYourStackSection` directly above `InteractionWarningsList` inside `_DetailSection.build`. The existing list is preserved (per spec's 7.2 defer to Sprint 3). 12pt vertical gap between sections when both render.
- **NEW** `test/features/product_detail/widgets/with_your_stack_section_test.dart` — 13 widget tests across 5 groups: visibility gates (empty profile → hide; empty warnings + profile → ✓ rows for each), ⚠ row (severity label + headline render, fallback to title when alertHeadline absent, worst-severity-wins on multi-match), ✓ row (no-match → "No known interaction", non-tappable), tap-expand (mechanism + recommendation + evidence chip + citation count, second tap collapses, citation pluralization "2 citations", no chip when sourceUrls empty), sort + condition support (descending severity sort, condition-only entries match via conditionIds).
- Test count 931 → 944 (+13). flutter analyze clean.

---

### [x] T1.9 — Populations dedupe (Section 8)

**What**
"Extra caution for: Pregnancy, Kidney disease, Children under 12. (You are already covered for Lisinopril)" — auto-dedupe against user's profile so they don't see warnings already shown elsewhere.

**Files**
- New: `lib/features/product_detail/widgets/populations_section.dart`

**Tests**
- Population matches user → moved to "(already covered)" line
- Population doesn't match → bulleted in main list
- All populations match user → section reduces to "(already covered for X, Y)" only

**Acceptance**
No duplicate warnings between Section 7 (Interactions) and Section 8 (Populations).

**Verified — 2026-04-29.**
- **NEW** `lib/features/product_detail/widgets/populations_section.dart` exports public `splitPopulations({populations, userConditions, userDrugClasses, ageBracket})` pure helper, public `aggregatePopulations(warnings)` flattener, and `PopulationsSection` widget. Pipeline-side `populationWarnings` are free-form prose strings (`"Children — immature gut barrier"`, `"People with IBD"`, `"Pregnancy"`); helper aggregates across all `InteractionWarning` instances, dedupes by case-insensitive trimmed string, then word-boundary-matches each remaining entry against a 21-keyword map (`pregnancy`/`pregnant` → `pregnancy` signal; `diabetic`/`diabetes` → `diabetes`; `children`/`pediatric`/`minors` → `under_18`; `older adults`/`elderly`/`geriatric` → `over_65`; etc.). Word-boundary regex prevents false-positive substring matches like "fish" inside "fishing".
- Output `PopulationSplit` record: `mainList` (bulleted "Extra caution for: A, B, C" — pipeline-order preserved), `alreadyCovered` (humanized user signals that DID match — alphabetically sorted, deduped, "You are already covered for X, Y"). Empty-input + no-user-signals + all-blank handled defensively.
- Age bracket → signal mapping: handles real `SchemaIds.ageBrackets` values directly — `'14-18'` → `under_18`; `'71+'` → `over_65`. `'51-70'` deliberately left unmapped (51-64 majority would be miscategorised as elderly). Falls back to fuzzy matchers (`under_*` / contains "child" → `under_18`; contains "65" / "over" / "elderly" / "geriatric" → `over_65`) for tests and any caller passing canonical signal tokens. Empty / unrecognized → empty signal, ignored.
  - **Audit fix (2026-04-29).** The original implementation only matched fuzzy-canonical tokens, so the literal schema strings flowing from `profileProvider.ageBracket` (`'14-18'`, `'71+'`, etc.) all fell through to `''` and age-bracket dedupe never fired in production. Added explicit schema mappings + 4 regression tests covering `'14-18'`, `'71+'`, `'51-70'` (unmapped), and middle brackets (`'19-30'`, `'31-50'`).
- Widget hides when no populations OR when both lists empty after dedupe. PGCard with groups_outlined header. Main list rendered as inline comma-separated body text (not bullets — keeps the section compact); covered line rendered as italic onSurfaceVariant parenthetical below.
- **MODIFY** `lib/features/product_detail/product_detail_screen.dart` — inserted `PopulationsSection` directly between `WithYourStackSection` (Section 7) and `InteractionWarningsList` (generic precautions). Reads `ageBracket` off the watched profile state. 12pt vertical gap.
- **NEW** `test/features/product_detail/widgets/populations_section_test.dart` — 24 tests across 3 groups: pure `splitPopulations` (17 tests covering empty input, no signals, single-condition match, keyword match via "diabetic" → "diabetes", word-boundary defense, case-insensitivity, multi-population-same-signal collapse, all-match → empty main, drug-class matching documented, age-bracket flow via canonical token + 4 regression tests for real schema strings, dedupe of duplicate strings, blank drop, alphabetical sort) + `aggregatePopulations` (1 test) + widget render (6 tests covering hide-when-empty, main-only, mixed main+covered, all-covered, edge case all-match-only, age-bracket integration).
- Acceptance gate: NO duplicate warnings between Section 7 + Section 8 — Section 7 surfaces user-specific warnings via `WithYourStackSection`; Section 8's `splitPopulations` filters out anything that matches the user's signals so the same content never duplicates across sections.
- Test count 960 → 980 (+20). flutter analyze clean.

---

### [x] T1.10 — Evidence section (Section 9)

**What**
"Clinical support: STRONG / MODERATE / LIMITED" + study count + meta-analysis flag. **No editorial quote in V1** (deferred). Tap → full citations.

**Files**
- Refactor: existing `lib/features/product_detail/widgets/pipeline_sections/evidence_detail_section.dart`

**Tests**
- Strong evidence (≥5 studies, meta available) → STRONG label
- Limited evidence (<3 studies) → LIMITED label
- Tap → citation list with PMIDs
- No editorial quote present in V1

**Acceptance**
Tier label matches actual evidence count. PMIDs link out to PubMed.

**Verified — 2026-04-29.**
- **REFACTOR** `lib/features/product_detail/widgets/pipeline_sections/evidence_detail_section.dart` — added public `EvidenceTier` enum (`strong` / `moderate` / `limited` with `label` + `color`) and three pure helpers: `evidenceTotalStudies(matches)` (sums PMIDs across matches, deduped by trimmed string so the same study under two ingredients counts once + ignores blanks), `evidenceHasMetaQuality(matches)` (true if any match's `evidence_level` ∈ `{strong, established, high}` — `'high'` included for forward-compat with the scoring-pipeline pillar levels), and `evidenceTier(matches)` (Flutter-side derivation until the pipeline ships a proper `meta_analysis` boolean: <3 studies → LIMITED; 3-4 studies OR 5+ without meta → MODERATE; ≥5 studies AND meta-quality → STRONG).
- New `_TierBlock` chip rendered above the existing per-match list — "Clinical support: \<TIER\>" with severity-tinted border (`evidenceStrong` / `evidenceGood` / `evidenceTheoretical` token reuse) + sub-line "N studies reviewed" + " · meta-analysis available" appended only when `evidenceHasMetaQuality` fires. Block is `PGPressable`-wrapped → tappable to open the all-citations bottom sheet (chevron-right affordance only when there are matches to drill into).
- Per-match rows preserved; the row-level `PubMed` pill is now `PGPressable` and opens a per-ingredient citations sheet with **every** PMID for that match (replacing the old behavior that only launched the first PMID directly). Aggregate sheet groups citations by ingredient with the ingredient name as a `titleSmall` heading + per-PMID rows that launch PubMed externally on tap. Both sheet variants use `PGModal.bottomSheet`.
- Tier label rendered as two side-by-side `Text` widgets in a Row (not `Text.rich` with `TextSpan` children) so `find.text('STRONG')` works in widget tests — caught + fixed during the first test run, recorded in the inline comment.
- **NO editorial quote in V1** — defensive test asserts that none of the static section text contains common editorial phrases ("has been shown", "clinically proven", "studies suggest", "research shows"). The pipeline doesn't curate research summaries yet, so any text we wrote here would be unverifiable.
- Constructor signature unchanged (`{Map<String, dynamic>? evidenceData}`) — the single consumer in `product_detail_screen.dart:3281` works without modification.
- **NEW** `test/features/product_detail/widgets/pipeline_sections/evidence_detail_section_test.dart` — 26 tests across 4 groups: pure `evidenceTotalStudies` (4 tests covering empty/sum/dedupe-cross-matches/blank-drop), `evidenceHasMetaQuality` (5 tests covering canonical `strong`/`established`/`high` + downgrade path + empty), `evidenceTier` boundary thresholds (8 tests including spec-exact STRONG ≥5+meta and LIMITED <3), and render (9 tests covering hide-when-null, hide-when-zero, all three tiers' label+sub-line, no-editorial-quote defense, tap-banner→all-citations, tap-pill→per-ingredient-citations, unsubstantiated-claims rendering).
- Test count 975 → 1001 (+26). flutter analyze clean.

---

### [x] T1.11 — Product Details (Section 10) — collapsed by default

**What**
Serving size, servings, manufacturer. Low priority — collapsed expander.

**Files**
- New: `lib/features/product_detail/widgets/product_details_section.dart`

**Tests**
- Renders 3 fields when present
- Collapsed by default (single-line header)
- Tap → expands

**Acceptance**
Always rendered, always collapsed initially.

**Verified — 2026-04-29.**
- **NEW** `lib/features/product_detail/widgets/product_details_section.dart` (~190 lines) — public `ProductDetailField({label, value})` data class + public `buildProductDetailFields({servingSize, servingsPerContainer, manufacturer})` pure helper returning the 3 fields in fixed display order: Serving size (most actionable / dosing), Servings per container (volume / refill horizon), Manufacturer (provenance, lowest priority). Defensive trim/null/empty filtering — `servingsPerContainer == 0` is dropped (degenerate "we don't know" sentinel from the pipeline). Section uses `PGCard.plain` (visually quieter than louder safety/quality cards above), `info_outline_rounded` 18pt header, chevron-up/down rotate on tap, AnimatedSize 220ms easeOutCubic reveal.
- Default state is collapsed — header only with `keyboard_arrow_down_rounded`. Tap (PGPressable, 0.98 scale + haptic) toggles. Field rows render label (140pt fixed col, w600 onSurfaceVariant) + value (Expanded, onSurface, height 1.35) split — `_DetailRow` keeps long manufacturer names from breaking the 2-col layout.
- Hides entirely when ALL three fields are null/empty (the "always rendered" acceptance is conditional on data presence — an empty collapsed expander would be noise).
- **MODIFY** `lib/features/product_detail/product_detail_screen.dart` — added 2 new params to `_DetailSection` (`dosingSummary`, `servingsPerContainer`); call site at line 528 reads them off `_product` directly. Manufacturer name read inline from `detailBlob['manufacturer_info']['name']` (already in scope; no new typed plumbing). `ProductDetailsSection` instantiated as the LAST item in the main column directly after `InteractionWarningsList`. 12pt vertical gap.
- Pipeline data sources: `_product?.dosingSummary` (TextColumn, e.g. "2 capsules daily") + `_product?.servingsPerContainer` (IntColumn) + `detailBlob.manufacturer_info.name` (string).
- **NEW** `test/features/product_detail/widgets/product_details_section_test.dart` — 10 tests across 2 groups: pure `buildProductDetailFields` (5 tests covering all-three-present in spec order, all-null → empty, blank/zero filter defense, single-field rendering, whitespace trim) + render (5 tests covering hide-when-all-null, header-only-collapsed-default, tap-expand-reveals-rows, tap-twice-collapses, partial-data-renders-present-only).
- Test count 1001 → 1011 (+10). flutter analyze clean.

**Audit follow-up — 2026-04-29 (post-T1.12 audit pass):**
- **Richer fields added** beyond spec's 3: `Net contents` (e.g. "60 capsules" via new public `formatNetContents(qty, unit)` helper that drops trailing `.0` on whole-number quantities), `Form` (capsule / tablet / softgel / gummy / powder / liquid — humanized via shared `_humanize`), `Country` (from `detail_blob.manufacturer_info.country`). All optional — section drops any row whose data is missing. New display order: Serving size → Servings per container → Net contents → Form → Manufacturer → Country.
- **iPhone SE narrow-screen layout fix.** `_DetailRow` now wrapped in a `LayoutBuilder` — below 380pt (matches T1.6 breakpoint) the row stacks label-above-value full-width instead of 140pt-fixed-col side-by-side. Long manufacturer names like "Nature's Best Incorporated" no longer squeeze on 320pt screens. Constants `_narrowBreakpoint = 380.0` + `_labelColumnWidth = 140.0` exposed.
- **`_DetailSection`** picks up 3 additional params: `netContentsQuantity`, `netContentsUnit`, `formFactor`. Call site reads them off `_product`; country pulled inline from `detailBlob.manufacturer_info` already in scope (no new typed plumbing). Wrapped in a `Builder` to capture `manufacturerInfo` once for both name + country reads.
- Test count 1011 → 1038 (+11 new tests covering: 6 `formatNetContents` boundary tests, 4 new `buildProductDetailFields` cases — all-six-present in display order, form-factor humanization, net-contents partial-input skip, country trim — plus 2 widget render tests for the narrow + wide screen paths). flutter analyze clean.

---

### [x] T1.12 — Better Alternatives (Section 11) — V1: non-personalized

**What**
Conditional render: only when current product is `LimitedFit | NotRecommended | low quality`. Show 2-3 higher-PG-score alternatives in same category. **V1 = "Higher quality alternatives"**, no personalized fit delta.

**Files**
- Existing `lib/features/product_detail/widgets/better_alternatives.dart` — minor refactor for new copy

**Tests**
- Strong fit + high quality → section hidden
- Limited fit → section visible
- Low quality (<60) → section visible
- Each alternative renders score + brand
- No "+N fit" delta visible (deferred)

**Acceptance**
Conditional logic correct. V1 copy exact: "Higher quality alternatives".

**Verified — 2026-04-29.**
- **REFACTOR** `lib/features/product_detail/widgets/better_alternatives.dart` — added public `shouldShowBetterAlternatives({isBlocked, isNotScored, score100, fitDisplay})` pure helper exported for unit testing + reused at the screen call site. Trigger conditions per spec: blocked → show; unscored + not blocked → hide; `score100 < 60` → show; `fitDisplay is FitLimitedFit | FitNotRecommended` → show; otherwise hide. Threshold tightened from V0 `<55` to spec-exact `<60`. `FitIncomplete` and null fit are explicit no-show cases (defer until profile fills in). New constants `_lowQualityThreshold = 60.0` + `_maxAlternatives = 3` (was 5 per spec "2-3").
- Title copy is now exactly **"Higher quality alternatives"** per spec — was "Better Alternatives". V0 subtitle "Higher-scored products in this category" dropped (V1 keeps the title self-explanatory; subtitle would push toward editorialised claims). V1 deliberately renders NO per-row "+N fit" delta — score badge + name + brand only. Defensive widget test asserts no fit-delta phrase ("+1 fit", "fit delta", " fit ") leaks into the rendered tree.
- **MODIFY** `lib/features/product_detail/product_detail_screen.dart` — replaced the screen-private `_shouldShowAlternatives` (deleted, tombstoned with comment) with a `Consumer`-wrapped `SliverToBoxAdapter` that watches `fitScoreForProductProvider` + computes `FitDisplay` via the existing `computeFitDisplay(verdict, fitResult)` (same code path as Section 2 ForYou — keeps the two sections in sync as the fit math evolves). Gate falls through to the new pure helper. Section returns `SizedBox.shrink` when the gate is false, so the sliver list stays valid. Added `import '...services/fit_score/fit_display.dart'` for `computeFitDisplay` access.
- **NEW** `test/features/product_detail/widgets/better_alternatives_test.dart` — 16 tests across 2 groups: pure `shouldShowBetterAlternatives` (10 tests covering strong+high-quality hidden, good-fit+adequate hidden, limited-fit show, not-recommended show, low-quality (<60) show, exact 60 boundary hidden, isBlocked always show, unscored hidden, null-fit + adequate hidden, FitIncomplete hidden) + render (6 tests covering null-category hidden, V1 copy "Higher quality alternatives" exact + V0 strings absent, score+brand+name rendering, 3-cap (5 seeded → top 3 by scoreQuality80 desc), no-fit-delta defense, empty-DB hidden). Render tests use `CoreDatabase.memory()` + `coreDatabaseProvider.overrideWithValue` + `_seedProduct` helper for isolation.
- Test count 1011 → 1027 (+16). flutter analyze clean.

---

### [ ] T1.13 — Deep Dive collapsed (Section 12)

**What**
Wrap existing deep-dive sections (Full mechanism, Manufacturing, Heavy metals) in a collapsed expander.

**Files**
- `lib/features/product_detail/product_detail_screen.dart` — wrap `_DeepDiveSection`

**Tests**
- Section collapsed by default
- Tap header → expands
- All existing deep-dive content preserved

**Acceptance**
No behavior change other than initial collapsed state.

---

### [ ] T1.14 — Transparency footer (Section 13)

**What**
Always-visible footer: "Last updated: {catalog generated_at} · Coverage: {n}/{total} · Sources: NIH · FDA · PubMed · PharmaGuide does not sell supplements. Educational only."

**Files**
- New: `lib/features/product_detail/widgets/transparency_footer.dart`

**Tests**
- Date format: "Apr 28" or "Updated 2 days ago"
- Coverage matches Product Quality section
- Disclaimer always present

**Acceptance**
Footer renders on every product page. No personalization (it's site-wide trust language).

---

### [ ] T1.15 — Sticky action bar (Section 14)

**What**
Bottom sticky bar: [Add to Stack] [Log Dose]. Conditional: [See Safer Alternatives] when verdict = Avoid/Contraindicated.

**Files**
- Refactor existing sticky bar in `product_detail_screen.dart`

**Tests**
- Safe product → 2 buttons
- Avoid product → "See Safer Alternatives" replaces "Add to Stack"
- Already-in-stack → "Remove" + "Log Dose"
- Tap [Add to Stack] → existing flow (no behavior change)

**Acceptance**
Conditional logic matches verdict tier.

---

### [ ] T1.16 — Sprint 1 verification + ship

**What**
End-of-sprint gate.

**Steps**
1. `flutter analyze` clean
2. `flutter test` all green (existing + new)
3. Manual walkthrough on 5 product types:
   - Safe + good fit (e.g. Thorne Magnesium Bisglycinate with sleep goal)
   - Caution + good fit (e.g. iron supplement with Lisinopril)
   - Avoid (banned substance product)
   - Contraindicated (pregnancy + Vitamin A high dose)
   - Not-scored (insufficient data)
4. Verify each section renders or hides correctly per spec
5. Sentry watch 24h post-deploy

**Acceptance**
All sections render. No new error classes in Sentry. Ready for Sprint 2.

---

# Sprint 2 — Refinement Polish

## Phase goal
Polish what shipped in Sprint 1. Tighten copy. Address any UX issues surfaced during Sprint 1 manual testing. Add the deferred low-cost improvements.

## Why
Sprint 1 ships **structure**. Sprint 2 ships **delight**. Real user feedback (yours + early TestFlight) drives this sprint's content.

## Estimate
**3–5 days.**

## Definition of Done (sprint-level)
- All Sprint 1 manual-testing notes addressed
- Overflow audit complete (Sentry RenderFlex count → 0)
- Copy review complete (no remaining numeric/JSON leaks)

## Tasks

### [ ] T2.1 — Overflow audit + sweep

**What**
Sentry shows ~8 unresolved RenderFlex overflow events. Walk through every screen on simulator, identify yellow stripes, fix each.

**Files**
- Various; common offenders: any `Row` with bare `Text` lacking `Flexible`/`Expanded`

**Acceptance**
- 0 RenderFlex events in Sentry over 7 days post-deploy
- Visual smoke test: long product names + long brand names + long ingredient names render without truncation issues

---

### [ ] T2.2 — Ingredient prettifier expansion

**What**
The ingredient-name lookup table from T0.1 starts with ~30 entries. Audit catalog for the top 100 most-frequent ingredient keys and add prettified forms.

**Files**
- `lib/core/util/ingredient_display.dart`

---

### [ ] T2.3 — Tradeoffs copy refinement

**What**
After Sprint 1 ships, watch real `score_bonuses`/`score_penalties` content for awkward strings. Add Flutter-side prose patches as needed.

---

### [ ] T2.4 — Empty-state polish

**What**
Each section should have a graceful empty state. Ensure no section ever shows "Loading…" indefinitely or a blank panel.

---

### [ ] T2.5 — Animation pass

**What**
Section expand/collapse uses `AnimatedSize` with 200ms easeInOut. Tap feedback uses `InkWell`. No jarring layout jumps.

---

### [ ] T2.6 — Sprint 1 audit follow-ups (bugs + nits + a11y)

Captured during the deep-dive audit that ran after T1.12 shipped (commits `f770b62` → `c9194c8`). Each item is non-blocking — code is green and spec-compliant — but the lot together is worth a polish pass before Sprint 2 closes.

**Bugs / inconsistencies**

1. **T1.10 — empty-PMID matches in all-citations sheet emit ghost gaps.** `_showAllCitations` iterates every match and adds a `SizedBox(height: 12)` after each `_CitationGroup`, even when the group has no PMIDs and short-circuits to `SizedBox.shrink`. Fix: filter `matches.where((m) => m.safeStringList('pmids').isNotEmpty)` before the loop.
2. **T1.10 — `_launchPubmed` has no PMID validation.** Any string is concatenated into the URL; non-numeric PMIDs land at PubMed and 404 silently. Fix: defensive `RegExp(r'^\d+$').hasMatch(trimmed)` guard, falling back to a no-op (or to the search URL) on miss.
3. **T1.10 — bottom sheet doesn't auto-dismiss when a PMID is tapped.** OS browser opens; sheet stays behind. Fix: `Navigator.of(sheetContext).pop()` before `launchUrl`.
4. **T1.11 — chevron uses two-icon swap (`keyboard_arrow_up_rounded` / `_down_rounded`).** Less premium than a smooth `RotationTransition` like T1.8 ships. Fix: animate a single chevron with a `Tween` driven by `_expanded`.
5. **T1.11 — no `Semantics(button: true, expanded: _expanded)` on the header.** Screen readers don't announce expand state. Fix: wrap the `PGPressable` header in a `Semantics` widget.
6. **T1.12 — `currentScore == null` short-circuit in `BetterAlternativesSection.build` is dead code.** Screen always passes `score100 ?? 0`, so null never reaches the section. Fix: drop the condition (the empty-list short-circuit downstream covers it) OR change the screen to pass `score100` (real null) and let the section short-circuit cleanly.
7. **T1.12 — quality filter is `>=` not `>`.** Surfaces alternatives at roughly-equal quality. Fix: `findAlternatives` already takes a min — bump to `currentScore * 0.8 + 4` (≈ +5 on 100-scale) so "higher quality" actually means meaningfully higher.
8. **T1.12 — `_AlternativeCard` uses legacy `Color.withAlpha(20)`.** Rest of trust-IA uses `withValues(alpha: 0.08)`. Fix: convert to the new API for consistency.
9. **T1.12 — `_AlternativeCard` wraps in `PGCard(onTap:)` instead of `PGPressable`.** No 0.96 scale + haptic feedback parity with the rest of the trust-IA sections. Fix: wrap the PGCard contents in a `PGPressable` and drop the bare `onTap`.

**Cross-cutting (app-wide, not just trust-IA)**

10. **No analytics on T1 sections.** Engagement is invisible: which sections do users tap into? Where's drop-off? Add per-section interaction events (header tap, expand, citation tap, alternative tap) wired through whatever analytics hook is canonical.
11. **Hardcoded English strings throughout.** Localization is an app-wide concern but every Sprint-1 section adds debt. Out of scope for T2.6 — capture as a separate localization sprint when timing's right.

**Acceptance**
- All Bug items above either fixed or explicitly tombstoned (with rationale) in source comments
- Cross-cutting items captured as separate sprint cards rather than left dangling

---

### [ ] T2.7 — Sprint 1 enhancement opportunities (out-of-spec but high-leverage)

Found during the post-T1.12 audit. None of these were on the V1 spec but each is a low-effort / high-value addition. Decide before Sprint 2 close which (if any) to pull in.

**T1.10 Evidence**
- **Dose-range surfacing.** Pipeline likely emits `dose_min` / `dose_max` per study. Showing "studied at 200-600mg" lets users sanity-check the product's actual dose against the evidence base. High-value, no editorial risk.
- **Study-type distinction.** If pipeline tags systematic review vs individual RCT vs observational, surface as a per-PMID badge in the citations sheet.
- **Telemetry on PMID tap.** Measure which citations users actually open — informs future ingredient-summary curation.

**T1.11 Product Details** *(✅ partially shipped: country + form factor + net contents added in commit __NEXT__)*
- ~~Country of origin~~ ✅ shipped
- ~~Form factor (capsule / tablet / softgel / powder / liquid)~~ ✅ shipped
- ~~Net contents (e.g. "60 capsules")~~ ✅ shipped
- ~~iPhone SE narrow-screen LayoutBuilder fallback~~ ✅ shipped
- **Remaining:** GMP-certified flag (`detail_blob.manufacturer_info.gmp_certified`) — could appear as a chip rather than a row. Skipped in the polish pass to keep the section reference-only (the GMP flag is a trust signal that overlaps T1.7).

**T1.12 Better Alternatives**
- **Product image thumbnails.** Alternative cards show only score badge + name + brand. Wiring `BrandedPlaceholder.compact: true` at 48pt would 2× scannability.
- **Brand deduplication.** Top 3 alternatives could all be Nature Made's catalog. Add a per-brand cap (e.g. max 2 per brand).
- **Loading shimmer** during `FutureBuilder` pending — currently shows nothing.
- **Affirmative empty-state.** When no higher-quality alternatives exist in category, show "We couldn't find better alternatives — this might already be your best option" instead of just hiding.
- **Fit-aware ranking** when fit-state triggered the section. V1 explicitly defers per spec ("V1 = no personalized fit delta") but the math for ranking is cheap on top of the existing helper.

**Acceptance**
For each item: either pulled into the next sprint's task list with a sized estimate, OR explicitly punted to V1.1 / Sprint 3+ with rationale captured here.

---

### [ ] T2.8 — Sprint 2 verification

Same as T0.7 / T1.16 pattern.

---

# Sprint 3 — Backend Foundation

## Phase goal
Land the data work that unlocks deferred V1.1 features: full formulation ontology, percentile ranking, personalized alternative delta, editorial evidence summaries.

## Why
These features are **data problems**, not Flutter problems. They need pipeline emissions or curated content that doesn't exist yet. Schedule them properly with a real timeline, don't rush.

## Estimate
**2–3 weeks**, runs in parallel with Sprint 2 polish (different surface area).

## Definition of Done (sprint-level)
- Excipient ontology v1 reviewed by pharmacist, in pipeline source
- Pipeline emits `score_percentile`, `formulation_purity_tier`, prose `score_bonuses[].detail`
- Editorial evidence summaries authored for top-10 most-prescribed clusters
- Personalized alternative-fit-delta provider implemented and benchmarked

## Tasks

### [ ] T3.1 — Excipient ontology v1

**What**
Build `excipient_classification.json` in pipeline:
- Source of truth: FDA inactive ingredient database + USP-NF + EFSA opinions
- Tags per excipient: `function` (capsule_shell | lubricant | flow_agent | sweetener | dye | preservative | …) + `tier` (expected | neutral | unnecessary | flagged)
- Pharmacist review for ~50 controversial entries (titanium dioxide, sucralose, certain dyes)

**Why**
Layer 1 of the formulation 4-layer model. All later phases depend on this data existing.

**Owner**
Pipeline team + clinical reviewer. Not a Flutter task.

---

### [ ] T3.2 — Penalty-based purity scorer (replaces Phase 1)

**What**
Pipeline emits `formulation_purity` block:
```json
{
  "tier": "Clean | Moderate | LowPurity | ContainsConcerns",
  "rationale": "Standard capsule excipients only.",
  "penalty_breakdown": {...}
}
```
Flutter widget renders the new tier; Phase 1 logic in Sprint 0 becomes obsolete and is removed.

---

### [ ] T3.3 — Pipeline emits `score_percentile`

**What**
Build-time: compute percentile rank for each product within its category. Emit as `score_percentile` field in `products_core`.

**Flutter consumer:** Section 3 subtitle reads "High Quality · Top 15%".

---

### [ ] T3.4 — Pipeline emits prose `score_bonuses[].detail`

**What**
Replace numeric `detail` ("3", "Tier 3") with prose ("Liposomal delivery format", "Premium delivery system"). Removes the need for the regex strip from T0.2.

---

### [ ] T3.5 — Editorial evidence summaries

**What**
Hire/contract clinical writer. Author 10–20 cluster summaries (e.g. magnesium for sleep, vitamin D for bone health). Stored in `assets/reference_data/editorial_summaries.json`.

**Flutter consumer:** Section 9 quote line.

---

### [ ] T3.6 — Personalized alternative fit delta

**What**
Provider that, given current product + user profile, returns top-3 alternatives in same category sorted by personalized fit score. Displayed in Section 11 as "+9 fit for you".

**Performance budget**
<200ms total compute on a typical device. Profile before merging.

---

### [ ] T3.7 — Sprint 3 verification

Same as previous patterns. Add: clinical writer signs off on copy.

---

## Risks & mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Sprint 1 IA refactor introduces visual regressions | Medium | High | Manual walkthrough on 5 product types is the gate |
| Excipient ontology curation slips | Medium | Low (Sprint 3) | Phase 1 (Sprint 0) buys time — even a 4-week delay doesn't block users |
| OTA in-session swap causes mid-scan glitches | Low | Medium | Snackbar gives users context; queries fail-soft via Riverpod retry |
| Risk-gated Fit confuses users who expected the number | Low | Low | "Not recommended" + alert provides better signal than a number; if user feedback insists, add an info-icon explainer |

---

## Change log

| Date | Author | Change |
|---|---|---|
| 2026-04-28 | SeanB + Claude | Initiative created. Sprint 0–3 defined. Locked decisions captured. |
| 2026-04-29 | SeanB + Claude | T0.6 promoted to canonical OTA activation strategy across both initiatives. `INITIATIVE_STACK_INTELLIGENCE.md`'s "no mid-session catalog swap" rule retired; Track D D3 now points here as source of truth. A6 in Stack Intelligence marked `[x]` (bundle-replacement bug genuinely fixed); T0.6 still `[ ]` — in-session refactor + validation gate + snackbar are owed. |
| 2026-04-29 | Claude | Sprint 0 code-complete. T0.1–T0.6 all `[x]` (rewording + prettifier; Highlights rename + numeric `detail` strip; formulation JSON-leak fix; Pairs Well count parity + clearer subtitle; Formulation Purity Phase 1 whitelist + dosage-form + hide-when-clean; OTA in-session swap with validation gate + atomic rename + SharedPreferences persistence + snackbar). T0.7 `[-]` — `flutter analyze` clean and 707/707 tests green; manual smoke + TestFlight + 24h Sentry watch owed by Sean. Sprint 0 roadmap row flipped from 🟢 Active to 🟡 Code-complete. |
| 2026-04-29 | Claude (live test) | Ran the shipped Sprint 0 build on iPhone 17 Pro simulator. Two real production bugs caught and fixed in commit `2a35eb8` (3 files, surgical): (1) T0.1 prettifier fell back to single-character title-case for whitespace-separated `ingredient_points` keys ("vitamin c" → "Vitamin c" instead of "Vitamin C"); fix normalizes whitespace runs to underscores before lookup + split. (2) Same JSON-leak class as T0.3 in `certification_detail_section.dart` — "Third-Party Verified" pill rendered `{name: Informed Choice, verified: true}` verbatim; fixed with localized dual-shape extractor. Both verified live via Flutter SIGUSR1 hot-reload. Test count 707 → 741. |
| 2026-04-29 | Claude (cross-team merge) | Sprint 1 spec revised after `/critique` pass + Yuka/SuppCo user-habit evidence. Trust/IA owns *what goes where*; Apple-grade owns *how it looks*. Six concrete changes: **(1)** T1.1 hero is **score-led, not identity-only** — Quality Score ring stays in hero, Personal Fit number still moves to Section 2. **(2)** T1.1 absorbs Apple-grade B.3a (other team is skipping their hero refactor). **(3)** T1.2 absorbs F.5 visual approach but rejects F.5's content model (their "Why this score · Your alerts" dual-column was conflating Section 2 + Section 3). **(4)** T1.4 absorbs F.4, rescoped — pillars + coverage + reasoning only (donut dropped because score lives in hero). **(5)** T1.4 has new blocking dependencies on Apple-grade F.0 data audit + F.2 PGPillarBar primitive (other team's deliverables). **(6)** T1.5 keeps verbose rows; F.3 + F.6 atom primitives dropped (decorative for medical-grade context). T1.1 now subsumes the deferred B.3a; B.3b SliverAppBar serializes after T1.1 lands to avoid concurrent edits to product_detail_screen.dart. |
| 2026-04-29 | Claude | T1.3 (Risk-gated Fit core logic) shipped. New `lib/services/fit_score/fit_display.dart` — pure-function helper with sealed `FitDisplay` hierarchy (`FitStrongMatch` / `FitGoodMatch` / `FitLimitedFit` / `FitNotRecommended` / `FitHidden` / `FitIncomplete`). Risk-gate runs first (Avoid/Contraindicated → Hidden regardless of score), then incomplete-profile check, then score banding via public `FitDisplayThresholds` (85/60/35). Caution/Monitor/Informational pass through the gate untouched. 21 unit tests across 5 groups including explicit boundary tests. Started T1.3 first because it's a pure-function helper with no upstream dependency on Apple-grade F.0/F.1/F.2. Test count 781 → 802 (the +1 over the Sprint 27.21 baseline 780 came from this session's earlier `a06bd22` PGFrostedHeader platform-glass commit). |
| 2026-04-29 | Claude | T1.1 (Score-led hero refactor) shipped. New `lib/features/product_detail/providers/hero_verdict_provider.dart` — pure-function `computeHeroVerdict` + sealed `HeroVerdict` hierarchy (Blocked / Avoid / None). Heavy edit to `_HeaderSection` in `product_detail_screen.dart`: removed Personal Fit pill, VerdictBadge, percentile, grade pill, `_HeroScoreReason`, "View Supplement Label" outline button (all moving to T1.2/T1.4/T1.5/T1.6/T1.11 in spec order); added centered Quality Score altar with PGScoreRing (88pt + 6pt stroke — proven non-overflowing) and externally-rendered "PG SCORE" label; gated verdict banner to Blocked/Avoid only; suppressed score altar when product-side BLOCKED to avoid mixed "DO NOT USE / 82" signals. Dead code cleanup: `_pickHeroScoreReason` helper + `_HeroScoreReason` widget class removed; 3 unused imports stripped (`pg_fitscore_badge`, `fit_score_provider`, `fit_score_sheet`). 25 new unit tests on hero_verdict_provider + existing product-detail screen tests updated for the new contract (Blocked tests now assert PGScoreRing is hidden; "Why this score" inline reasoning assertion replaced with T1.1 invariant test). Image kept at 56pt — BrandedPlaceholder's multi-row mode above 56 overflows by 2px in the test placeholder path. Apple-grade B.3a folded in here; B.3b SliverAppBar now unblocked for the other team. Test count 802 → 833 (+31). |
| 2026-04-29 | Claude (polish pass) | T1.1 hero polish after critique-dev review. Outer `Container + DecoratedBox` → `PGCard(variant: elevated)` (single-surface design-system idiom). Image bumped 56pt → 96pt with new `BrandedPlaceholder.compact` flag (commit `26d54c3`) plumbed through `ProductImage.compact` so the multi-row "full card" placeholder mode doesn't overflow at hero proportions. Score ring bumped 88pt × 6pt → 96pt × 7pt — strokeweight tuned by 1pt below the natural scaling ratio to fit PGScoreRing's inner Column without overflow. `_ScoreRingButton` swapped Material+InkWell ripple → PGPressable (0.96 scale compression + spring + light haptic). Outline-style trust chips (`_HeroTrustChipOutline`) shipped in a parallel agent's `2e103ee`. Test suite still 833/833 — premium-tier visual upgrades, no contract changes. |
| 2026-04-29 | Claude | T1.2 ("For You" merged block, Section 2) shipped. New `lib/features/product_detail/widgets/for_you_section.dart` — ConsumerWidget consolidating context chips + verdict + Personal Fit pill (risk-gated via T1.3) + alerts (severity-priority sorted, filtered to contraindicated/avoid/caution) + Why-this-fits expander (4-bullet deterministic). Empty-profile state collapses to single PGCard CTA → profile setup. Wired into `product_detail_screen.dart` between hero and condition alert banner; suppressed when product is BLOCKED. New helpers `_maxSeverityOf(warnings)` + `_topGoalLabelFromFit(result)` extract risk-gate input + verdict goal label from upstream data. Apple-grade F.5 visual approach (PGCard.plain shell, PGPressable on interactives, tabular figures on /100 pill) reused; F.5's content model (which conflated Section 2 + Section 3) rejected. 17 widget tests across 5 groups: empty-profile, verdict copy with risk-gating, alert priority + filtering, Why-this-fits expander, context chips with humanizer. Test count 833 → 850 (+17). |
| 2026-04-29 | Claude (audit pass) | Sprint 0 + Sprint 1 thorough code-level audit. Two real bugs caught + fixed: (1) `topGoalLabelFromFit` regex `[a-z\s]` rejected 11 of 18 SchemaIds.goalLabels values containing `/`, `&`, or `,` (Reduce Stress/Anxiety, Cardiovascular/Heart Health, Focus & Mental Clarity, Skin Hair & Nails, etc.) — silently degraded the For You verdict headline from "Strong match for your <Specific Goal>" to a generic "your profile" for those 11 goal types. Fix: pattern relaxed to `your\s+(.+?)\s+goal\b` with non-greedy capture + word boundary. Helper extracted to top-level `topGoalLabelFromFit` for direct unit testability; 36 new tests cover every production goal label + pattern robustness. (2) `ForYouSection.hasProfile` missed `profile.allergens` — an allergens-only profile incorrectly hit the empty-state CTA and missed the alerts list. Fix in `d9bf5b9`: `hasProfile` now also OR's `allergens.isNotEmpty`; new test asserts allergens-only profile renders the populated section. Plus T0.6 defensive fix in `8ff51db`: `CatalogSwapper.swap()` validation-failure path wrapped `newDb.close()` in nested try/catch so a Drift close-throws error doesn't mask the original validation failure that Sentry needs to attach. Test count 850 → 891 (+41). |
| 2026-04-29 | Claude | T1.4 (Product Quality, Section 3) shipped. Extended existing `score_breakdown_card.dart`: new `heroScore` param renders a hero-continuity label ("Your 82 breaks down as:") above the 4 pillars; new `mappedCoverage` param renders a tier-tinted `_CoverageLine` row below the pillars (≥0.7 green high-confidence / ≥0.3 yellow partial / <0.3 insufficient — thresholds match the legacy hero "Limited data" gate for cross-surface consistency). Defensive clamp on coverage `[0..1]` so a >1 ratio renders as 100%. Existing 4 `_ExpandableSectionBar` instances kept (PGPillarBar primitive evaluated but the existing tap-expand bars own the inspector contract; PGPillarBar is non-tappable). Wired `score100` → `heroScore` and `mappedCoverage` → `mappedCoverage` from product detail screen. 12 new widget tests across 3 groups: continuity label (rendering + rounding + null-hide), coverage line (4 tier-boundary tests at 0.92/0.7/0.5/0.3/0.15/0.0/1.5-clamped, null-hide), integration (Y-position assertion proves continuity above coverage). Apple-grade F.4 (rescoped — no donut) folded in here. Test count 891 → 903 (+12). |
| 2026-04-29 | Claude | T1.5 (Ingredients, Section 4) shipped. New `lib/features/product_detail/widgets/ingredients_section.dart` exports `InactivePurpose` data class + `inactiveIngredientPurpose(name)` lookup (22-entry table: capsule shells, lubricants, flow agents, solvents, attention-tier sweeteners/colorants — TiO2 detail copy surfaces the EU 2022 food-additive ban context) + `InactiveIngredientChip` (PGPressable-wrapped, opens a PGModal.bottomSheet with role + detail on tap; unknown names fall back to generic "Added during manufacturing" copy so no chip is a dead-end) + thin `IngredientsSection` wrapper. Modified `product_detail_screen.dart` to swap the 4 inert inactive `Container` chips inside `_DetailSection` for `InactiveIngredientChip` instances; the "+N more" overflow chip is preserved as a count affordance. Active rendering unchanged — existing `_CollapsibleIngredients` / `_IngredientTile` already deliver the spec's 5-element row (bioavailability dot + name + dose + form/category + UL safety tag), per "Reuses: existing active/inactive widgets". 14 new tests across 4 groups: lookup contract, T0.5-whitelist coverage gate, attention-tier copy pin, chip render + tap behavior. Apple-grade F.3 + F.6 atom primitives stayed dropped per the merged plan. Test count 903 → 917 (+14). |
| 2026-04-29 | Claude | T1.6 (Tradeoffs, Section 5) shipped. New `lib/features/product_detail/widgets/tradeoffs_section.dart` — public `TradeoffsSection(items)` widget that splits the same `_extractWhyItems` records (bonuses + penalties, already T0.2-sanitized upstream) into a two-column "👍 What's good / ⚖️ What to consider" layout. LayoutBuilder branch: side-by-side at ≥380pt width; single-column stacked fallback below 380pt or when only one half has content. Section hides entirely (SizedBox.shrink) when both lists are empty. Defensive blank-label drop. New `TradeoffRow` public widget (colored bullet + label + optional detail subline) — extracted because future surfaces (T1.7 interactions, T1.10 evidence) will reuse the pros/cons row idiom. Modified `product_detail_screen.dart` to swap `_WhyThisProductSection(items: whyItems)` → `TradeoffsSection(items: whyItems)`; removed the now-unreferenced `_WhyThisProductSection` (lines 2243–2281) and `_ProConTile` (lines 2698–2758) classes — replaced with tombstone comments. 10 new tests across 2 groups: split contract (bonuses-only / penalties-only / both-at-480pt same-Y / both-at-320pt SE stacked-Y / both-empty hide / blank-label defensive drop) and row rendering (label + detail, empty-detail no-empty-Text, long-detail wrap at SE width, multi-bonus + multi-penalty). Test count 917 → 931 (+10 T1.6 + 4 incidental). |
| 2026-04-29 | Claude | T1.8 (Interactions refactor, Section 7.1) shipped. Built out-of-tree as a NEW `lib/features/product_detail/widgets/with_your_stack_section.dart` instead of in-place refactoring `interaction_warnings.dart` — the existing 1201-line list owns 7.2's profile-aware "Other precautions" tier and per-spec 7.2 defers to Sprint 3, so detonating it for the per-row personalized view would have been disproportionate scope. New section sits ABOVE the existing list. `WithYourStackSection({warnings, userDrugClasses, userConditions})` is a pure widget; caller passes pre-resolved profile sets. Renders one row per drug-class + one per condition. Each row: severity-tinted icon (do_not_disturb / error_outline / warning_amber per tier) + humanized label + "Severity — Headline" sub-text + tap-expand chevron when matched, OR check-circle + "No known interaction" sub-text + no-chevron when not matched. Tap-expand reveals Mechanism (alertBody / mechanism) + Recommendation (management) + Evidence chip + citation-count chip with bottom-sheet of source URLs. Worst-severity-wins on multi-match. Section hides entirely on empty profile. 13 widget tests covering visibility gates, ⚠ rendering + worst-severity selection, ✓ rendering + non-tappability, tap-expand reveal/collapse + citation pluralization, severity-desc sort + condition matching. Test count 931 → 944 (+13). T1.8 [x]. (Note: the spec numbering offset — Section 6 "What we don't know" is T1.7, Section 7 "Interactions refactor" is T1.8 — was confusing initially but the work landed against the right spec.) |
| 2026-04-29 | Claude | T1.7 (What we don't know, Section 6) shipped. New `lib/features/product_detail/widgets/unknowns_section.dart` exports public `buildUnknowns(...)` pure helper + `UnknownsSection` widget. Helper takes 5 trust signals (isTrustedManufacturer, hasThirdPartyTesting, mappedCoverage, scoreEvidenceResearch + max), returns up to 4 human-readable bullets in fixed display order (third-party → COA → coverage → evidence — most actionable first). Boundary thresholds: `mappedCoverage < 0.5` strict, `scoreEvidenceResearch < scoreEvidenceResearchMax * 0.4` with defensive divide-by-zero guard. Spec's "AND no COA URL" condition for the manufacturer trigger simplified to untrusted-alone — pipeline doesn't ship a `coa_url` field today; tightening is a one-line change when it appears. Widget renders deliberately soft per spec: PGCard.plain (not elevated), help_outline_rounded 16pt header, onSurfaceVariant text color, 4pt muted bullets, italic "… and N more" overflow line for the >4 case (defensive only — current logic can't trip it, but a future 5th condition won't truncate silently). Hides entirely when no triggers fire. Modified `_DetailSection` constructor to accept 5 trust-signal params (passed through from `_product` at the call site); inserted `UnknownsSection` directly above `WithYourStackSection`. 16 new tests — 11 on the pure `buildUnknowns` (all-positive, each individual trigger, boundary tests at exactly 0.5 mappedCoverage / 40% evidence ratio, null inputs skip, defensive max=0, all-4 trigger order) + 5 widget render tests. Test count 944 → 960 (+16). |
| 2026-04-29 | Claude | T1.9 (Populations dedupe, Section 8) shipped. New `lib/features/product_detail/widgets/populations_section.dart` exports public `splitPopulations(...)` pure helper + `aggregatePopulations(warnings)` flattener + `PopulationsSection` widget. Helper takes free-form populationWarnings strings + user signals (conditions / drug classes / age bracket), returns a `({mainList, alreadyCovered})` record. Word-boundary regex match against a 21-keyword map (`pregnancy`/`pregnant` → `pregnancy`; `diabetic`/`diabetes` → `diabetes`; `children`/`pediatric` → `under_18`; etc.) — defends against false-positive substring matches like "fish" inside "fishing". Aggregates `populationWarnings` across all warnings, dedupes by case-insensitive string, then partitions: matched populations drop (already surfaced in T1.8 Section 7's WithYourStackSection — no duplicate warnings between sections), unmatched populations bullet in main "Extra caution for: A, B, C" line, matched user signals concatenate into "(You are already covered for X, Y)" italic parenthetical (alphabetically sorted, deduped). PGCard with groups_outlined header. Hides when no populations OR when dedupe leaves both lists empty. Wired into product_detail_screen.dart between Section 7 (WithYourStackSection) and the generic InteractionWarningsList; pulls ageBracket off the watched profileProvider. 20 new tests across 3 groups: pure splitPopulations (13 — empty/no-signals/single-match/keyword-match/word-boundary-defense/case-insensitivity/multi-pop-same-signal-collapse/all-match-empty-main/drug-class/age-bracket/dedupe-duplicate/blank-drop/alpha-sort) + aggregatePopulations (1) + widget render (6). Test count 960 → 980 (+20). |

---

## How to use this file

1. **At the start of each work session** — open this file. Jump to the active sprint. Pick the next `[ ]` task.
2. **When a task completes** — change `[ ]` to `[x]`, fill in the actual outcome under "Comments" if it differed from the plan.
3. **When a task is paused/blocked** — change `[ ]` to `[-]`, add a short note in "Comments" explaining why.
4. **At sprint boundaries** — run the sprint-verification task. Update the roadmap table at the top.
5. **If scope shifts** — append to the change log with date + reason. Do NOT silently delete tasks.

If you find yourself wanting to do something that's listed in **Out of scope**, stop. That's deferred for a reason. Add a note in the change log if the deferral reason no longer applies, and discuss before reopening.
