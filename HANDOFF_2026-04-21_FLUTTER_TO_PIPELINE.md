# Handoff — 2026-04-21 Flutter → Pipeline Team

**From:** Flutter PharmaGuide team (device-testing findings from catalog `v2026.04.21.164306`)
**To:** Pipeline repo (`PharmaGuide_Pipeline`)
**Priority:** Medical safety. Several categorization issues in pipeline output render as user-facing safety defects on Flutter. Flutter is adding a defensive rendering layer in parallel (Sprint 27.7) but these are **upstream data problems** — defensive filters are a band-aid.

---

## TL;DR

Device testing on the bundled catalog surfaced 7 categorization / semantic defects in pipeline output. Flutter can mask the worst of them with defensive filters, but the real fix is upstream. None of these require a schema change — they're all content / classification fixes within existing fields.

| # | Defect | Severity | Pipeline fix scope |
|---|--------|----------|-------------------|
| 1 | `decision_highlights.positive` contains danger text | **CRITICAL** | Re-classify per product |
| 2 | `warnings_profile_gated` with `display_mode_default="critical"` + condition-specific copy | **CRITICAL** | Re-classify or rewrite copy |
| 3 | 6× duplicate warning emissions per product | **HIGH** | Dedup at build time |
| 4 | `has_banned_substance=1` without authored block-preflight copy | **HIGH** | Add 2 new authored fields |
| 5 | `ban_ingredient` raw enum leaking to UI (copy fallback chain) | **HIGH** | Audit Dr Pham fallback coverage |
| 6 | Enzyme products score 0/25 Section A | **MEDIUM** | New scorer micro-metric |
| 7 | Singular `condition_id` vs plural `condition_ids` inconsistency | **MEDIUM** | Schema audit |

Ship order is ours to pick — Flutter Sprint 27.7 ships a defensive layer regardless. Safety-critical upstream fixes (#1, #2, #4) unblock the permanent fix. Cosmetic (#6, #7) can wait for next pipeline sprint.

---

## Defect #1 — `decision_highlights.positive` contains danger text

**CRITICAL.** Safety-inverted signal in `decision_highlights` shown at the top of every product detail page.

### What Flutter sees

User scanned a banned CBD product (VitaFusion CBD Mixed Berry) and observed these lines in the `decision_highlights.positive` bucket:

- "Not lawful as a US dietary supplement. Talk to your doctor." → rendered as **green thumb-up**
- "Concentrated added sugar. Some can carry trace arsenic." → rendered as **green thumb-up**
- "Undisclosed colorant. Transparency concerns." → rendered as **green thumb-up**
- "Diabetes. Contains high glycemic sweetener." → rendered as **green thumb-up**

### What the pipeline is emitting

`decision_highlights` JSON with `positive`, `caution`, `trust` string keys. The above strings are landing in `positive`. They are danger signals, not positives.

### What Flutter renders

[`lib/features/product_detail/product_detail_screen.dart:2501-2566`](lib/features/product_detail/product_detail_screen.dart:2501) — `_DecisionHighlights` trusts the pipeline bucket:

```dart
final positive = parsed['positive']?.toString() ?? '';
final caution = parsed['caution']?.toString() ?? '';
final trust = parsed['trust']?.toString() ?? '';
// positive → green thumb_up
// caution → amber info
// trust → evidence-strong verified
```

### Ask

1. **Audit `decision_highlights` categorization** across all 8,288 products. Any string containing danger keywords (`not lawful`, `banned`, `talk to your doctor`, `arsenic`, `trace metals`, `undisclosed`, `high glycemic`, `contraindicated`) must go in `caution` or a new `danger` bucket — never `positive`.
2. **Add a `danger` key** to the decision_highlights JSON. Three-bucket is too coarse when a product has hard contraindications.
3. **Pipeline build-time validator**: fail the build if any `positive` string matches a deny-list regex (see keywords above).

### Flutter-side defense (Sprint 27.7)

Severity keyword scan on `positive` strings; auto-promote to `caution` and log a Sentry breadcrumb with `product_dsld_id` + the offending text so pipeline team can fix upstream. This stays in place permanently as defense-in-depth.

---

## Defect #2 — `warnings_profile_gated` mis-categorized as `critical`

**CRITICAL.** Condition-specific warning copy shown to users who don't have that condition.

### What Flutter sees

Male user, no liver disease / pregnancy in profile. VitaFusion CBD Mixed Berry detail page shows:

- "Not recommended during pregnancy" — rendered 6 times
- "Not recommended for liver disease" — rendered

These warnings carry `condition_id` / `drug_class_id` tags, so they should be suppressed for users whose profile doesn't match.

### What the pipeline is emitting

Flutter's profile-gating logic ([`product_detail_screen.dart:1603-1629`](lib/features/product_detail/product_detail_screen.dart:1603)) is correct:

```dart
// display_mode_default: "critical" → always show
// display_mode_default: "informational" → always show (neutral)
// display_mode_default: "suppress" → hide unless profile matches
```

The pipeline is emitting condition-specific warnings with `display_mode_default: "critical"`. "Critical" means "always show regardless of profile" — but the **copy** is condition-specific ("not recommended during pregnancy"). Result: pregnancy copy shown to male users, liver-disease copy shown to users with no liver condition.

### Ask

Two paths, pick one:

**Path A (preferred):** Rewrite warning copy to be profile-agnostic when `display_mode_default: "critical"`:
- ❌ "Not recommended during pregnancy."
- ✅ "May affect pregnancy — consult a physician before use."

Critical-mode warnings are shown to everyone, so copy must address everyone.

**Path B:** Leave the condition-specific copy, but change `display_mode_default` to `"suppress"` for any warning where the copy references a specific condition. Let profile-gating do its job.

**Either path:** add a pipeline build-time validator — if `display_mode_default == "critical"` AND copy matches `/(during pregnancy|for liver disease|breastfeeding|kidney disease|heart disease|while nursing)/i`, fail the build.

### Flutter-side defense (Sprint 27.7)

Defensive regex filter on warning text; if it references a condition not in user profile, treat as `suppress` regardless of pipeline's `display_mode_default`. Log mismatch to Sentry for upstream audit.

---

## Defect #3 — 6× duplicate warning emissions

**HIGH.** Same warning rendered 6 times on VitaFusion CBD Mixed Berry page.

### What Flutter sees

`warnings_profile_gated` (and possibly `warnings`) arrays contain 6 near-identical pregnancy warnings, likely differing only in `mechanism` text whitespace / punctuation / slight wording.

### What's happening

Flutter dedups by `'${severity.name}:${mechanism}'` at [`product_detail_screen.dart:309-317`](lib/features/product_detail/product_detail_screen.dart:309). If the pipeline emits 6 copies with any variation in mechanism text, all 6 survive.

### Ask

1. **Pipeline-side dedup at build time** — collapse warnings where `(severity, canonical_id, condition_id, drug_class_id)` tuple is identical. Prefer the most specific authored copy; fall back to the first.
2. **Audit why 6 copies exist** — are they from different source rules (e.g. one from `banned_recalled`, one from `high_risk_ingredient`, one from `ingredient_interaction_rules`)? If so, the dedup key should include the source rule.

### Flutter-side defense (Sprint 27.7)

Stronger dedup key: `sha1(severity + lowercase(mechanism).normalized + conditionIds.sorted.join + drugClassIds.sorted.join)`. Catches near-duplicates from text variations.

---

## Defect #4 — `has_banned_substance=1` without authored block-preflight copy

**HIGH.** Flutter needs a critical UI guardrail when a user adds a banned product to their stack. No pipeline-authored copy exists to show.

### Context

`products_core.has_banned_substance` column is populated (integer 0/1) — that part works. But when Flutter's stack-add safety preflight detects it, there's no authored "Here's what's banned and why" copy to show the user.

Flutter currently shows no guardrail (this is Sprint 27.7 bug #1). We'll add one, but it needs authored copy from upstream.

### Ask

Two new fields on `products_core` (or equivalent in the detail_blob):

| Field | Purpose | Constraints | Example |
|-------|---------|-------------|---------|
| `banned_substance_preflight_one_liner` | Stack-add confirmation banner copy | ≤ 80 chars, plain language, action-framed | `"Contains cannabidiol — not a lawful US supplement ingredient."` |
| `banned_substance_preflight_body` | Expandable detail on the confirmation sheet | ≤ 200 chars, cites regulatory action | `"FDA has not approved CBD as a dietary supplement. May interact with liver enzymes and medications."` |

Both authored per-product by safety team (same pharmacist/MD review as Sprint 27.6 Path C). Same build-time validators: non-empty, within char limits, no encyclopedic-definition leading clause.

### Flutter-side (Sprint 27.7)

A new `CRITICAL` state in [`safety_check_sheet.dart`](lib/features/product_detail/widgets/safety_check_sheet.dart) — red banner with the two fields above, "Cancel" primary button, "Add anyway" destructive with long-press confirmation. Currently Flutter has no data to feed this state; once pipeline ships the fields, Flutter wires them.

---

## Defect #5 — `ban_ingredient` raw enum leaking to UI

**HIGH.** User saw literal string `ban_ingredient` rendered as the warning label on a banned product scan.

### What's happening

`InteractionWarning.type` or similar type-enum field is rendering as-is somewhere in the copy fallback chain. The expected authored copy (`alertHeadline` / `alertBody` / `safetyWarningOneLiner` via Dr Pham) wasn't populated, so the renderer fell through to the raw enum name.

### Ask

1. **Audit which warning types can have `safety_warning` / `safety_warning_one_liner` empty.** Any type that the Flutter `InteractionWarning.fromJson` fallback chain touches must have authored copy — never emit a warning with bare `type: "ban_ingredient"` and no body.
2. **Build-time validator:** for every emitted warning, assert at least one of `(alert_headline, alert_body, safety_warning, safety_warning_one_liner, detail)` is non-empty. Fail the build otherwise.
3. **Coordinate with Sprint 27.6 Path C** — same safety-team authoring pass should cover this. `safety_warning_one_liner` is already on the Path C scope.

### Flutter-side (Sprint 27.7)

Never render a bare `type` enum. If copy is missing, render `"Flagged ingredient — tap for details"` as a placeholder and log a Sentry error with `dsld_id` + warning type so pipeline team can see which products have missing copy.

---

## Defect #6 — Enzyme products score 0/25 in Section A

**MEDIUM.** Thorne Plantizyme (DSLD 35491) and similar enzyme-focused products score `score_ingredient_quality = 0.0 / 25.0` despite `mapped_coverage = 1.0` (all 5 enzymes mapped).

### Why

Section A scores bioavailability forms, dose adequacy, premium forms, synergy, omega-3 dose. Digestive enzymes (Bromelain, Protease, Amylase, Lipase, Cellulase, etc.) have:
- No RDA / no UL
- No bioavailability form tiers
- No "premium form" signals
- No modeled activity-unit scoring (HUT, FCC, ALU, DU, SKB)

Five mapped enzymes × 0 points = 0/25. Product total comes out 29.5/80 from Safety & Purity alone. In the app this displays as "0" across every Section A sub-metric with 5 ingredients visible — misleading to users.

### Ask

New micro-metric: `A8_enzyme_potency` (or `A8_activity_units`) with:
- Unit-aware dose tiers per enzyme (e.g. Bromelain: `<1000 FCC PU` poor / `1000-2000` adequate / `2000-2400` good / `>2400` excellent)
- Activity unit parser (HUT, FCC PU, ALU, DU, SKB, AGU, LU) — the pipeline has these in labels already
- Cap similar to other A-section caps (suggest 8–10 pts)
- Triggers only when product has ≥2 enzymes mapped AND ≥60% have activity-unit data

Reference data: FCC food chemicals codex / SKB units for amylase, HUT for protease, etc. — mostly covered by `NOW Foods` / `Thorne Research` / `Enzymedica` labels in the catalog.

### Flutter-side (Sprint 27.7, not blocking pipeline)

Detect "Section A all-zero with ingredients > 0" case in [`score_breakdown_card.dart`](lib/features/product_detail/widgets/score_breakdown_card.dart). Render `"Scoring not yet modeled for this product type"` placeholder instead of a misleading "0". Removes the user-facing confusion while pipeline team adds A8.

---

## Defect #7 — Singular `condition_id` vs plural `condition_ids` inconsistency

**MEDIUM.** Two field-naming conventions in pipeline output for the same kind of tag.

### What Flutter sees

- [`product_detail_screen.dart:976-977`](lib/features/product_detail/product_detail_screen.dart:976) parses `condition_ids` / `drug_class_ids` (**plural, array**) in `interaction_summary_hint`
- [`interaction_warnings.dart:229-230`](lib/features/product_detail/widgets/interaction_warnings.dart:229) parses `condition_id` / `drug_class_id` (**singular, scalar**) in warning entries

If the pipeline ever emits a plural array on a warning entry, Flutter silently drops the extras → partial profile gating → warnings leak.

### Ask

Audit the pipeline schema and confirm which shape each surface emits:

1. `interaction_summary_hint.condition_ids` — plural array (confirmed by user copy)
2. `warnings[*].condition_id` — singular scalar (per Flutter parser, but unverified)
3. `warnings_profile_gated[*].condition_id` — same as above?
4. If any emits plural, document it in the schema. If all emit singular, confirm it.

### Flutter-side (Sprint 27.7)

Parse both shapes on all warning entries. Merge singular + plural into `Set<String>` → `matchesProfile()` does any-match. Permanent defense — no impact if pipeline is already consistent.

---

## Minor — HANDOFF_2026-04-21.md smoke-test has wrong product name

Your HANDOFF doc lists DSLD `16037` as "Thorne Silybin Phytosome". Actual row in the bundled catalog:

```
DSLD 16037 | Thorne Research | Planti-Oxidants | 52.1/80 (65/100)
```

No product named `Silybin` exists in the catalog. Score (52.1/80) matches the expected ~52/80 — the expected score is right, the product name is wrong. User hit this during smoke testing and thought the DB was missing products.

**Ask:** fix the smoke-test table in the next HANDOFF doc. Recommend using product name lookup rather than hard-coding DSLD IDs, since names are stable but numeric IDs are meaningless to readers.

---

## Summary: what ships together, what ships separately

### Pipeline PR 1 — Critical safety (recommended this week)

1. Defect #1: `decision_highlights` re-classification + new `danger` bucket + build-time validator
2. Defect #2: `warnings_profile_gated` re-classification (Path A or B) + build-time validator
3. Defect #5: warning-copy fallback validator
4. Minor HANDOFF doc fix

### Pipeline PR 2 — Authored safety fields (coordinate with Sprint 27.6 Path C)

5. Defect #4: `banned_substance_preflight_one_liner` + `_body` fields, safety-team authoring pass
6. Defect #3: build-time dedup
7. Defect #7: tag-field-shape audit + doc

### Pipeline PR 3 — Scorer enhancement (V1.1 timeline OK)

8. Defect #6: `A8_enzyme_potency` micro-metric

---

## Flutter-side work running in parallel (not blocking this handoff)

**Sprint 27.7 ships:**
- Defensive filters for #1, #2, #3, #5, #7 (permanent defense-in-depth, stay in place after pipeline fixes)
- UI guardrail for #4 (wires to pipeline fields once #4 ships)
- Placeholder for #6 (no pipeline dependency)
- Sprint 27.6 Path A (drop `warning_message`)

Flutter Sprint 27.7 lands within ~4 days regardless of pipeline timeline. Pipeline PRs unblock removal of the upstream-fixes-done half of the defensive layer; the defense-in-depth stays permanent.

---

## Questions?

Flutter repo: `/Users/seancheick/PharmaGuide ai` — see [`SPRINT_TRACKER.md`](SPRINT_TRACKER.md) Sprint 27.7 section for the parallel work.

For the safety-team authoring process on #4, reference Sprint 27.6 Path C in the Flutter tracker — same authoring template (`safety_warning_one_liner` / `safety_warning` / per-entry sign-off checklist) applies here.

All device testing reproducible with catalog `v2026.04.21.164306` on commit `6e6a692` in Flutter main.

Good luck upstream!
