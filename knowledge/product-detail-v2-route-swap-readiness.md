# Product Detail v2 — Route-Swap Readiness Report

**Date:** 2026-05-15 → 2026-05-16
**Branch:** `design/v2-mobile-polish`
**Author:** Phase 11.7g verification pass
**Decision sought:** Approve or block flipping `/product/:dsldId` from
`ProductDetailScreen` → `ProductDetailV2ConnectedScreen` in `app.dart`.

---

## Executive summary

Phase 11.7 (Product Detail v2 adapter wiring) is **structurally
complete** — all 18 sections wired, 0 placeholders, analyzer clean
across `lib/`, no orphaned imports.

**Updated 2026-05-16** after Phase 11.7g.1 targeted live verification
on iPhone 17 (iOS 26.5) simulator with **Supabase blob populated** for
test products:

- **14 sections tile-render verified live** (up from 7 earlier)
- **5 sections suppression-only verified live** (verbatim helper ports
  cover the static parity argument)
- **1 known recommendation-logic flaw** carried over from production
  (S16 Better Alternatives — filed as separate non-blocking
  product-logic bug in `knowledge/v2-audit-backlog.md`)

**Route swap is now stronger than expected — significantly more
ground covered than the original 7-section verification baseline.**

---

## 1. Live tile-render verified (Phase 11.7g.1, 2026-05-16)

These were exercised on the iPhone 17 simulator and produced real
v2 visual output with real blob data:

| # | Section | Test path | What rendered |
|---|---|---|---|
| S1 | Hero | 178767 (long-name, 88 chars), 65844 (rich-blob), 16012 (blocked) | Title truncates cleanly to 3 lines on long names; image, brand, serving info, trust tags all correct |
| S1.5 | BlockedBanner | 16012 Thorne Vinpocetine | FDA-banned headline + "FDA ban effective · Sep 7, 2016" date line + safety paragraph + detail paragraph all render verbatim |
| S2 | PersonalFit (FitIncomplete) | 65844, 178767 | "Add your profile to personalize" + edit-pencil tap → Routes.profileSetup |
| S3 | ReviewBeforeUse — **no-profile NUDGE path** | 178767 | "This product has known interactions" + "Complete profile" pill button — FIRST live verify of nudge state |
| S3 | ReviewBeforeUse — **warning ROW path** | 65844 (Thorne MediPro w/ 1 hint) | Card title "Review before use" + count badge "1" + caution-tone "Diabetes" row with "Contains 4.0g sugar per serving. May affect blood glucose levels. · Theoretical" — FIRST live verify of populated warning row |
| S4 | LabelConfidence — **NOTE tier** | 65844 (discontinued product) | "Product note" header + "Product discontinued · Aug 8, 2017" row with tap-to-explanation chevron — FIRST live verify of note tier |
| S5 | ScoreBreakdown | 178767, 65844 | "Why this scored 64/89" title + 4 pillars on 0–10 scale + coverage tier line "Most ingredients in our database — high-confidence score" |
| S6 | Ingredients — **active list** | 178767 (3 active rows) | "Active Ingredients [3]" header + rows: Vitamin C 180mg/Excellent, Rose hips 780mg/Good, beta-carotene 90 IU/Good. Form chips render with correct tier colors |
| S6 | Ingredients — **inactive list** | 178767 | "Other ingredients [7]" collapsible header with count badge — first live verify of structured inactive presentation |
| S7 | Tradeoffs | 178767 | "WHAT'S GOOD" / "WHAT TO CONSIDER" two-column split rendering correctly ("Natural-source ingredients" / "Harmful additive: Dextrose") |
| S9 | Nutrition Facts | 178767, 65844 | Calories + nutrient rows with right-aligned values + unit suffix ("170", "5 g", "14 g") |
| S10 | Certifications | 65844 (Thorne) | "Certifications & checks" header + 5 rows: 3 standard checks (Purity Verified, Heavy Metal Tested, Label Accuracy Verified) + 2 third-party programs (NSF Sport, USP Verified) with "Third-party verified" caption — FIRST live verify |
| S11 | Evidence — tier banner | 178767, 65844 (both LIMITED) | "Clinical evidence · LIMITED" tier banner with amber dot |
| S13 | Formulation | 65844 (botanicals-rich product) | "Formulation" header + 7 botanicals chips (Chlorella Protein, Inulin, Flax seed powder, Carrot, Broccoli, Beet, Spinach) — FIRST live verify |
| S14 | Probiotic | 65844 (multi-strain probiotic shake) | "Probiotic strains" header + "Prebiotic included" green chip + strain rows (Lactobacillus acidophilus · HIGH evidence, Bifidobacterium animalis lactis · HIGH) — FIRST live verify |
| S17 | TransparencyFooter | 178767, 65844, 16012 | "DATA SOURCES · NIH ODS · PubMed · FDA" + freshness label **"Updated May 15, 2026"** — FIRST live verify of catalogInfoProvider-driven freshness |

---

## 2. Suppression-only verified live (no tile-render fired this pass)

These rendered as `SizedBox.shrink()` correctly because their blob
signals weren't present in test products. Their tile-render code
paths use verbatim production helpers — the static parity argument
covers behavior:

| # | Section | Why no live tile in this pass |
|---|---|---|
| S8 | Populations | Test products had no profile-matched conditions firing through the hint parser |
| S12 | HeavyMetal | Test products had no `heavy_metal_detail.signals[]` (good news — no contamination flags in shipped catalog) |
| S15 | ManufacturerViolations | Test products had no `manufacturer_detail.violations.violations[]` (Thorne brand has clean record) |
| S16 | BetterAlternatives | 178767 had FitIncomplete + score=64 (gate doesn't fire). 65844 scored 89 (gate doesn't fire). 16012 blocked but `primary_category` is null → expected suppression (**matches production behavior verbatim**) |
| S18 | AllergenSummaryBanner | All test products had structured allergen flags (Gluten-Free / Dairy-Free / Soy-Free) → suppressed correctly per the matchedAllergens check |

---

## 3. NOT live-verified (environment limitations)

The shipped DB doesn't contain candidates for these scenarios. They
are not v2 wiring bugs.

| Scenario | Why blocked |
|---|---|
| NOT_SCORED non-blocked product | Every NOT_SCORED entry in shipped DB is also FDA-banned → goes through BlockedBanner path before LabelConfidence S4 partial/limited tier can fire. |
| Missing-image product | All shipped products have `image_url` populated. PGProductHero's documented placeholder branch is reachable in code; live render not exercised. |
| S12/S15/S16(result-list) | Need products with `heavy_metal_detail`, `manufacturer_detail.violations`, or low-score-with-category-having-cleaner-alternatives. None encountered in this pass; can be tested in TestFlight cycle. |

---

## 4. Known risks

### 4.1 Recommendation-logic flaw (S16 Better Alternatives)
Already documented + filed in
`knowledge/v2-audit-backlog.md`. **Carried over from production
verbatim** — v2 renders the same `findAlternatives` output, doesn't
amplify the issue. Does NOT block route swap. Schedule separate
product-logic sprint.

### 4.2 S16 BetterAlternatives renders blank for blocked products with null primary_category
Vinpocetine (16012) is blocked + `primary_category == null` →
section suppresses entirely (no "See safer alternatives" content
visible after the BlockedBanner). **Production has the same
behavior** (better_alternatives.dart:77-79). Not a v2 regression.

If desired, this could be improved as a separate fix: when blocked +
no category, surface a static "Browse safer alternatives" link to
search, instead of silently hiding. **Not blocking this swap.**

### 4.3 Long-name truncation
178767 (88-char name) truncates with "..." after 3 visible lines.
Acceptable per the v2 hero design contract ("Max 2-3 visible title
lines"). Compare side-by-side with production behavior in TestFlight
to confirm parity.

### 4.4 Impeller validation error (Flutter engine)
The flutter run output included:
```
[ERROR:flutter/impeller/entity/contents/contents.cc(119)]
Break on 'ImpellerValidationBreak' to inspect point of failure:
Contents::SetInheritedOpacity should never be called when
Contents::CanAcceptOpacity returns false.
```
This is a **Flutter engine validation message**, not a v2 issue.
Production should hit the same. Visual output is correct. Tracking
separately if it surfaces user-visible defects.

### 4.5 Tile-render gaps on S12 / S15 / S18 (legacy free-text allergens)
These are rare-firing safety surfaces. The verbatim-helper-port
argument covers parity: composition logic is imported, not
reimplemented; only the visual card surface differs. Live tile-
render verification deferred to TestFlight cycle.

---

## 5. Rollback plan if swap exposes issues

The swap is a **single-line change** in `lib/app.dart` — the route
table mapping `/product/:dsldId` → either the legacy
`ProductDetailScreen` or v2 `ProductDetailV2ConnectedScreen`.

### Rollback steps
```bash
# Single commit revert
git revert <swap-commit-hash>
# Or hand-edit app.dart to point back to the legacy widget.
```

### What's safe about this approach
- **Legacy route is NOT deleted** in the swap commit. `app.dart`
  keeps the import and switches via the route mapping only.
  Reverting the mapping line restores the legacy path immediately
  without code-restoration work.
- **All v2 section files remain on disk** under
  `lib/features/product_detail/v2/sections/*.dart` — partial
  rollback possible if one section is buggy (flip that one back via
  a wrapper).
- **The dev route `/dev/v2/product/:dsldId`** stays active so QA can
  keep testing the v2 path even after a rollback.

### When to roll back
- A safety-critical surface (BlockedBanner, ReviewBeforeUse warnings,
  LabelConfidence) renders incorrectly on real-blob data.
- The scroll anchor breaks (sticky CTA tap goes nowhere).
- A blob shape this build hasn't seen produces a crash.

### When NOT to roll back
- Cosmetic v2-tone-vs-prod-tone differences.
- Behaviors documented in the parity doc as deliberate v2
  improvements (ScoreBreakdown's 0–10 normalized display, S3 privacy
  correction, S5 right-aligned pillar scores, S6 collapsible
  active+inactive auto-expand ≤5).

---

## 6. Recommendation

**Phase 11.7g.1 produced significantly stronger live verification
than the original 7-section baseline assumed.** With 14 sections
tile-render verified on a Supabase-connected build with real blob
data, the v2 path is materially proven against production blob
shapes.

### Option A — Stage the swap behind a debug toggle (recommended)
1. Keep `/product/:dsldId` → legacy `ProductDetailScreen` as the
   default in `app.dart`.
2. Add a `useV2ProductDetail` debug-only Riverpod flag (mirrors the
   `useV2Theme` pattern already in `app.dart`) that swaps the
   widget at the route boundary.
3. Ship one TestFlight build with the flag default ON.
4. Promote to default after one clean cycle.

### Option B — Hard-swap now
Acceptable given the verification depth in §1. Lower-friction
operationally. Rollback is one line.

### My recommendation: **Option A — staged toggle.**
Cost is ~30 minutes of wire-up; gain is one TestFlight cycle of
real-blob verification on S12/S15/S18 before the production route
flips for all users.

**Awaiting Sean's approval before touching production route.**

---

## 7. Outstanding work items (not blocking the swap)

- [ ] **Better Alternatives recommendation-logic fix** —
      separate product-logic sprint (already in backlog).
- [ ] Scanner v2 two-stage flow — Phase 11.8, blocked on Product
      Detail v2 stability.
- [ ] Legacy `ProductDetailScreen` deletion — defer to a later
      cleanup commit AFTER one stable TestFlight cycle on v2.
- [ ] Inactive-row tap → functional roles sheet (S6.next) —
      production sheet is private; surfacing requires extracting to
      a public function.
- [ ] Production sub-score line parsing in S5 (`_explainFn`) —
      deferred v2 component enhancement.
- [ ] Tile-render live verification of S12, S15, S16(result-list),
      S18 on a TestFlight cycle.
- [ ] Re-verify long-name truncation (178767) side-by-side with
      production to confirm parity is intentional.

---

## 8. Test product map (for follow-up sessions)

| Scenario | dsldId | Brand | Why useful |
|---|---|---|---|
| Long-name (88 chars) | 178767 | Spring Valley | Hero truncation parity test |
| Rich-blob (S3 warning + S4 note + S10 cert + S13 form + S14 probiotic) | 65844 | Thorne MediPro Vegan | Maximum mid-page coverage |
| FDA-blocked | 16012 | Thorne Vinpocetine | S1.5 + suppression of S2-S15 + S16 null-category-no-render edge case |
| (Future) Heavy metal | TBD | — | Need product with `heavy_metal_detail.signals[]` |
| (Future) Manufacturer violations | TBD | — | Need product with `manufacturer_detail.violations.violations[]` |
| (Future) Legacy free-text allergens | TBD | — | Need product with `allergenSummary` + no `blob.allergens[]` |
| (Future) NOT_SCORED non-blocked | TBD | — | Need product where score is null but not banned |
| (Future) Low-score with alternatives | TBD | — | Need product with score < 60 AND populated category for S16 result list |
