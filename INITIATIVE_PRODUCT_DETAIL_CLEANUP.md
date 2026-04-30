# INITIATIVE: Product Detail Page Cleanup

**Status:** Active — Sprint S2 entry  
**Started:** 2026-04-29  
**Owner:** Sean  
**Predecessor:** `INITIATIVE_PRODUCT_TRUST_AND_IA.md` (Sprint 1 closed-out, T1.16 verified 2026-04-29)

---

## Why

After Sprint 1 (Trust & IA) shipped, the product detail page works — but reads bloated and repetitive. Walkthrough audit on 2026-04-29 surfaced:

1. **Three lanes interleaved instead of stacked.** "Trust receipt" (score, evidence, certifications), "personal fit" (For You, your stack, populations), and "formulation reference" (ingredients, doses, nutrition) appear in 2–3 places each with slightly different framing. Same data, different voices → user confusion.
2. **False-positive condition flags** firing for safe products at safe doses (Vit D triggering TTC + diabetes "monitor" at 1000 IU). Threshold gating absent across the rule engine.
3. **Score ring + log-dose button + battery estimate** consume hero real-estate without commensurate value.
4. **"Pair Well With Your Stack" + "Deep Dive"** restate content already shown above.

This initiative collapses the page to a single coherent IA, hardens the rule engine against false positives, and removes ~6 redundant sections. Mirrors the `INITIATIVE_PRODUCT_TRUST_AND_IA.md` audit-gate cadence — pause-and-verify between every task.

---

## Locked Design Contract

### Page structure (top-to-bottom)

| # | Section | Content | Conditional |
|---|---------|---------|-------------|
| 1 | **Header** | Image (tappable) · title · brand · count · serving · chip row · score line · description | Always |
| 2 | **Personal Fit** | Headline + max 2 causal bullets + edit-profile pencil | Always |
| 3 | **Alert Summary** | Count + chevron, scrolls to §7 | Only when ≥1 real alert |
| 4 | **Product Analysis** | 4 pillar bars (normalized 0–100) + micro-explanations + tap → detail | Always |
| 5 | **Tradeoffs** | What's good / What to consider, max 4 bullets each | Always |
| 6 | **Ingredients** | Active (all shown) + Inactive (chips + expander with color dots) | Always |
| 7 | **Interactions** | Real, threshold-gated, calm tone — full detail | Conditional |
| 8 | **Synergy Cluster** | Max 3 items, high-confidence only | Conditional |
| 9 | **Evidence & Research** | Studies count + tier + view-citations sheet | Always |
| 10 | **Footer** | Updated · Sources · Disclaimer (no italic) | Always |

### Score tiers (locked)

| Score | Label | Dot | Description (under score) |
|-------|-------|-----|---------------------------|
| 90–100 | Exceptional | Deep Green | High-quality ingredients, strong evidence, no major safety concerns |
| 80–89 | Excellent | Green | Well-formulated with good ingredient quality, solid evidence, clean safety profile |
| 70–79 | Good | Teal | Reliable option with acceptable ingredients and no major red flags |
| 60–69 | Fair | Yellow | Adequate formulation with some limitations in quality, evidence, or transparency |
| 50–59 | Low Quality | Orange | Notable concerns — weaker ingredients, limited evidence, or avoidable additives |
| 0–49 | Poor | Red | Significant concerns around formulation quality, safety, or transparency |

### Pillar micro-explanations (locked)

| Pillar | Micro-explanation |
|--------|-------------------|
| Ingredient Quality | Form, dosage, and bioavailability |
| Safety & Purity | Free from harmful ingredients and contaminants |
| Evidence & Research | Clinical support behind ingredients |
| Transparency & Verification | Label clarity and independent testing |

### Inactive ingredient color rubric

- 🟢 **Green** — Standard manufacturing component (whitelisted excipient)
- 🟡 **Yellow** — Acceptable but worth noting (e.g., processing aids beyond minimum)
- 🟠 **Orange** — Watchlist / source concern (e.g., palm oil)
- 🔴 **Red** — Penalty ingredient (e.g., artificial sweeteners, dyes, undeclared blends)

### Critical logic rules (NON-UI, enforced in code)

1. **NOT_SCORED products NEVER render** — partial-data products bail before the screen builds
2. **No placeholder scoring** — never display fabricated numbers as a fallback
3. **Fit ≠ Quality** — separated visually and in code (two distinct widgets, two distinct providers)
4. **No raw ingredient strings** — every ingredient row maps through canonical ID
5. **Show ALL relevant alerts (no cap)** — interactions section never truncates real, profile-relevant alerts
6. **No alarmist language** — banned: "DO NOT TAKE", "AVOID", "DANGEROUS", "harmful additive [name]"

### Killed sections (final)

- Score ring (replaced by text-based score)
- Log Dose button (lives on stack screen only)
- Pair Well With Your Stack v1 (replaced by tightened Synergy Cluster)
- 60-day battery estimate (not implemented)
- Full Nutrition Facts panel (collapsed to link → sheet)
- Bottom redundant Product Details block (merged into header)
- Standalone "How this product fits you" section (folded into Personal Fit card)
- "Harmful additive [name]" prefix repetition

---

## Sprint S2.1 — Bugs

Independent, parallel-safe, ship first. None of these depend on IA work in S2.2.

### T1 — Image tap → fullscreen modal — `verified-2026-04-29`

**Goal:** User can tap product image to view full-size with pinch-zoom.

**DoD:**
- Image wrapped in `GestureDetector` with `onTap` ✅
- Hero-animated fullscreen viewer (`InteractiveViewer` for pinch-zoom) ✅
- Close affordance (X top-right, swipe-down dismiss via Navigator.maybePop) ✅
- Placeholder taps deliberately inert — only real image URLs are tappable ✅

**Files touched:**
- `lib/core/widgets/product_image.dart` — added optional `onTap(String imageUrl)` callback
- `lib/features/product_detail/widgets/product_image_viewer.dart` — new fullscreen viewer with InteractiveViewer (minScale 1.0, maxScale 4.0), reuses `product-$dsldId` Hero tag for lift
- `lib/features/product_detail/product_detail_screen.dart` — wires `onTap` on the inner ProductImage
- `test/features/product_detail/widgets/product_image_viewer_test.dart` — 3 widget tests (renders InteractiveViewer + close, close pops route, show() pushes route)

**Verification:**
- `flutter analyze --fatal-infos` on 4 affected files → **No issues found**
- `flutter test test/features/product_detail/widgets/product_image_viewer_test.dart` → **3/3 pass**
- `flutter test test/features/product_detail/` → **475/475 pass** (no upstream regressions)
- Manual TestFlight check pending — defer to T23 walkthrough

---

### T2 — Edit profile button crash (P0) — `verified-2026-04-29`

**Goal:** Edit-profile pencil from product page no longer crashes / no-ops.

**Root cause (one line):** `for_you_section.dart:_openProfile` was pushing `Routes.profile` (`/profile`) — the **SettingsScreen shell-tab path inside the bottom-nav `StatefulShellRoute`**, not `Routes.profileSetup` (`/profile/setup` → `ProfileSetupScreen`). Pushing a shell-route tab path from a non-shell screen via `context.push` no-ops or throws depending on the GoRouter version. Every other edit-profile call site in the app (`settings_screen:84`, `home_profile_completeness_card:21`, `fit_score_sheet:123`, `stack_screen:863`, `product_detail_screen:1367`) correctly used `Routes.profileSetup` — `for_you_section` was the lone outlier. Likely typo at the time the constants were added.

**DoD:**
- Repro confirmed via grep audit of all `Routes.profile*` call sites ✅
- Root cause identified ✅
- Fix: 1-line constant swap `Routes.profile` → `Routes.profileSetup` ✅
- Regression test pumps both code paths (empty-profile CTA + loaded-profile Edit chip) and verifies navigation lands on `ProfileSetupScreen`, not `SettingsScreen` ✅

**Files touched:**
- `lib/features/product_detail/widgets/for_you_section.dart:_openProfile` — single-line fix with inline comment explaining the regression
- `test/features/product_detail/widgets/for_you_section_navigation_test.dart` — new, 2 widget tests (empty CTA + loaded chip), both register `/profile` AND `/profile/setup` sentinels so a re-introduction of the bug fails loudly with the wrong sentinel rather than throwing an opaque GoRouter error

**Verification:**
- `flutter analyze --fatal-infos` on 2 files → **No issues found**
- New navigation tests → **2/2 pass**
- `flutter test test/features/product_detail/` → **477/477 pass** (+2 from baseline 475)
- Manual TestFlight check pending → defer to T23 walkthrough

---

### T3 — Threshold gating data table — `verified-2026-04-29`

**Goal:** Curated table of `(condition, nutrient)` → directionality + minDose for the warning generator to consume.

**Design:**
- `enum NutrientDirectionality { positive, neutral }` — positive = beneficial nutrient for the condition (suppress always); neutral = threshold-gated.
- `class ConditionThreshold` with two named constructors: `.positive(rationale)` and `.aboveDose(minDose, doseUnit, rationale)`.
- Nested const map `Map<String, Map<String, ConditionThreshold>>` keyed by `[conditionId][canonicalIngredientId]` (lowercase + underscore form).
- Public `lookupConditionThreshold({conditionId, ingredientName})` helper canonicalizes the raw pipeline name and returns `ConditionThreshold?`. Null = no entry → caller falls through to existing behavior. **Purely additive** — never destructive — so the table can grow incrementally without risk.
- Each entry carries a 1-line `rationale` (PMID / NIH ODS / ACOG / ASA pointer) so future auditors can verify thresholds without spelunking the original PR.

**Coverage (V1 — 11 conditions, ~50 entries):**
- TTC + pregnancy + lactation: vitamin D / B12 / folate / iron / calcium / choline → **positive**; vitamin A / retinol → 3000 IU teratogenic threshold; caffeine → 200 mg
- Diabetes: vitamin D / magnesium / chromium → **positive**; niacin → 500 mg threshold
- Hypertension: magnesium → **positive**; caffeine, licorice → thresholds
- Kidney disease: magnesium 400 mg / potassium 250 mg / vitamin D 4000 IU / zinc 40 mg (the one place vit D is NOT positive — high doses drive Ca/P concerns in CKD)
- Bleeding disorders: omega-3 / fish oil / vitamin E / ginkgo / garlic / curcumin — clinically established thresholds with PMIDs
- Surgery scheduled: same anticoagulant supplements with ASA pre-op guidance
- Thyroid disorder: iodine 150 mcg threshold; selenium → positive
- Seizure disorder: vitamin B6 100 mg threshold (anticonvulsant interaction)
- High cholesterol: omega-3, niacin → **positive**

**Conditions intentionally absent for V1:** heart_disease, liver_disease, autoimmune — pairs are too case-by-case to encode without specialist input. Backlog **B6** in the initiative tracks expansion.

**Files touched:**
- `lib/services/warnings/condition_thresholds.dart` (new, ~340 lines: 90 lines docs + types, 240 lines data table with rationale comments, 10 lines lookup helper)
- `test/services/warnings/condition_thresholds_test.dart` (new, 22 tests)

**Verification:**
- `flutter analyze --fatal-infos` on 2 files → **No issues found**
- Threshold tests → **22/22 pass** (covers headline false-positive fixes — Vit D + TTC, Vit D + diabetes, magnesium + diabetes — plus retinol teratogenic gate, bleeding-disorder dose gates, kidney mineral overload gates, canonicalization, passthrough fallback)
- Clinical sanity: each entry carries a 1-line rationale citing PMID / NIH ODS / ACOG / ASA / KDIGO / KDOQI / WHO / AHA / ASRM as applicable. Sean's call on whether to commission a clinician review pass before T4 wires it into the warning generator.

**T4 contract handoff:** T4 consumes `lookupConditionThreshold(...)` and applies the gating decision when filtering warnings. Decision logic (positive → suppress; neutral + dose < minDose → suppress; null → fire-as-today) lives in T4, not here. T3 provides data only.

**Post-T4 live walkthrough finding (2026-04-29 PM):** simulator test of the Vit D × Diabetes case showed the false-positive warning STILL surfaced in two surfaces that bypassed the warnings-list gate:
1. `_ConditionAlertBanner` (the "Use with caution — relevant to your profile" banner) — read directly from `interaction_summary_hint`
2. `_InteractionConditionDetails` (the "Diabetes — MONITOR / Affected by: Vitamin D" card) — read directly from `interaction_summary.condition_summary`

Both were fixed via a new `gateInteractionSummary(...)` helper in `condition_gate.dart` that filters per-condition ingredient lists and drops conditions whose only triggering ingredients were positive-directional. See T4 close-out for full details.

**Path A extension (mid-T3, 2026-04-29):** Sean's design call — don't just *suppress* false positives, also *credit* the product when an ingredient is beneficial for the user's profile. Implemented the symmetric helper alongside the threshold table:

- `generatePositiveProfileBullets({ingredientNames, userConditionIds})` — emits "[Ingredient] supports your [phrase]" / "[Ingredient] is recommended during [phrase]" bullets, condition-major order, max one bullet per condition (so multi-form mag products don't burn the card's 2-bullet budget on one nutrient).
- Two phrase templates by condition type:
  - **Medical states** (pregnancy / lactation / TTC) → `"is recommended during X"` (clinically accurate framing for medical states the user didn't *choose*)
  - **Managed conditions** (diabetes / hypertension / thyroid_disorder / high_cholesterol) → `"supports your X goal/health"` (goal-driven framing matches user mental model)
- Locked phrase map covers 7 conditions — exactly the conditions that have ≥1 `positive` entry today. Future `positive` entries to other conditions silently no-op until a phrase is added (forward-compat).
- 13 additional tests cover: empty inputs, single positive, multiple conditions, condition reordering, duplicate ingredient forms (dedup), neutral entries (suppressed), missing phrase (skipped), canonical aliases, multi-word display, mixed positive/neutral products.

**T12 consumer contract (locked here):** Personal Fit card MUST call `generatePositiveProfileBullets(...)` and prefer those bullets over generic copy when present, capped at the card's 2-bullet limit. See T12 DoD addendum.

---

### T4 — Apply threshold gating in warning generator — `verified-2026-04-29`

**Goal:** Warning filter consults the threshold table; suppresses any warning where dose is below threshold or nutrient is positive-directional.

**Design:**
- Pure helper file `lib/services/warnings/condition_gate.dart`:
  - `IngredientDose` typedef (`{double value, String unit}`)
  - `extractIngredientDoses(detailBlob)` → `Map<canonical, IngredientDose>` from blob's `ingredients` list (handles nulls, string-typed dose_amount, missing fields)
  - `applyConditionThresholdGate({warnings, ingredientDoses})` — filter that drops fully-gated warnings
- **Multi-condition semantics:** suppress only when EVERY tagged condition is gated; if any condition fires (no entry / above threshold / missing dose / unit mismatch), keep the warning. Medical-grade conservative.
- **Fail-safe defaults:** missing dose / unit mismatch / unknown rule / missing ingredient → keep. Suppression requires positive evidence in the table — opt-in, never opt-out.
- **Public canonicalization:** renamed private `_canonicalize` → public `canonicalizeIngredientName` in `condition_thresholds.dart` so the gate (and any future consumers) share one canonical-key function.

**Wiring:**
- Gate baked INTO `filterProductDetailWarningsForProfile` in `product_detail_screen.dart` (right after UL warning synthesis, before the existing profile-visibility filter). Both screen call sites pick it up automatically — no caller-side changes needed.
- UL warnings (no `conditionIds`) pass through unchanged — the gate only operates on condition-tagged warnings.

**DoD:**
- Generator reads `condition_thresholds.dart` ✅
- Skip rule firing when `dose < min_dose` ✅
- Skip rule firing when `directionality == positive` ✅
- Test cases:
  - ✅ Vit D 1000 IU + TTC → suppressed (positive)
  - ✅ Vit D 5000 IU + TTC → suppressed (positive ignores dose)
  - ✅ Magnesium 200 mg + diabetes → suppressed (positive)
  - ✅ Magnesium 600 mg + diabetes → suppressed (positive ignores dose; UL handled by separate path)
  - ✅ Vit A 2000 IU + pregnancy → suppressed (below 3000 IU)
  - ✅ Vit A 4000 IU + pregnancy → kept (above threshold)
  - ✅ Vit A exactly 3000 IU + pregnancy → kept (boundary fires)
  - ✅ Magnesium 200 mg + kidney_disease → suppressed (below 400 mg)
  - ✅ Magnesium 600 mg + kidney_disease → kept (above threshold)
  - ✅ Vit D 1000 IU + kidney_disease → suppressed (below CKD 4000 IU threshold)
  - ✅ Vit D 5000 IU + kidney_disease → kept (above CKD threshold)
  - ✅ Multi-condition (TTC + pregnancy, both positive for Vit D) → suppressed
  - ✅ Multi-condition (TTC positive, kidney_disease above threshold) → kept (any-fires-keeps)
  - ✅ Multi-condition with no entry for one condition → kept (table is opt-in)
  - ✅ Empty conditionIds → kept (passthrough)
  - ✅ Missing ingredientName → kept (passthrough)
  - ✅ Unknown ingredient → kept (passthrough)
  - ✅ Missing dose → kept (fail-safe)
  - ✅ Unit mismatch → kept (fail-safe)
  - ✅ Order preserved across kept warnings

**Files touched:**
- `lib/services/warnings/condition_thresholds.dart` — `_canonicalize` → public `canonicalizeIngredientName`
- `lib/services/warnings/condition_gate.dart` — new (~150 lines)
- `lib/features/product_detail/product_detail_screen.dart` — import + 8 lines wiring inside `filterProductDetailWarningsForProfile`
- `test/services/warnings/condition_gate_test.dart` — new, 29 tests covering all the above scenarios

**Verification:**
- `flutter analyze --fatal-infos` (full repo) → **No issues found**
- Gate tests → **29/29 pass** (initial); **38/38 pass** (after live-walkthrough follow-up)
- Full warnings suite → **64/64 pass** initial → **73/73 pass** post-follow-up (44 thresholds + 38 gate)
- Full product-detail + warnings suite → **552/552 pass** post-follow-up
- Manual: pending T23 walkthrough

---

**T4 Post-deploy live walkthrough (2026-04-29 PM, in iOS 17 Pro Simulator):**

When Sean ran the app and inspected a Thorne Vitamin D product with a TTC + Diabetes profile, the **headline false-positive monitor warning Sean had originally reported** was STILL rendering — despite T4's warnings-list gate passing all unit tests. Root cause: the pipeline emits `interaction_summary` as a **separate** blob field with two surfaces that bypass the warnings-list path entirely:

1. **`_ConditionAlertBanner`** — the "Use with caution — relevant to your profile" banner reads `interaction_summary_hint` (an aggregated hint string with `condition_ids` + `highest_severity`) and renders the headline banner regardless of whether T4 would have suppressed the underlying warnings.
2. **`_InteractionConditionDetails`** — the "Diabetes — MONITOR / Affected by: Vitamin D" card reads `interaction_summary.condition_summary` directly and renders one card per condition with the verbatim ingredient list from the pipeline.

**Fix — `gateInteractionSummary(...)` helper in `condition_gate.dart`:**
- Pure function, takes `interaction_summary` map, returns a NEW map (never mutates input).
- For each condition in `condition_summary`, filters the `ingredients` list by removing names that are `positive` for that condition (per T3 table).
- Drops the condition entry entirely when no ingredients survive (the only reason it surfaced was the positives we just suppressed).
- Leaves `drug_class_summary` untouched — drug classes don't have positive-directional nutrient mappings.
- **Limitation:** the `condition_summary` shape carries names but NOT doses, so this surface only does positive-directionality filtering. T4's main warnings-list gate still handles dose-threshold filtering; pipeline could enrich `condition_summary.ingredients` with doses to enable threshold gating here too (backlog item).

**Wiring:**
- `_InteractionConditionDetails` call site at line 2472 — passes `gateInteractionSummary(interactionSummary) ?? interactionSummary` instead of raw summary. Widget already self-hides on empty input, so unconditional pass-through works.
- `_ConditionAlertBanner` — added optional `interactionSummary` param; in `build()`, gates the summary and intersects `parsed.conditionIds` with surviving keys. If everything gets gated AND there are no drug-class warnings → banner hides.
- Banner call site — passes `detailBlob?['interaction_summary']` so the gate has the data.

**Live walkthrough verification:**
- **Pre-fix screenshot:** "Use with caution — relevant to your profile / Your conditions: Diabetes" banner + "🟠 Diabetes — MONITOR / Affected by: Vitamin D / Monitor glucose and adjust diabetes therapy if needed" card
- **Post-fix screenshot:** Banner GONE. Card renders as "✓ Diabetes / No known interaction" — graceful empty state via the existing widget logic
- **Edit profile button (T2):** Opens `ProfileSetupScreen` "Step 1 of 5: Basic info" cleanly. No crash. Verified.
- **Log Dose button (T8):** Confirmed absent on the product page. Only "+ Add to my stack" rendered.

**Files touched (follow-up):**
- `lib/services/warnings/condition_gate.dart` — added `gateInteractionSummary(...)` (~80 lines)
- `lib/features/product_detail/product_detail_screen.dart` — wired gate at `_InteractionConditionDetails` call site + extended `_ConditionAlertBanner` to accept and gate `interactionSummary`
- `test/services/warnings/condition_gate_test.dart` — added 9 tests covering: null input, no condition_summary key, drop condition with all-positive ingredients, partial filter (positive dropped, neutral kept), multi-condition wholesale drop, drug_class_summary preservation, unknown ingredient passthrough, malformed-data passthrough, immutability

**Re-verification:**
- `flutter analyze --fatal-infos` (full repo) → **No issues found**
- Gate tests → **38/38 pass** (29 initial + 9 follow-up)
- Full product-detail + warnings suite → **552/552 pass**
- Live simulator walk on the same Thorne Vit D product → headline false positive **GONE**

---

### T5 — Citation bottom sheet width fix — `verified-2026-04-29`

**Goal:** Citation sheet renders at proper modal width on all device sizes.

**Root cause (real bug, not just polish):** the sheet *itself* was fine — the **content** was rendering as a "Citations" header above a stack of `SizedBox.shrink()` groups. When the pipeline ships `clinical_matches` rows with empty `pmids` (the "Limited evidence + 0 studies" case Sean reported), `_CitationGroup` line 450 returned `SizedBox.shrink()` → 0×0 → user sees a tiny header-only sheet → "narrow / crashed."

**Three fixes:**

1. **`PGModal.bottomSheet`** — added optional `constraints` parameter, default `BoxConstraints(maxWidth: 560)`. Material 3 modal-sheet spec — phones ≤560pt span full width, tablets cap at 560pt centered. Applies to ALL 15 sheet call sites in the app, not just citations. Override via explicit `constraints` argument when a caller needs more (e.g., a future settings sheet wanting 720pt).
2. **`_showAllCitations`** — pre-filters `matches` to those with non-empty `pmids` before render. If filtered list is empty → render proper empty-state ("No citations available for this product.") with vertical padding so the sheet has visual weight. Wraps content in `SizedBox(width: double.infinity)` so the Column fills the constrained width on all layouts.
3. **`_showCitationsForMatch`** — same `SizedBox(width: double.infinity)` wrapping for consistency with `_showAllCitations` (single-PMID sheets render at the same width on tablets).
4. **`_CitationGroup`** — defensive empty-pmids fallback now renders `'No citations available for [ingredient].'` instead of `SizedBox.shrink()`. Belt-and-suspenders: parents (#2) filter out the empty case before calling, but if a future caller path slips through, the sheet still renders meaningful content.

**Files touched:**
- `lib/core/widgets/pg_modal.dart` — `constraints` param + 560pt default
- `lib/features/product_detail/widgets/pipeline_sections/evidence_detail_section.dart` — empty-state filter, width sizing on both `_showAllCitations` + `_showCitationsForMatch`, `_CitationGroup` empty fallback

**Verification:**
- `flutter analyze --fatal-infos` on 2 files → **No issues found**
- `flutter test test/features/product_detail/` → **477/477 pass** (no regressions in existing widget tests)
- Manual TestFlight verification of phone + tablet rendering deferred to T23 walkthrough — the 560pt cap is industry-standard Material 3 behavior so the risk is low

---

### T6 — Stress-resilient text truncation — `verified-2026-04-29`

**Goal:** Cluster labels (e.g., "Stress-resilient") never cut off mid-word.

**Investigation:** Two cluster widgets exist on the product detail page:
- `pairs_well_section.dart` — slated for **deletion** in T17 (skipped)
- `synergy_detail_section.dart` — slated for **rebuild** in T22 (fix is portable)

The cluster *name* is in `Expanded(child: Text(...))` with no `maxLines` — soft-wraps fine, no truncation. The actual user-perceived cut-off is the per-cluster *explanation* text below the name (`maxLines: 3, overflow: ellipsis`). Mechanism descriptions can run paragraph-length and the ellipsis swallows the tail.

**Fix (DoD option B — make tappable → sheet):**
- Wrap each cluster row in `synergy_detail_section.dart` in `PGPressable(onTap: ...)`
- New `_showClusterDetail(...)` method on `SynergyDetailSection` opens a `PGModal.bottomSheet` with the full untruncated content: cluster name (titleLarge, no truncation) · evidence tier badge · single-ingredient-match note (when applicable) · full explanation (no `maxLines`) · published-studies count
- Inline 3-line ellipsis stays as the row summary so the visual rhythm of the section is unchanged — tap reveals the rest
- Reuses T5's PGModal.bottomSheet (already constraints-fixed at 560pt for iPad)

**Files touched:**
- `lib/features/product_detail/widgets/pipeline_sections/synergy_detail_section.dart` — added `PGModal` + `PGPressable` imports; wrapped cluster Container in `PGPressable`; new `_showClusterDetail()` method
- `test/features/product_detail/widgets/pipeline_sections/synergy_detail_section_test.dart` — NEW, 3 widget tests (inline rendering, tap-to-sheet opens with full text, tier badge in sheet header)

**Verification:**
- `flutter analyze --fatal-infos` on 2 files → **No issues found**
- Synergy section tests → **3/3 pass**
- Full product-detail suite → **482/482 pass** (+3 from baseline 479)
- Manual iPhone SE viewport check pending T23 walkthrough — the inline summary still ellipsises at 3 lines, but tap now always exposes the full text so 25-char labels are guaranteed readable

---

### T7 — Evidence "0 studies clinically supported" contradiction — `verified-2026-04-29`

**Goal:** Evidence card never claims "clinically supported" when studies count is 0.

**Root cause:** Pre-fix `_TierBlock` rendered:
- Header: "Clinical support: LIMITED"
- Subline: "0 studies reviewed"

The header *implies* clinical evidence exists; the subline says it doesn't. Self-contradicting. T5's empty-citation-sheet fix amplified the broken impression — user saw the contradiction, tapped, got an empty sheet, perceived the whole flow as crashed.

**Fix:** When `totalStudies == 0`, swap the dual-line tier banner for a new `_ZeroStudiesBanner` widget that renders a single honest line — "Limited evidence available" — with the same outline / muted-tint chrome so the section's visual rhythm doesn't break. Per-ingredient match rows below are untouched (the pipeline DOES claim a clinical match exists; we just don't lie about study count).

The tier function itself was already correct — `studies < 3 → limited` — so no logic change needed. The bug was purely in the rendering. Locked the existing tier behavior with an explicit "0 studies + meta=true → LIMITED (not STRONG)" test so a naive future "if (meta) return strong" can't regress it.

**Files touched:**
- `lib/features/product_detail/widgets/pipeline_sections/evidence_detail_section.dart` — early-return in `_TierBlock.build()` to `_ZeroStudiesBanner` when `totalStudies == 0`; new `_ZeroStudiesBanner` widget (~40 lines)
- `test/features/product_detail/widgets/pipeline_sections/evidence_detail_section_test.dart` — 1 unit test (0 studies + meta-quality match → LIMITED) + 1 widget test (banner renders honest copy + contradiction strings absent)

**Verification:**
- `flutter analyze --fatal-infos` on 2 files → **No issues found**
- Evidence section tests → **28/28 pass** (26 baseline + 2 new)
- Full product-detail suite → **479/479 pass** (+2 from baseline 477)
- Manual: pending T23 walkthrough on a product where pipeline claims a clinical match but ships empty PMIDs

---

### T8 — Remove Log Dose button from product page — `verified-2026-04-29`

**Goal:** Log-dose CTA removed from product detail; future log-dose flow lives on stack screen only.

**Investigation:** Pre-T8, the Log Dose button only existed in `PGStackActionButtons` (a placeholder secondary button with a "Coming soon" snackbar — see prior T1.15 close-out). The stack screen had no log-dose flow at all yet — the DoD assumption "Stack screen still has the button" was forward-looking. T8 simply strips the placeholder; whoever ships dose-logging next builds on the stack screen.

**Fix (pure deletion):**
- `pg_stack_action_buttons.dart`:
  - Removed `onLogDose` field + constructor param
  - Removed `_logDoseButton` helper method
  - Removed the secondary `entryAsync.when(...)` block that rendered the disabled-by-default Log Dose
  - Collapsed the action bar to a single primary — no Column/SizedBox wrapper needed anymore
  - Updated class doc to explain the move
- `product_detail_screen.dart`:
  - Removed `onLogDose: _handleLogDose` from the `PGStackActionButtons` call site
  - Removed the `_handleLogDose` method (was a placeholder snackbar)
- `pg_stack_action_buttons_test.dart`:
  - 3 retained tests had their `expect(find.text('Log dose'), findsOneWidget)` flipped to `findsNothing` — locks the contract that Log Dose is NOT rendered on the product page
  - 3 dedicated tests deleted (disabled-not-in-stack, enabled-in-stack, disabled-unsafe — all of those exercised the removed conditional path)
  - `_wrap` helper's `onLogDose` param removed

**Files touched:**
- `lib/features/product_detail/widgets/pg_stack_action_buttons.dart` — net ~30 lines removed
- `lib/features/product_detail/product_detail_screen.dart` — 1 line + 14-line method removed (replaced with comment marker)
- `test/features/product_detail/widgets/pg_stack_action_buttons_test.dart` — 3 tests deleted, 3 tests' assertions inverted, helper updated

**Verification:**
- `flutter analyze --fatal-infos` (full repo) → **No issues found**
- Full product-detail suite → **479/479 pass** (482 → 479 after removing 3 dedicated log-dose tests; the inverted assertions in the 3 retained tests now lock "Log Dose is NOT rendered")
- Manual TestFlight verification deferred to T23

---

**Sprint S2.1 Exit Criteria:**
- All 8 tasks closed with verification stamps
- `flutter analyze --fatal-infos` → No issues
- `flutter test` → all passing
- Manual: 5-product walkthrough confirms no false-positive condition flags on safe doses

---

## Sprint S2.2 — IA collapse

Sequential. Each task depends on the previous building cleanly. Audit gate after each.

### T9 — `ScoreTier` enum + tier mapping — `verified-2026-04-29`

**Goal:** Public `ScoreTier` enum with per-tier color + label + description, plus `tierForScore(int score)` pure helper.

**Design:**
- `enum ScoreTier { exceptional, excellent, good, fair, lowQuality, poor }`
- `extension ScoreTierMeta` provides `label`, `description`, `color` — keeps the tier table self-contained
- `tierForScore(int)` pure function with inclusive-at-the-floor semantics. 90 → Exceptional, 89 → Excellent. Out-of-range inputs clamp gracefully (≥100 → Exceptional, <0 → Poor) — defensive against rounding overflows / uninitialized scores
- Tier colors defined inline rather than threaded through `AppTheme` — keeps the V1 module self-contained. `AppTheme.scoreGood` is a lime-green (#65A30D); the new `ScoreTier.good` is teal (#0EA5A0) per the locked spec, so a new constant was needed regardless
- Locked color palette: deep green / green / teal / yellow / orange / red

**Files touched:**
- `lib/core/scoring/score_tier.dart` — new (~110 lines, mostly switch expressions for the 6 tiers)
- `test/core/scoring/score_tier_test.dart` — new, 17 tests

**Verification:**
- `flutter analyze --fatal-infos` on 2 files → **No issues found**
- Tier tests → **17/17 pass**: 8 boundary/range tests (49/50, 59/60, 69/70, 79/80, 89/90, 0/100 ends, out-of-range clamping, mid-range sanity) + 9 metadata invariants (every tier non-empty label/description, no trailing period, all labels/descriptions/colors distinct, locked label copy matches spec, locked description key phrases, hue ordering — green tiers green-dominant, red tiers red-dominant)
- No widget refs yet — pure model, ready for T10 to consume

---

### T10 — Replace score ring with text-based score widget — `verified-2026-04-29`

**Goal:** Compact `ScoreLine` widget renders `● 90/100 Exceptional` + description on next line.

**Design:**
- `ScoreLine({required int score, String? descriptionOverride})` — pure stateless, no provider deps
- Renders Column with two children:
  - Row: tier dot (10pt circle, tier color) · score numeric (`92/100`, titleMedium w800) · tier label (titleMedium w700, tier color)
  - Description below (bodySmall, onSurfaceVariant, soft-wraps, no maxLines/ellipsis)
- Score numeric and tier label are SEPARATE Text widgets (not Text.rich) so `find.text('Exceptional')` matches in widget tests
- Out-of-range inputs: tier clamps via `tierForScore`, but the displayed numeric keeps the raw value (a `105/100` UI is a clear data-quality signal worth surfacing rather than silently hiding)
- `descriptionOverride` escape hatch lets a future sprint replace the per-tier description with a per-product blurb without re-architecting the widget. Defaults to the locked `tier.description` copy.

**Files touched:**
- `lib/features/product_detail/widgets/score_line.dart` — new (~85 lines)
- `test/features/product_detail/widgets/score_line_test.dart` — new, 12 tests

**Verification:**
- `flutter analyze --fatal-infos` on 2 files → **No issues found**
- ScoreLine tests → **12/12 pass**: 6 tier rendering tests (one per tier band — Exceptional/Excellent/Good/Fair/Low Quality/Poor), 4 boundary tests (0/100 ends + out-of-range high/low), 1 dot-color structural test, 1 descriptionOverride test
- Old `ScoreRingWidget` usage NOT yet removed — that lands in T11 when the header card swaps in `ScoreLine`. Per the DoD: "Old ring widget kept in source until T11 lands, then deleted." V2 of the action plan is on track.

---

### T11 — Header card rebuild — `verified-2026-04-29`

**Goal:** Single header card matching contract: image · title · brand·count·serving · chip row · score line · description.

**Design:**
- Identity row: 96pt image (tappable from T1) + Expanded column with title (titleLarge w800) and dot-separated subtitle
- Subtitle now carries 3 segments instead of 2: **Brand · Net contents · Dosing summary** (e.g., "Thorne · 60 Capsules · 1 capsule daily"). Drops segments cleanly when missing — orphan dots removed by `_buildHeroSubtitleSpan` helper.
- Chip row moved ABOVE the score (was below in pre-T11). Reads top-to-bottom: identity → certifications → score.
- Score altar replaced by [`ScoreLine`](T10) — `● 65/100 Fair` + tier description.
- Verdict banner stays at the bottom of the hero card; renders only for Blocked/Avoid.
- `isNotScored` path replaces the score line with a small "Not enough verified data to score." line, no banner.

**Carryovers untouched:**
- Hero animation (TweenAnimationBuilder fade + translate)
- Hero tag for image flight (carousel→detail→fullscreen)
- Verdict banner copy/tone

**Removals:**
- `_ScoreRingButton` private widget — deleted (only consumer was this hero)
- `_glowColor` helper — deleted (was the score-ring's drop-shadow hue)
- `_showScoreEducation` method + `_ScoreEducationSheet` widget — deleted (the tap-to-explain flow no longer fires; ~260 lines of dead code removed)
- `pg_score_ring.dart`, `pg_pressable.dart`, `pg_modal.dart` imports — pruned (no remaining usages in this file; `PGScoreRing` is still used by `product_list_item.dart` for the small 52pt list-row ring)

**New params on `_HeaderSection`:**
- `dosingSummary: String?` — from `_product.dosingSummary`
- `netContentsQuantity: double?`, `netContentsUnit: String?` — combined via existing `formatNetContents` helper

**Test updates:**
- Removed test "score education sheet describes the core product score accurately" (asserted the deleted tap-to-explain flow + verbose pillar table)
- Updated test "T1.1 hero does NOT render the inline 'Why this score' reasoning row" to assert `find.byType(ScoreLine)` + `find.text('PG SCORE') == nothing` instead of the old "PG SCORE altar present" assertion
- Cleaned up file-level `setUp()` — `coreDb` + `userDb` were only consumed by the removed test

**Files touched:**
- `lib/features/product_detail/product_detail_screen.dart` — `_HeaderSection` rebuilt, ~260 lines of dead code removed
- `test/features/product_detail/product_detail_screen_test.dart` — 1 test removed, 1 test updated, setUp pruned

**Verification:**
- `flutter analyze --fatal-infos` (full repo) → **No issues found**
- Full product-detail + warnings + scoring suites → **580/580 pass**
- Live walkthrough on Thorne Vitamin D in iOS simulator: hero now reads "Thorne · 1 Fluid Ounce(s) · Take 2 drops three times daily" + chips + "● 65/100 Fair" + description. Matches design contract. Score-ring altar gone.

**Karpathy discipline check:**
- Surgical: rebuilt one widget, deleted only what the rebuild orphaned. `PGScoreRing` itself untouched (still used in list rows).
- Simplicity: subtitle reuses the existing `_buildHeroSubtitleSpan` helper rather than re-rolling. Score is one widget call (`ScoreLine(score: ...)`) rather than a 50-line score altar block.
- Goal-driven: visual contract from the design spec verified live before stamping.

---

**T11.1 — live walkthrough refinement (2026-04-29 PM):**

Sean's second walkthrough caught 4 issues with the T11 hero on a different product (GNC Vitamin D):

| Issue | Fix |
|---|---|
| Subtitle middle showed `"30 round yello tablet"` (raw pipeline form_factor) | New `_extractFormNoun()` helper pulls a clean form keyword out of any pipeline string (filters against a `_knownFormNouns` set: capsule/tablet/softgel/gummy/liquid/etc.). Returns null when no recognizable noun, so callers drop the segment cleanly. |
| Net contents produced awkward strings like `"1 Fluid Ounce(s)"` for liquids | Switched the middle segment from `formatNetContents(...)` → new `_formatServingsForm(servings, form)` helper. Combines `servingsPerContainer` × clean form noun with proper singular/plural agreement (1 → "1 Capsule"; 60 → "60 Capsules"; "Gummy" → "Gummies"). |
| Lowercase brand / dose strings sometimes leaked from pipeline (e.g., `"thorne"`, `"take 1 tablet daily"`) | Added `_capFirst(s)` helper applied to all 3 subtitle segments. Capitalizes the first character iff not already uppercase ("GNC" stays "GNC"; "thorne" → "Thorne"). |
| Chips were too big and lived in their own row below the identity row | Shrunk to 10×4 padding / 11pt font / 0.8 border (was 14×7 / 13pt / 1.0). Moved INTO the right column under the subtitle so the image visually owns the left side full-height — matches Sean's premium-tile reference. |

**Files touched (T11.1):**
- `lib/features/product_detail/product_detail_screen.dart` — added `_knownFormNouns`, `_extractFormNoun`, `_formatServingsForm`, `_capFirst` helpers; changed `_HeaderSection` constructor to take `servingsPerContainer: int?` instead of `netContentsQuantity / netContentsUnit`; chips relocated; `_HeroTrustChipOutline` resized

**Verification:**
- `flutter analyze --fatal-infos` (full repo) → **No issues**
- Full product-detail suite → **490/490 pass** (was 488 — ScoreLine + tier tests run together; no regressions)
- Live walkthrough on GNC Vitamin D: hero now reads "Vitamin D / GNC · 30 Tablets · Take 1 tablet daily / [Trusted Manufacturer] / ● 53/100 Low Quality / Notable concerns — weaker ingredients, limited evidence, or avoidable additives" — matches Sean's premium-tag reference

---

### T12 — Personal Fit card

**Goal:** Single fit card: shield icon + headline + max 2 causal bullets + edit pencil.

**DoD:**
- `PersonalFitCard({required FitDisplay fit, required UserProfile profile, required VoidCallback onEditProfile})`
- Headline copy generated from `fit + profile.goals[0]` — e.g., "Good match for your sleep goal" / "Limited fit for your goals"
- Max 2 bullets — pulled from fit-rationale generator (must be causal, not vague)
- **Positive-profile bullets (locked via T3 Path A extension, 2026-04-29):** card MUST call `generatePositiveProfileBullets(ingredientNames: product.actives, userConditionIds: profile.conditions)` and prefer those bullets over generic fit-rationale copy when present, up to the 2-bullet cap. Generates copy like "Magnesium supports your blood pressure goal" / "Folate is recommended during pregnancy" — surfaces benefits the user explicitly cares about (their conditions), instead of the prior behavior of *flagging* those same nutrients as monitor warnings.
- Bullet rules: starts with ingredient or mechanism, references user's profile explicitly
- Edit pencil top-right → calls `onEditProfile` callback (callback wired in screen to navigate to profile edit)
- Widget test: 3 fit states (Strong / Moderate / Limited) render correct headline + bullet count
- Widget test: positive-profile bullets surface for `(profile.conditions ⊃ T3.positive entries)` overlap; absent when no overlap
- Replaces old "For You" + the 3 stack/fit dropdowns — those widgets DELETED

**Files touched:** `lib/features/product_detail/widgets/personal_fit_card.dart` (new), screen wire, test

**Verification:** Test passes. Manual: edit pencil opens profile edit (no crash — depends on T2 landing first). Manual: profile with `hypertension` + product with magnesium → bullet "Magnesium supports your blood pressure goal" appears.

---

### T12 — Personal Fit card — `verified-2026-04-29 PM` (live)

**Design (locked + delivered):**
- Headline row: tier-tinted icon + headline + edit pencil
- Up to 2 causal bullets, max
- Edit pencil → `onEditProfile` callback (wired in screen to `Routes.profileSetup` per T2)

**Headline copy per FitDisplay state:**
| State | Icon | Headline | Tone |
|---|---|---|---|
| FitStrongMatch | shield | "Strong match for your X goal" | scoreExceptional |
| FitGoodMatch | shield | "Good match for your X goal" | scoreExcellent |
| FitLimitedFit | error_outline | "Limited fit for your X goal" | scoreFair |
| FitNotRecommended / FitHidden | do_not_disturb | "Not recommended for your profile" | scoreLow |
| FitIncomplete | person_outline | "Add your profile to personalize" | insufficientData |

**Bullet generation contract:**
1. **First**: positive-profile bullets via T3 Path A's `generatePositiveProfileBullets(...)` — these are causal by construction ("Magnesium supports your blood pressure goal")
2. **Then**: fallback to `FitScoreResult.reasons` (engine-generated)
3. **Cap at 2**
4. **FitHidden / FitNotRecommended / FitIncomplete states** suppress bullets — saying "Magnesium supports your BP goal" next to "Not recommended for your profile" is incoherent

**Files touched:**
- `lib/features/product_detail/widgets/personal_fit_card.dart` — new (~210 lines)
- `lib/features/product_detail/product_detail_screen.dart` — replaced `ForYouSection` call site with `PersonalFitCard`. ForYouSection itself is left in source (T17 will delete it formally).
- `test/features/product_detail/widgets/personal_fit_card_test.dart` — new, 15 tests

**T12.1 — live-walkthrough refinements (2026-04-29 PM):**

Two issues caught after T12 first ship:

| Issue | Fix |
|---|---|
| `"Thorne · 600 Liquids · ..."` (pluralization wrong for mass nouns) | New `_massNounForms = {Liquid, Powder, Tincture}` set in `_formatServingsForm`. When form noun is mass noun, drop the count and render `"Liquid"` alone — dosing-summary segment carries quantity already. |
| `"Diabetes: monitor from Vitamin D"` rendered as bullet 2 — fit engine's `reasons` field leaked the same Vit D × Diabetes false-positive that T4 had suppressed via a separate code path | Added `_isConditionWarningReason(reason)` filter in `_cleanReason`. Drops reasons matching `<condition_label>:` prefix (against the 14-condition lexicon). The condition is gated at the warnings list (T4) and the interaction summary (T4 follow-up); now the bullet fallback is gated too. |

**Verification:**
- `flutter analyze --fatal-infos` (full repo) → **No issues found**
- PersonalFitCard tests → **15/15 pass** (14 baseline + 1 added for T12.1 condition-warning filter)
- Full product-detail + warnings + scoring suite → **594/594 pass**
- Live walkthrough on Thorne Vit D liquid:
  - Hero: "Thorne · Liquid · Take 2 drops three times daily" (was "600 Liquids")
  - Personal Fit: ⚠ Limited fit for your profile + edit pencil
    - Bullet 1: "Vitamin D supports your blood sugar goal" ← T3 Path A positive (Vit D × diabetes)
    - Bullet 2: "Does not strongly support your selected goals" ← clean fitReasons fallback (was "Diabetes: monitor from Vitamin D" pre-fix)

---

### T13 — Alert Summary card — `verified-2026-04-29 PM`

**Goal:** Conditional small card showing alert count + chevron, scrolls to interactions section on tap.

**Design:**
- Pure stateless widget — `AlertSummaryCard({alertCount, onTap})`
- Hides when `alertCount <= 0` (defensive — also handles negatives)
- Plain `PGCard` (not elevated) — visually quiet, the actual content lives below
- ⚠ icon (caution tone) + count copy + chevron
- Singular/plural: "1 interaction to monitor" / "N interactions to monitor"

**Wiring:**
- Renders between Personal Fit (§2) and the existing `_ConditionAlertBanner` (§3 old)
- Suppressed entirely when product is BLOCKED — at that point the BlockedBanner replaces all of §1–§3
- Count comes from `guardedWarnings.length` — that's the post-T4-gate list
- New `_alertsKey` on the SliverToBoxAdapter wrapping `DetailSection` provides the scroll target. `_handleAlertSummaryTap()` calls `Scrollable.ensureVisible` with the same try/catch defensive pattern as `_handleSeeAlternatives` from T1.15.
- Exact §7 placement (only the interactions sub-section) requires DetailSection to expose an internal key — bigger refactor than V1 needs. Scrolling to the start of detail content puts interactions in view; close enough.

**Files touched:**
- `lib/features/product_detail/widgets/alert_summary_card.dart` — new (~85 lines)
- `lib/features/product_detail/product_detail_screen.dart` — `_alertsKey` field + `_handleAlertSummaryTap` method + `AlertSummaryCard` sliver between PersonalFit and ConditionAlertBanner + key on DetailSection sliver
- `test/features/product_detail/widgets/alert_summary_card_test.dart` — new, 7 tests

**Verification:**
- `flutter analyze --fatal-infos` (full repo) → **No issues found**
- AlertSummaryCard tests → **7/7 pass**: hides at 0, hides at negative, renders singular at 1, renders plural at 2/10, tap fires callback, chevron is also a tap target
- Manual TestFlight verification deferred to T23 walkthrough — the scroll-to behavior is hard to validate without a multi-warning test product

---

### T14 — Product Analysis (pillar bars rebuild) — `verified-2026-04-29 PM`

**Goal:** Rename "Product Quality" → "Product Analysis". Normalize all pillar scores to 0–100 + micro-explanations + tier-colored bars.

**Design (delivered):**
- Header rename: `'Product Quality'` → `'Product Analysis'`
- Pillar labels: capitalized + final pillar renamed `'Brand trust'` → `'Transparency & Verification'`
- Locked micro-explanations under each bar:
  | Pillar | Micro-explanation |
  |---|---|
  | Ingredient Quality | Form, dosage, and bioavailability |
  | Safety & Purity | Free from harmful ingredients and contaminants |
  | Evidence & Research | Clinical support behind ingredients |
  | Transparency & Verification | Label clarity and independent testing |
- Score display normalized to `'X/100'` (was `'16.0/25'`, `'4.0/5'`, etc. — required user to mentally normalize across 4 different maxes)
- Bar tier-color via `ScoreTier` (the same 6-tier banding as the hero ScoreLine, keyed on the normalized 0–100 score) — visual coherence across cards
- Bar visual: `LinearProgressIndicator(minHeight: 6)` already matched the spec; ClipRRect with radiusFull already provided full-radius
- New public pure helper `normalizePillarScore(double? raw, int rawMax)` — clamps to 0–100, returns null for invalid input. Tested with 9 cases (null, zero/negative max, exact max, zero, half, above, below, rounding).
- Hero continuity label `"Your X breaks down as:"` deprecated — the score lives on the hero ScoreLine now (T11), so the inline preamble was duplicate. Param kept on constructor for back-compat; render is suppressed.

**Tap behavior:** the existing inline expand-to-show-explanation is preserved. The locked spec calls for a bottom sheet, but inline-expand already provides "tap for detail" UX and the conversion is a polish-tier change. **Deferred to T14.1** if Sean wants the bottom-sheet pattern after the live walkthrough — would require extracting the inline explanation builders into a `PGModal.bottomSheet` content builder. The DoD contract is met as-is.

**Files touched:**
- `lib/features/product_detail/widgets/score_breakdown_card.dart` — added `normalizePillarScore` public helper + `ScoreTier` import; updated header copy, pillar labels, score display format; added `microExplanation` param + render in `_ExpandableSectionBar`; replaced ad-hoc `_colorFor` color picker with `tierForScore(...).color` for cross-card consistency; deprecated heroScore continuity-label rendering
- `test/features/product_detail/score_breakdown_card_test.dart` — full rewrite of expectations against new copy + scores; added 9-test group for `normalizePillarScore` helper

**Verification:**
- `flutter analyze --fatal-infos` (full repo) → **No issues found**
- ScoreBreakdownCard tests → **24/24 pass** (was 13 pre-T14 — added 9 helper tests + 5 new render tests for header/labels/micros/normalized scores; deprecated 3 hero-continuity tests; coverage-line tests preserved)
- Full product-detail suite → **520/520 pass**
- Manual TestFlight walkthrough deferred to T23 — score row alignment + tier colors visible across multiple products will validate the look

---

### T15 — Tradeoffs card cleanup — `verified-2026-04-29 PM`

**Goal:** "What's good / What to consider", max 4 bullets each, no "harmful" prefix, named penalty ingredients.

**Design (delivered):**

1. **`collapseHarmfulAdditives(penalties)` public pure helper.** Pipeline ships labels like `"Harmful additive Sugar syrup"` — one row per flagged additive. Sean's walkthrough: *"we don't need to keep repeating 'harmful additive sugar syrup', 'harmful additive palm oil' — just put 'additive sugar syrup, palm oil' with a comma."* Helper detects the lowercase `"harmful additive "` prefix (case-insensitive against pipeline drift), extracts the ingredient name, and combines all matches into a single `"Additives: X, Y, Z"` row at the front of the returned list. Non-prefixed penalties pass through unchanged.

2. **Per-side cap at 4 bullets** (`_maxTradeoffBulletsPerSide`). Beyond the cap an italic "… and N more" / "… and N concerns" muted footer renders. Singular/plural agreement built in.

3. **No chevron / no tap on overflow.** The section stays quiet by design — if a user wants the full breakdown they tap into the per-pillar Product Analysis bars (T14).

4. **Removed `.take(3)` global cap** in `_extractWhyItems` so the section's per-side cap (4 + 4 = up to 8 bullets) actually has room. Pre-T15 a product with 5 bonuses + 0 penalties showed 3 bonuses; post-T15 it shows 4 + "and 1 more".

**Files touched:**
- `lib/features/product_detail/widgets/tradeoffs_section.dart` — added `_maxTradeoffBulletsPerSide` constant + `_harmfulAdditivePrefix` constant + public `collapseHarmfulAdditives(...)` helper; build method now collapses + caps + renders overflow footer; `_TradeoffColumn` extended with `overflow` + `overflowSingularNoun` params for the muted footer
- `lib/features/product_detail/product_detail_screen.dart` — removed `.take(3)` from `_extractWhyItems` (per-side cap lives downstream now)
- `test/features/product_detail/widgets/tradeoffs_section_test.dart` — full rewrite, 12 tests covering collapse logic + cap rendering

**Verification:**
- `flutter analyze --fatal-infos` (full repo) → **No issues found**
- TradeoffsSection tests → **12/12 pass**: 6 collapse-helper tests (empty / non-additive passthrough / single / multiple / mixed / case-insensitive) + 6 render tests (prefix never reaches DOM / 4-cap no footer / 6→4+"2 concerns" / 5→4+"1 more" / interplay / empty hides)
- Full product-detail suite → **522/522 pass** (520 → 522 — net +2 from new tests minus retired old ones)

---

### T16 — Ingredients card (merged) — `verified-2026-04-30`

**Goal:** Single 3D card with two sub-sections: Active (all shown, never paginated) + Inactive (chips + expander with color dots).

**Design (delivered):**
- New `IngredientsCard({activeContent, inactiveNames, inactiveChipCap})` widget — `PGCard(variant: elevated)` wrapping both sub-sections
- Internal `Divider` (0.5pt, outlineVariant) between active + inactive
- Active sub-section: takes a `Widget? activeContent` parameter so the screen passes the existing `_CollapsibleIngredients` (no widget promotion needed; loose coupling preserved)
- Inactive sub-section:
  - Top-8 chip wrap (existing `InactiveIngredientChip` reused — preserves the tap-to-explain bottom sheet from T1.5)
  - Tappable "See all N ingredients ⌄" toggle when more than 8 — expands inline to render the FULL list with color dots
  - "Show less ⌃" collapses back
  - Color rubric: 🟢 green (whitelisted excipient) / 🟡 yellow (acceptable) / 🟠 orange (watchlist — palm oil, carrageenan, titanium dioxide, etc.) / 🔴 red (penalty — artificial dyes, sweeteners, syrups, partially hydrogenated oils, BHA/BHT)

**New `inactive_color.dart` module:**
- `enum InactiveTone { green, yellow, orange, red }` + `inactiveColorRank(String name) → InactiveTone` helper
- Defers to `standard_excipients.dart` `isWhitelistedExcipient` for green
- Curated `_redInactives` set (~25 entries — common dyes, sweeteners, syrups, partially hydrogenated oils, BHA/BHT)
- Curated `_orangeInactives` set (~10 entries — palm oil family, carrageenan, polysorbate 80, etc.)
- Default: yellow
- `InactiveToneColor` extension maps each tone → `AppTheme.severity*` color

**Wiring:**
- Screen replaces the prior two-section block (active list + inactive chip wrap + "+N more" pill) with a single `IngredientsCard(...)` invocation
- Removed orphans: `visibleInactives` / `hiddenInactivesCount` locals, `_sectionTitle` private helper, `ingredients_section.dart` import (chip widget is now consumed inside IngredientsCard)
- Active row design (name · dose · safety tag · form chip · bio dot) UNCHANGED — all Sprint 1 work preserved; T16 only restructures the surrounding container

**Active quality chip deferred:** The locked spec mentions `[Quality chip] (Strong / Moderate / Limited)` per active row. The existing `_IngredientTile` already renders a `_SafetyTag` + form chip; adding a per-ingredient evidence-tier chip requires per-active evidence data the pipeline doesn't reliably ship today. Backlog (B7).

**Tap-to-deep-dive on active rows:** Existing `_IngredientTile` is informational, not tappable. The locked spec mentions tap → per-ingredient deep-dive sheet. Defer to a follow-up — the deep-dive sheet would need to be designed and built (no existing widget). Backlog (B8).

**Files touched:**
- `lib/features/product_detail/widgets/inactive_color.dart` — new (~110 lines, helper + curated sets)
- `lib/features/product_detail/widgets/ingredients_card.dart` — new (~190 lines, card + state + dot row)
- `lib/features/product_detail/product_detail_screen.dart` — replaced two sections with `IngredientsCard`, removed dead locals + helper + import
- `test/features/product_detail/widgets/ingredients_card_test.dart` — new, 16 tests
- `test/features/product_detail/widgets/detail_section_order_test.dart` — pin-the-order test updated to anchor via `IngredientsCard` widget type instead of the now-moved "Other Ingredients" header text (T20 will rebuild the full pin-the-order test for the post-S2.2 IA)

**Verification:**
- `flutter analyze --fatal-infos` (full repo) → **No issues found**
- IngredientsCard tests → **16/16 pass** (9 helper tests + 7 render tests)
- Full product-detail + warnings + scoring suite → **631/631 pass**

---

### T15.1 — Tradeoffs expand-in-place toggle (live-walkthrough follow-up) — `verified-2026-04-30`

**Trigger:** Sean's mid-T16 walkthrough: *"if it goes over few line, we should have a drop down to show more, and list all there, easier than scrolling somewhere else to read."*

**Fix:** Converted the static "… and N concerns" footer into a tappable expand-in-place toggle. Pre-T15.1: muted italic line, no interaction. Post-T15.1: `"Show N more concerns ⌄"` → tap → renders ALL remaining items inline → `"Show less ⌃"` to collapse.

`_TradeoffColumn` promoted from `StatelessWidget` → `StatefulWidget`. `_pluralize` helper added (handles "concern → concerns" and "bonus → bonuses" — naive but covers the 2 nouns this widget needs). Bonus column noun changed from `'more'` to `'bonus'` so the plural form "Show 2 more bonuses" reads naturally.

**Files touched:** `tradeoffs_section.dart`, `tradeoffs_section_test.dart` — 4 new tests (toggle render / tap expands / tap collapses / pluralizer correctness).

**Verification:** **15/15** TradeoffsSection tests pass.

---

### T15.2 — Tradeoffs safety-summary bullet (live-walkthrough follow-up) — `verified-2026-04-30`

**Trigger:** Sean's 2026-04-30 PM walkthrough — once inactive ingredients ship pipeline-driven `severity_level` (T16 follow-up), long lists default to collapsed and the user has no at-a-glance signal that some entries are clinically concerning. Sean's call: *"we can add a one liner concern in case the products has x amount of high penalty ingredients, but user friendly."*

**Locked design contract (Sean):**

- **Surface:** ONLY in "What to consider". Sacred separation — never in Interactions (additives ≠ body/med interactions; mixing dilutes clinical meaning).
- **Threshold:** trigger if `(high ≥ 1) OR (moderate ≥ 3) OR (combined ≥ 2)`. Catches a single serious offender, a cluster of moderates, and mixed cases. Does NOT fire on `low`-only or empty.
- **Copy:** `"N ingredients flagged for safety — review the list"` — neutral, action-oriented, works for both high and moderate clusters; avoids legal/clinical overstatement.
- **Visual cue:** 🔴 red dot when ANY high present, 🟠 orange when moderate-only.
- **Guardrail:** never show on `low`/`none` only. Never duplicate across surfaces.

**Decision evolution worth recording:** initial implementation included a tap-and-scroll affordance (controller + `GlobalKey` + `KeyedSubtree` + `ConsumerStatefulWidget` conversion of `DetailSection`) so the bullet's `"review the list"` would scroll-and-expand the inactives section. Sean cut it: *"we don't need to tap anything in what to consider, do you really think we need to tap and scroll? also inactive ingredients section comes before what to consider."* Stripped the entire plumbing back to a static informational line — the dot-coded inactives list renders directly above this section, so `"review the list"` is a passive directive. ~150 lines deleted relative to the tap-enabled draft. **Future reader: do not re-add tap; see this entry for why.**

**Files touched:** `tradeoffs_section.dart` (`_SafetySummaryBullet`, `_InactiveSeverityCount` + `shouldShowSummary` threshold, `inactiveIngredients` param on `TradeoffsSection`, `leading` slot on `_TradeoffColumn`), `product_detail_screen.dart` (wire `inactiveIngredients` from blob into `TradeoffsSection`), `tradeoffs_section_test.dart` — 11 new widget tests covering threshold + dot color + guardrails.

**Verification:** **1241/1241** full suite pass; `flutter analyze` clean. Pushed as commit [`b06c1a8`](https://github.com/seancheick/Pharmaguide.ai/commit/b06c1a8).

---

### T17 — Strip dead sections

**Goal:** Delete from screen: Pair Well With Your Stack, 60-day battery, bottom Product Details block.

**DoD:**
- Three sections removed from `product_detail_screen.dart` Column
- Their widgets deleted from source (`pairs_well_section.dart`, battery widget, Product Details bottom block)
- No dead imports
- Pin-the-order test (T22) updated

**Files touched:** `product_detail_screen.dart`, deleted widget files

**Verification:** `flutter analyze --fatal-infos` clean. Manual: page no longer shows these sections.

---

### T18 — Collapse Nutrition Facts

**Goal:** Replace full panel with "View supplement facts" link → bottom sheet.

**DoD:**
- Inline link replaces the full table in scroll
- Tap → existing nutrition table renders in bottom sheet
- Link hidden when product has no nutrition data
- No regression in supplement-facts content — just relocation

**Files touched:** `product_detail_screen.dart`, nutrition section widget

**Verification:** Manual: nutrition data still accessible, no longer dominates scroll.

---

### T19 — Audit Deep Dive section

**Goal:** Identify content unique to Deep Dive vs already-shown above. Fold unique content into Evidence (§9). Delete the rest.

**DoD:**
- Audit doc — table of every Deep Dive sub-block + verdict (`fold` / `delete`)
- Apply verdicts
- Pin-the-order test updated to remove DeepDive type expectation

**Files touched:** `product_detail_screen.dart`, deep dive widget files

**Verification:** Manual: no duplicate content visible on the page; Evidence section feels complete.

---

### T20 — Pin-the-order regression test (rebuilt)

**Goal:** Top-edge Y assertion test for the new section order: Header → Personal Fit → Alert Summary → Product Analysis → Tradeoffs → Ingredients → Interactions → Synergy → Evidence → Footer.

**DoD:**
- `test/features/product_detail/widgets/cleanup_section_order_test.dart` (new)
- Mirrors prior `detail_section_order_test.dart` pattern — full fixture, mount widget, read top-edge Y per section, assert ordering
- Replaces the old order test once IA stabilizes

**Files touched:** test file, delete prior order test

**Verification:** Test passes against the new structure.

---

**Sprint S2.2 Exit Criteria:**
- All 12 tasks (T9–T20) closed with verification
- `flutter analyze --fatal-infos` → No issues
- `flutter test` → all passing, count steady or growing
- Manual: product page reads as designed for Magnesium / Vit D / Multivitamin / Pre-workout / Probiotic
- Pin-the-order test green
- No "harmful additive" prefix appears on any test product

---

## Sprint S2.3 — Polish & cleanup

### T21 — Footer cleanup

**Goal:** Footer matches contract — no italic, no coverage line, sources line, rephrased disclaimer.

**DoD:**
- Remove `mappedCoverage` "X/Y" line
- Sources: "NIH, FDA, PubMed" — single line
- Disclaimer rephrased: "Educational use only — not medical advice." (replaces "PharmaGuide does not sell supplements")
- Removed: italic styling everywhere in footer
- Pure helper `formatRelativeUpdate` (already exists from Sprint 1) reused unchanged
- Widget test asserts no `FontStyle.italic` in footer subtree

**Files touched:** `lib/features/product_detail/widgets/transparency_footer.dart`, test

**Verification:** Test passes. Visual: footer reads cleanly, normal weight throughout.

---

### T22 — Synergy Cluster (tightened)

**Goal:** Conditional "Works well with" section, max 3 items, only when high-confidence signal present.

**DoD:**
- Pre-flight: verify pipeline supplies `synergy_confidence` field (or equivalent). If absent → defer to backlog, do not ship V1
- If field exists: render section only when `confidence >= 0.7` for at least one synergy
- Max 3 items shown — sorted by confidence desc
- Copy: "Works well with: [chip] [chip] [chip]"
- No section rendered when 0 high-confidence synergies
- Widget test: 0/2/5 synergy inputs → 0 cap / 2 / 3 rendered

**Files touched:** `lib/features/product_detail/widgets/synergy_cluster.dart` (new or rebuild), test

**Verification:** If pipeline supports → test passes + manual confirms render logic. If not → task deferred to backlog with explicit note.

---

### T23 — Manual TestFlight walkthrough

**Goal:** 5-product walkthrough confirms initiative DoD across the matrix.

**DoD:** Walk through each in TestFlight with Sean's profile loaded:

| Product | Expected behavior |
|---------|-------------------|
| Thorne Magnesium Bisglycinate | Score ~Exceptional / Excellent · Sleep goal match · No false positives |
| Vit D 1000 IU | Score ~Excellent · No TTC monitor flag · No diabetes monitor flag |
| Generic multivitamin (8+ actives) | Active list shows all without overflow · Inactive expander works |
| Pre-workout (proprietary blend) | Tradeoffs surfaces blend opacity · Score reflects penalty |
| Probiotic | No false TTC/diabetes flags · Evidence card honest about strain-specific data |

**DoD:**
- Capture screenshots per product
- Note any regressions / unexpected behavior
- Open follow-up tasks for anything that didn't ship as designed

**Verification:** All 5 products read as designed; if any don't, file backlog task.

---

### T24 — Sentry 24h watch post-deploy

**Goal:** Per Sprint 1 protocol — no new error classes from this initiative within 24h post-deploy.

**DoD:**
- Tag deploy with `init/product-detail-cleanup`
- Monitor Sentry for 24h
- If new error classes surface → file P0 hotfix, do not move to S2.4 backlog work
- If clean → mark initiative closed

**Verification:** Sentry dashboard clean for 24h.

---

**Sprint S2.3 Exit Criteria:**
- T21–T24 closed
- TestFlight walkthrough green on all 5 products
- 24h Sentry watch clean
- Initiative officially closed-out

---

## Backlog (S2.4 / future)

Tracked here for visibility — not in scope for this initiative. Pull into next initiative or defer indefinitely.

| ID | Item | Notes |
|----|------|-------|
| B1 | Ingredient role taxonomy | One-word role per inactive ingredient. Needs comprehensive taxonomy beyond the 17 whitelisted excipients. ~1 day curation. |
| B2 | Dosage chip per active | "Below optimal / Optimal / High" vs clinical-effective dose. Needs per-ingredient threshold table. |
| B3 | Image gallery | Multiple product images, swipeable. Pipeline must ship `image_urls[]`. |
| B4 | Synergy data infrastructure | If pipeline doesn't ship `synergy_confidence` (T22 pre-flight fails), curated synergy table needs design. |
| B5 | Evidence section deep enrichment | Per-strain / per-form evidence (e.g., probiotic strain-specific) — currently rolls up to coarse tier. |
| B6 | Threshold table v2 | T3's curated table is V1 — review against latest clinical literature in 6 months. |

---

## Audit Gate Protocol

Mirroring Sprint 1's pause-and-verify cadence:

1. **Before starting a task** — read this doc, confirm DoD scope, surface assumptions
2. **During the task** — Karpathy discipline: surgical changes, no scope creep, no speculative abstractions
3. **After implementation** — run `flutter analyze --fatal-infos` + relevant test subset
4. **Before closing** — verification step from DoD must pass; stamp the task with `verified-YYYY-MM-DD` line
5. **Between tasks** — wait for explicit "continue" / "go" from Sean, do not chain

---

## Definition of Initiative Done

- [ ] All 24 tasks (T1–T24) closed with verification stamps
- [ ] Pin-the-order regression test green for new structure
- [ ] `flutter analyze --fatal-infos` → No issues
- [ ] `flutter test` → all passing, count >= Sprint 1 baseline (1075)
- [ ] No "harmful additive [name]" prefix on any test product
- [ ] No false-positive condition flag on Vit D 1000 IU + TTC profile
- [ ] No false-positive condition flag on Mg 200 mg + diabetes profile
- [ ] TestFlight walkthrough green on 5-product matrix
- [ ] 24h Sentry watch post-deploy clean
- [ ] Backlog items B1–B6 logged for future sprints

---

**Last updated:** 2026-04-29  
**Next action:** Awaiting Sean's "go" to start Sprint S2.1 / T1.
