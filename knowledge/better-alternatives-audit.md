# Better Alternatives — Audit + Ranking Formula

**Phase:** 11.7L.F
**Date:** 2026-05-16
**Author:** Sean + Claude (live-DB audit)

---

## Why this audit exists

The "Higher quality alternatives" section on Product Detail originally
ranked candidates by the legacy **`score_quality_80`** field alone, filtered only by
`primary_category` and a minimum-score floor that mostly mirrors the
current product's own score. The result: when the user lands on a
poor-quality product, the section sometimes recommends products that
make no sense — different supplement type, different audience,
discontinued products, or even mis-categorised items.

This file documents:

1. The exact failure modes from a live query against the bundled
   catalog (8,441 products in `assets/db/pharmaguide_core.db`).
2. Concrete pinned examples that became regression test fixtures.
3. The proposed v2 ranking formula and what each criterion buys us.
4. The data fields the ranker reads from `products_core`.

---

## Historical logic that caused the bug

```dart
// lib/features/product_detail/widgets/better_alternatives.dart
final minQualityV4 = (currentScore! * 0.8).clamp(0.0, 100.0);
return coreDb.findAlternatives(
  category!, minQualityV4,
  excludeDsldId: currentDsldId, limit: 3,
);

// lib/data/database/core_database.dart::findAlternatives
SELECT * FROM products_core
WHERE primary_category = :category
  AND quality_score_status = 'scored'
  AND quality_score_v4_100 >= :minScore
  AND dsld_id != :currentDsldId
ORDER BY quality_score_v4_100 DESC
LIMIT :limit;
```

Three problems just from reading the query:

| # | Problem | Failure mode |
|---|---|---|
| 1 | `>= currentScore`, not `>` | A score-50 multi can suggest other score-50 products as "better" |
| 2 | No on-market filter | 24% of the catalog (2,010 products) is `discontinued_date != NULL` |
| 3 | `primary_category` is the only intent signal | "multivitamin" alone covers 1,947 products of wildly different types |

---

## Catalog field coverage (2026-05-16)

```
total                                 8441
has supplement_type                   8441 (100%)   ← USE THIS
has goal_matches                      5561 (66%)
has key_ingredient_tags               3593 (43%)
off-market (discontinued_date != null) 2010 (24%)   ← FILTER THIS
primary_category populated            3512 (42%)
```

`supplement_type` is the most reliable intent signal — populated on
every product. `goal_matches` and `key_ingredient_tags` are
second-tier (populated on roughly half the catalog).

---

## Bad examples from legacy live data

These examples came from the V3 `/80` catalog. The failure modes still matter,
but new implementations must use `quality_score_v4_100`.

### #1 — Staminol (male herbal energy blend) → prenatal vitamin

| Field | Current product | Top current recommendation |
|---|---|---|
| dsld_id | 315814 | 328830 |
| product_name | Staminol | Basic Prenatal |
| brand | GNC Mega Men | Thorne |
| supplement_type | **herbal_blend** | **multivitamin** |
| primary_category | multivitamin | multivitamin |
| legacy score | 18.5 | 72.4 |

A man buying a stamina/energy herbal blend gets a prenatal vitamin
recommended. Different audience, different intent, different
ingredient family. The category match is technically true but the
two products belong to entirely different needs.

**Root cause:** category bucket is too broad; `supplement_type`
mismatch ignored.

---

### #2 — Vitamin A 8,000 IU → cognitive multi + kids' chewable

| Field | Current product | Top recommendation | #2 recommendation |
|---|---|---|---|
| dsld_id | 19170 | 337875 | 281264 |
| product_name | A 8,000 IU | SynaQuell | Kids Multi + Strawberry Kiwi |
| brand | CVS Pharmacy | Thorne | Thorne |
| supplement_type | **targeted** | multivitamin | multivitamin |
| legacy score | 37.0 | 69.0 | 68.8 |
| discontinued | no | no | **yes** |

A single-ingredient Vitamin A buyer gets a brain-support multi and a
kids' chewable. Plus the #2 recommendation is discontinued.

**Root cause:** no `supplement_type=targeted` strict filter; no
on-market gate.

---

### #3 — GNC Probiotic Complex → discontinued product + magnesium

| Field | Current product | Top recommendation | #4 recommendation |
|---|---|---|---|
| dsld_id | 1646 | 15581 | 297681 |
| product_name | Probiotic Complex 1 | Restore | Magnesium with Pre & Probiotics Gummies |
| brand | GNC Probiotics | Thorne Performance | Garden of Life Dr. Formulated |
| supplement_type | probiotic | probiotic | probiotic |
| legacy score | 25.3 | 62.4 | 58.0 |
| discontinued | no | **yes** | no |

The #1 spot is a discontinued product — user can't buy it. #4 is a
magnesium that happens to contain probiotics, not a probiotic-first
product.

**Root cause:** no on-market gate; `key_ingredient_tags` /
`is_probiotic` not weighted (a probiotic-first product should beat
a magnesium-with-probiotics).

---

### #4 — Children's Multivitamin Gummies → adult prenatal + discontinued

| Field | Current product | Top recommendations |
|---|---|---|
| dsld_id | 178559 | 336315 / 328830 / 313907 |
| product_name | Children's Multivitamin Gummies | Thorne A.M. / Basic Prenatal / Advanced Nutrients |
| audience | kids | adult / prenatal / adult |
| legacy score | 44.1 | 72.6 / 72.4 / 71.8 |
| discontinued (#3) | no | **yes** |

A parent shopping for their child gets "Basic Prenatal" suggested.
This is tone-deaf at best, mildly dangerous at worst (prenatals have
very different micronutrient profiles than children's formulations).

**Root cause:** no audience awareness (kids/adult/prenatal); no
on-market gate.

---

### #5 — Score-tie "alternatives"

The current threshold is `>= currentScore`, not `>`. For any product
at score X, candidates at score X qualify as "higher quality." E.g.
a 50-score multi can have 50-score multis returned as "Higher
quality alternatives."

**Root cause:** off-by-one comparison.

---

## Proposed ranking formula

The goal: **trust before brevity**. The user sees 2-3 picks at most;
each pick must be defensibly better than what they're looking at.

### Hard filters (drop from candidate pool)

A candidate is dropped before ranking if any of these are true:

1. `dsld_id == currentDsldId` (don't recommend the same product)
2. `discontinued_date != NULL` (off-market)
3. `quality_score_status != 'scored'` or `quality_score_v4_100 <= currentScore` (must be STRICTLY higher)
4. `has_banned_substance == 1`
5. `has_recalled_ingredient == 1`

### Tiered candidate buckets

Build the candidate list from buckets, top to bottom, until we have
enough (target 3, max-fetch 30 per bucket):

| Tier | Match criteria | Why |
|---|---|---|
| **A** | Same `supplement_type` AND ingredient-family overlap ≥ 0.5 | Closest swap — same intent, same active family |
| **B** | Same `supplement_type` only | Same intent even if active mix differs |
| **C** | Ingredient-family overlap ≥ 0.5 (different supplement_type) | Same active family even if presentation differs |
| **D** | Same `primary_category` only (today's default) | Last-resort same-bucket fallback |

"Ingredient-family overlap" reads from `key_ingredient_tags`
(parsed as a lowercase JSON list) and the `contains_*` boolean
flags (`omega3`, `probiotics`, `collagen`, `adaptogens`,
`nootropics`, `is_probiotic`). Jaccard similarity between the two
sets — 1.0 means identical families; 0 means none in common.

### Tiebreakers within a tier

When multiple candidates qualify for the same tier, rank by:

1. **Ingredient family Jaccard** DESC (closer match wins)
2. **Goal-match Jaccard** DESC (when both sides have `goal_matches`)
3. **`quality_score_v4_100`** DESC (higher quality)
4. **`mapped_coverage`** DESC (more complete ingredient data → more
   trustworthy comparison)
5. **`score_brand_trust`** DESC (transparency / third-party testing)
6. **Allergen compatibility** DESC (preserves the current product's
   allergen-free flags — gluten-free, dairy-free, soy-free, vegan)

### Why this order matches Sean's priorities

| Sean's priority | Where it lives in the formula |
|---|---|
| 1. Same product intent / use case | Tier A + B (`supplement_type` match) |
| 2. Same key active ingredient family | Tier A + C (Jaccard on `key_ingredient_tags` + `contains_*` flags) |
| 3. Same category | Tier D + the candidate-pool query stays category-scoped |
| 4. Higher quality score | Hard filter (`> current`) + tiebreaker #3 |
| 5. Better transparency / formulation | Tiebreakers #4 + #5 (`mapped_coverage`, `score_brand_trust`) |
| 6. Better fit for user profile (when available) | Tiebreaker #2 (`goal_matches` Jaccard when profile is loaded; otherwise 0 for both sides → neutral) |

User-profile fit is wired into the tiebreaker chain as an OPTIONAL
input — the ranker accepts a `userGoals: Set<String>?` that, when
present, prefers candidates whose `goal_matches` overlap with the
user's selected goals. When the user hasn't set goals, this
tiebreaker is neutral and the rest of the chain still applies.

---

## Output contract

`rankAlternatives(currentProduct, candidates, {userGoals, limit: 3})`
returns up to `limit` products in order of best-fit-first. Every
returned product is guaranteed to:

- be on-market
- be strictly higher quality than the current product
- carry no banned-substance / recalled-ingredient flag
- match the current product on **at least one** of: supplement type,
  ingredient family, primary category

Empty list when no candidate clears all hard filters.

---

## Regression test fixtures

The five bad examples above are pinned as fixtures in
`test/services/recommendations/better_alternatives_ranker_test.dart`.
Each test asserts:

1. The legacy buggy recommendation NO LONGER appears in the new
   ranker's output (negative assertion).
2. The new top recommendation passes a sanity property (same
   supplement type OR clear ingredient-family overlap).
3. No off-market product appears in the output.
4. Score is strictly greater than the current product's score.

Pinned product IDs (so the fixtures survive future catalog rebuilds):

| Test | Current dsld_id | Excluded buggy recommendation |
|---|---|---|
| Staminol case | 315814 | 328830 (Basic Prenatal) |
| Vitamin A 8000 IU case | 19170 | 281264 (Kids Multi, discontinued) |
| GNC Probiotic case | 1646 | 15581 (Restore, discontinued) |
| Kids multi case | 178559 | 328830 (Basic Prenatal) |
| Score-tie case | any score-50 multi | any tied 50-score product |

If a future scoring/catalog update changes one of these dsld_ids,
the test will fail loudly — a deliberate trip wire to catch silent
regressions in the recommendation surface.
