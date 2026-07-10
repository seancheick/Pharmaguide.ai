# Flutter Data Contract v2

> Version: 2.0.0 — 2026-06-09
> Scope: how the Flutter app reads the V4 pipeline export.
> Canonical pipeline contract: `FINAL_EXPORT_SCHEMA_V1.md` / export schema `2.0.0`.

App persistence layout:

- `pharmaguide_core.db` — bundled/read-only reference DB from the pipeline export.
- `user_data.db` — local read/write DB for `product_detail_cache`, `user_profile`,
  `user_scan_history`, `user_stacks_local`, and `user_favorites`.

No health profile, medication, condition, allergy, or FitScore data is sent to
Supabase. Signed-in users may sync supplement-only stack rows for account
continuity; medication rows never sync. FitScore is computed fresh on-device
from the loaded profile.

## Production Score Contract

Flutter must use the V4 score fields exported by schema `2.0.0`:

```dart
class ProductQualityScore {
  final double? qualityScoreV4_100;
  final String qualityScoreStatus; // scored | suppressed_safety | not_scored
  final String? qualityTier;       // Elite/Excellent/Strong/Acceptable/Weak/Poor
  final String scoreModelVersion;  // "v4"
}
```

Rules:

- `quality_score_v4_100` is the only shipped quality score.
- `score_100_equivalent` and `score_display_100_equivalent` are compatibility
  mirrors of the same V4 score.
- `raw_score_v4_100` is audit/debug only. Do not show it when
  `quality_score_status != "scored"`.
- `score_quality_80` and `score_display_80` were dropped from export schema
  `2.0.0`. Do not query, sort, or display them.
- Product ranking and UPC tie-breaking use `quality_score_v4_100 DESC` with nulls
  last, after active product status.

## Scan Card

Source: `products_core` from local SQLite.

Required fields:

```sql
SELECT dsld_id, product_name, brand_name, image_url, image_is_pdf,
       thumbnail_key, detail_blob_sha256,
       interaction_summary_hint, decision_highlights,
       product_status, discontinued_date, form_factor, supplement_type,
       quality_score_v4_100, quality_score_status, quality_tier,
       quality_score_suppressed_reason, score_model_version,
       score_display_100_equivalent, score_100_equivalent,
       grade, verdict, safety_verdict,
       percentile_top_pct, percentile_label,
       badges, top_warnings, cert_programs,
       has_banned_substance, has_recalled_ingredient,
       has_harmful_additives, has_allergen_risks, blocking_reason
FROM products_core
WHERE upc_sku = ?
ORDER BY CASE product_status WHEN 'active' THEN 0 ELSE 1 END,
         CASE quality_score_status WHEN 'scored' THEN 0 ELSE 1 END,
         quality_score_v4_100 DESC,
         dsld_id
LIMIT 1;
```

Display behavior:

- If `quality_score_status == "scored"`, show `quality_score_v4_100`.
- If `quality_score_status == "suppressed_safety"`, show the safety verdict and
  suppression reason, not the audit score.
- If `quality_score_status == "not_scored"`, show an unavailable-score state, not
  zero.
- Use `verdict` and `top_warnings` for safety messaging; the quality score never
  overrides BLOCKED/UNSAFE/CAUTION copy.

## Product Page

Source: `products_core` for instant header, then `product_detail_cache` or remote
detail blob for full detail.

The header reads:

- identity and image fields from `products_core`
- V4 score fields above
- compliance booleans
- `mapped_coverage`
- `key_ingredient_tags`
- `decision_highlights`

The detail blob reads:

- `quality_pillars_v4` — canonical six-pillar detail surface
- `v4_score_explanation`
- `v4_score_provenance`
- `v4_safety_gate`
- `v4_completeness_gate`
- `rda_ul_data`
- centralized nutrient/health intelligence fields consumed by stack/FitScore
- interaction, condition, medication, allergen, warning, certification, and
  formulation details

Legacy `section_breakdown` can still exist in blobs for audit/history. Do not use
it as the production quality-score source.

## Search And Lists

Product search, recommendations, and category lists sort by V4:

```sql
ORDER BY CASE quality_score_status WHEN 'scored' THEN 0 ELSE 1 END,
         quality_score_v4_100 DESC,
         product_name COLLATE NOCASE ASC
```

Filtering examples:

```sql
-- Products 70+/100 on the V4 contract.
WHERE quality_score_status = 'scored'
  AND quality_score_v4_100 >= 70
ORDER BY quality_score_v4_100 DESC;
```

Never write `/80` thresholds such as `score_quality_80 > 56`.

## Detail Payload Resolution

`products_core.detail_blob_sha256` is the primary runtime key:

```text
shared/details/sha256/{blob_sha256[0:2]}/{blob_sha256}.json
```

`detail_index.json` is compatibility/audit tooling only. New Flutter flows should
derive the path from `detail_blob_sha256`.

## FitScore And Personalization

FitScore is on-device only:

- Wait for the loaded profile provider before computing personalized safety or fit.
- Use the centralized nutrient/health intelligence services instead of reparsing
  detail blobs screen-by-screen.
- RDA/UL, medication, condition, allergy, and goal logic must use the same
  normalized pipeline identifiers consumed by stack health.
- EPA/DHA must not be compared against ALA RDA. Unknown units/forms should be
  skipped rather than coerced.

## Reference Data

The app consumes pipeline-exported reference data for local computation:

| Key | Purpose |
|---|---|
| `rda_optimal_uls` | Age/sex/pregnancy/lactation RDA/AI/UL checks |
| `interaction_rules` | Ingredient-condition and ingredient-medication safety |
| `clinical_risk_taxonomy` | Severity and condition taxonomy |
| `user_goals_clusters` | Goal matching |

## Hard Rules

- Never display `safe` when `mapped_coverage < 0.3`.
- Never persist FitScore.
- Never show `raw_score_v4_100` to users as the product score.
- Never query dropped V3 fields (`score_quality_80`, `score_display_80`).
- Null score means unavailable or safety-suppressed, not zero.
