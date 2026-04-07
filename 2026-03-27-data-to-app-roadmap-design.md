# PharmaGuide: Data Enrichment to Application Development Roadmap

**Version:** 1.0.1
**Date:** 2026-04-02
**Aligned with:** PharmaGuide Flutter MVP Spec v5.3 (Pipeline Contract Aligned)
**Architecture:** Approach A — SQLite-Core + Supabase-Detail (Hybrid Offline+Online)

---

## Context

PharmaGuide has a mature 3-stage data pipeline (Clean -> Enrich -> Score) producing:

- `pharmaguide_core.db` (SQLite, 65 columns, ~180K products)
- `detail_blobs/{dsld_id}.json` (local build output) plus `detail_index.json` for compatibility/audit; runtime can prefer `products_core.detail_blob_sha256`
- `export_manifest.json` (version metadata)

This roadmap covers the transition from data pipeline to production Flutter app via Supabase distribution.

### Architectural Decision

**Approach A selected:** Bundle `products_core` SQLite with the app. Store detail blobs in Supabase Storage. App fetches detail JSON on-demand and caches locally.

Rationale:

- Already designed this way (CLAUDE.md: "offline-first architecture: phone loads from local SQLite cache first, hydrates from Supabase on cache miss")
- Data changes weekly (FDA sync + audits) — no need for real-time subscriptions or delta patches
- `build_final_db.py` already outputs exactly what's needed
- Single distribution mechanism: Supabase Storage for both `.db` file and detail blobs
- `export_manifest` table in Supabase DB tracks versions

Alternatives deferred:

- Approach B (Full PostgreSQL): v2 consideration if server-side search, user reviews, or multi-device sync needed
- Approach C (Edge Functions + Deltas): Only if >100K products and bandwidth becomes a cost concern

---

## Phase 1: Data Finalization and Schema Mapping

### 1.1 Data Readiness

Data is treated as ready. The pipeline audit is complete for the initial product set. Key stats:

- harmful_additives.json: 115 entries, schema v5.1.0, all tests passing
- banned_recalled_ingredients.json: 143 entries, FDA sync active
- ingredient_quality_map.json: 563 parents, all stubs resolved
- Total test suite: 3065 tests passing

### 1.2 Schema Mapping (JSON to Supabase)

No relational schema mapping is required for pipeline data. `build_final_db.py` already produces the correct output format. The mapping is:

| Pipeline Output               | Supabase Location                                                                            |
| ----------------------------- | -------------------------------------------------------------------------------------------- |
| `pharmaguide_core.db`         | `supabase-storage://pharmaguide/v{version}/pharmaguide_core.db`                              |
| `detail_index.json`           | `supabase-storage://pharmaguide/v{version}/detail_index.json`                                |
| `detail_blobs/{dsld_id}.json` | `supabase-storage://pharmaguide/shared/details/sha256/{blob_sha256[0:2]}/{blob_sha256}.json` |
| `export_manifest.json`        | PostgreSQL `export_manifest` table (single current row)                                      |

### 1.3 Identifiers in Detail Blobs

Every ingredient and warning entry in detail blobs now carries an `identifiers` field:

- Compact format, non-null fields only: `{"cui": "C0042839", "cas": "149-32-6", "pubchem_cid": 222285, "unii": "RA96B954X6"}`
- Sources: IQM (active ingredients), harmful_additives + other_ingredients (inactive), banned_recalled (warnings)
- Strategy: Lookup at export time in `build_final_db.py` from source data files (not enricher)
- Benefit: Identifiers stay current with each export; audit fixes propagate automatically

### 1.4 What Does NOT Go to Supabase

The 33 reference databases (IQM, harmful_additives, allergens, etc.) are consumed during pipeline enrichment. Their effects are baked into:

- `products_core` columns (scores, flags, verdicts)
- Detail blob sections (warnings, scoring breakdowns, clinical links)
- Reference data tables bundled in the SQLite (for on-device scoring)

---

## Phase 2: Backend Synchronization Strategy

### 2.1 Supabase Project Setup

#### PostgreSQL Tables (4 total)

```sql
-- Pipeline distribution
CREATE TABLE export_manifest (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  db_version       text NOT NULL,
  pipeline_version text NOT NULL,
  scoring_version  text NOT NULL,
  schema_version   text NOT NULL,
  product_count    integer NOT NULL,
  checksum         text NOT NULL,
  min_app_version  text NOT NULL DEFAULT '1.0.0',
  generated_at     timestamptz NOT NULL,
  created_at       timestamptz DEFAULT now(),
  is_current       boolean DEFAULT true
);

-- User-facing (app writes)
CREATE TABLE user_stacks (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid REFERENCES auth.users NOT NULL,
  dsld_id      text NOT NULL,
  dosage       text,
  timing       text,
  supply_count integer,
  source_device_id text,
  client_updated_at timestamptz,
  deleted_at timestamptz,
  added_at     timestamptz DEFAULT now(),
  updated_at   timestamptz DEFAULT now()
);

CREATE TABLE user_usage (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid REFERENCES auth.users NOT NULL,
  scans_today       integer DEFAULT 0,
  ai_messages_today integer DEFAULT 0,
  reset_day_utc     date DEFAULT ((now() AT TIME ZONE 'UTC')::date)
);

CREATE TABLE pending_products (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid REFERENCES auth.users NOT NULL,
  upc            text NOT NULL,
  normalized_upc text,
  product_name   text,
  brand          text,
  image_url      text,
  submitter_note text,
  status         text DEFAULT 'pending',
  review_notes   text,
  reviewed_at    timestamptz,
  reviewed_by    text,
  submitted_at   timestamptz DEFAULT now()
);

-- Indexes
CREATE INDEX idx_user_stacks_user ON user_stacks(user_id);
CREATE INDEX idx_user_usage_user ON user_usage(user_id);
CREATE UNIQUE INDEX idx_user_usage_daily ON user_usage(user_id, reset_day_utc);
CREATE INDEX idx_pending_products_user ON pending_products(user_id);
CREATE UNIQUE INDEX idx_pending_products_user_normalized_upc_pending
  ON pending_products(user_id, normalized_upc)
  WHERE status = 'pending' AND normalized_upc IS NOT NULL;

-- Partial index: only is_current=true rows (one row, queried every app launch)
CREATE INDEX idx_export_manifest_current ON export_manifest(is_current) WHERE is_current = true;
```

The unique index on `user_usage(user_id, reset_day_utc)` prevents duplicate rows per UTC day, which is critical for accurate scan/AI message limit enforcement. The partial index on `export_manifest(is_current)` keeps version checks fast as the table grows.

#### RLS Policies

```sql
-- export_manifest: anyone can read, only service role can write
ALTER TABLE export_manifest ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read" ON export_manifest FOR SELECT USING (true);

-- user_stacks: users own their rows
ALTER TABLE user_stacks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own stacks" ON user_stacks
  FOR ALL USING (auth.uid() = user_id);

-- user_usage: users read their counters; writes go through increment_usage
ALTER TABLE user_usage ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own usage" ON user_usage
  FOR SELECT USING (auth.uid() = user_id);

-- pending_products: users submit and view their requests; status is server-owned
ALTER TABLE pending_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own submissions" ON pending_products
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users submit pending products" ON pending_products
  FOR INSERT WITH CHECK (auth.uid() = user_id);
```

#### RPC Functions (2 total)

```sql
-- 1. Atomic manifest rotation.
-- The SQL function owns the update/insert order, but callers treat it as one transaction.
CREATE OR REPLACE FUNCTION rotate_manifest(
  p_db_version text,
  p_pipeline_version text,
  p_scoring_version text,
  p_schema_version text,
  p_product_count integer,
  p_checksum text,
  p_generated_at timestamptz,
  p_min_app_version text DEFAULT '1.0.0'
) RETURNS uuid AS $$
DECLARE
  new_id uuid;
BEGIN
  INSERT INTO export_manifest (
    db_version, pipeline_version, scoring_version, schema_version,
    product_count, checksum, min_app_version, generated_at, is_current
  ) VALUES (
    p_db_version, p_pipeline_version, p_scoring_version, p_schema_version,
    p_product_count, p_checksum, p_min_app_version, p_generated_at, true
  ) RETURNING id INTO new_id;

  UPDATE export_manifest
  SET is_current = false
  WHERE is_current = true AND id != new_id;

  RETURN new_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Atomic usage increment with UTC day rollover.
-- Flutter reads the returned object and blocks when limit_exceeded=true.
CREATE OR REPLACE FUNCTION increment_usage(
  p_user_id uuid, p_type text  -- 'scan' or 'ai_message'
) RETURNS jsonb AS $$
DECLARE
  v_usage user_usage%ROWTYPE;
  v_scans integer := 0;
  v_ai integer := 0;
  v_exceeded boolean := false;
BEGIN
  INSERT INTO user_usage (user_id, scans_today, ai_messages_today, reset_day_utc)
  VALUES (p_user_id, 0, 0, (now() AT TIME ZONE 'UTC')::date)
  ON CONFLICT (user_id, reset_day_utc) DO NOTHING;

  SELECT * INTO v_usage
  FROM user_usage
  WHERE user_id = p_user_id AND reset_day_utc = (now() AT TIME ZONE 'UTC')::date
  FOR UPDATE;

  IF p_type = 'scan' AND v_usage.scans_today >= 20 THEN
    v_exceeded := true;
  ELSIF p_type = 'ai_message' AND v_usage.ai_messages_today >= 5 THEN
    v_exceeded := true;
  ELSE
    UPDATE user_usage
    SET
      scans_today = CASE WHEN p_type = 'scan' THEN scans_today + 1 ELSE scans_today END,
      ai_messages_today = CASE WHEN p_type = 'ai_message' THEN ai_messages_today + 1 ELSE ai_messages_today END
    WHERE id = v_usage.id
    RETURNING scans_today, ai_messages_today INTO v_scans, v_ai;
  END IF;

  IF v_exceeded THEN
    v_scans := v_usage.scans_today;
    v_ai := v_usage.ai_messages_today;
  END IF;

  RETURN jsonb_build_object(
    'scans_today', v_scans,
    'ai_messages_today', v_ai,
    'limit_exceeded', v_exceeded
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

#### Storage

- Bucket: `pharmaguide` (public read via anon key, write via service role)
- Structure: `v{version}/pharmaguide_core.db`, `v{version}/detail_index.json`, `shared/details/sha256/{blob_sha256[0:2]}/{blob_sha256}.json`

### 2.2 Manual Sync Script (Start Here)

New script: `scripts/sync_to_supabase.py`

```
python scripts/sync_to_supabase.py <build_output_dir>
```

Workflow:

1. Read `export_manifest.json` from build output
2. Compare version to Supabase `export_manifest` where `is_current = true`
3. If newer: upload `pharmaguide_core.db` to Storage bucket
4. Upload `detail_index.json`, then upload only missing hashed detail blobs to Storage
5. Call `rotate_manifest` RPC to atomically insert new row and mark previous as not current (no window where zero rows are current)
6. Print summary: version, product count, blob count, upload duration

The remote `checksum` is for artifact verification after upload/download. The
local on-device SQLite manifest only needs `db_version`; it does not embed a
self-referential checksum row.

Auth: Supabase service role key from `.env` (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`). Never the anon key.

### 2.3 CI/CD Pipeline (Later, When Stable)

GitHub Action on merge to `main`:

1. Run full pipeline (clean -> enrich -> score -> build_final_db)
2. Run test suite (must pass)
3. Run `sync_to_supabase.py` with service role key from GitHub Secrets
4. Post notification with version + product count

Why manual first: Still auditing data. Manual gives inspection control before production push. CI/CD automates once pipeline output is trusted.

---

## Phase 3: Flutter Data Consumption Architecture

### 3.1 Two-Layer Data Model (From Spec v5.3)

**Layer 1 -- Local SQLite (`pharmaguide_core.db` and `user_data.db`):**

- **Reference DB (`pharmaguide_core.db`)**: Ships bundled with the app. Contains `products_core` (~180K products), `products_fts`, `reference_data`, `export_manifest`. Read-only, overwritten OTA during updates.
- **User DB (`user_data.db`)**: Created on first launch. Contains `user_profile`, `user_stacks_local`, `user_favorites`, etc. Read-write, never overwritten.
- Instant offline access for scan lookups and search.
- Reference DB updated in background using a background downloader when pipeline produces a new export version.

**Layer 2 -- Supabase (Remote):**

- Detail blobs: one JSON per product, fetched on first product view, cached locally in `product_detail_cache`
- User data: Supabase Auth + `user_stacks` + `user_usage` + `pending_products`
- AI proxy: Supabase Edge Function wrapping Gemini 2.5 Flash-Lite
- DB version check: app reads `export_manifest` on launch, compares to Supabase

### 3.2 Source of Truth Flow

```
Pipeline repo (Git)
  -> build_final_db.py
  -> sync_to_supabase.py
  -> Supabase Storage (versioned .db + detail blobs)
      |
App launch:
  1. Read local export_manifest from bundled SQLite
  2. If online: check Supabase export_manifest for newer version
  3. If newer: background-download new `.db` file via native OS downloader, atomically swap in when complete (leaving `user_data.db` untouched)
  4. Never block the user during update
      |
Product scan:
  1. Query products_core (local SQLite, async to prevent UI block) -- instant header + score
  2. Check product_detail_cache for dsld_id
  3. If cached + version matches: render from cache
  4. If not cached + online: read `products_core.detail_blob_sha256`, derive the hashed detail path, fetch the payload from Supabase -> cache -> render
  5. Fall back to versioned `detail_index.json` only if the row-level hash is missing
  5. If not cached + offline: show header only, "Detail unavailable offline" banner
```

### 3.3 Bundle Size

- 180K products x ~500 bytes/row = ~90MB SQLite file (compressed in app bundle)
- Reference data: ~313KB total (parsed once at startup, held in memory)
- Detail blobs: fetched on-demand (only viewed products)

### 3.4 When Pipeline Re-runs

Run `sync_to_supabase.py` after pipeline execution. New version appears in Supabase. Apps detect on next launch. Background download. Seamless update. No user action required.

---

## Phase 4: Frontend Implementation of Enriched Data

### 4.1 Clinical Data Display Mapping

| Pipeline Field            | Flutter UI Location                   | Display Format                                                                  |
| ------------------------- | ------------------------------------- | ------------------------------------------------------------------------------- |
| `mechanism_of_harm`       | Card 2 (Safety) harmful additive rows | Red row: "[Additive] -- [mechanism text]"                                       |
| `population_warnings`     | Card 2 below mechanism                | Em-dash formatted: "Pregnant women -- Children -- Immunocompromised"            |
| `notes`                   | Card 2 additive/ingredient detail     | Grey caption below mechanism                                                    |
| `evidence_level`          | Card 3 interaction warnings           | Chip: "Established" / "Probable" / "Theoretical"                                |
| `doseThresholdEvaluation` | Card 3 below action text              | Muted info box with dose context                                                |
| `clinical_matches`        | Card 3 evidence section               | Study badges: RCT (dark blue), Systematic Review (purple), Meta-Analysis (teal) |
| `interaction_summary`     | Condition Alert Banner                | Orange banner above cards with condition names + severity                       |
| `score_bonuses`           | Pros section                          | Green rows with type badge + source                                             |
| `score_penalties`         | Considerations section                | Red/yellow rows with severity badge + mechanism                                 |
| `identifiers`             | Not displayed to users in MVP         | Data integrity field; future "Sources" deep-dive                                |

### 4.2 Identifier Strategy

CUI, CAS, PubChem, UNII are data integrity tools:

- Ensure pipeline matches the correct substance during enrichment
- Ensure `interaction_summary` condition/drug mappings are accurate
- Available in detail blobs for future "Sources" or "Learn More" deep-dive screen
- NOT displayed directly to consumers in MVP (too technical)

### 4.3 Implementation Notes (From Spec v5.3)

- Export field is `notes` on both active and inactive ingredients, and `mechanism_of_harm` on harmful additive entries
- The older Flutter spec referenced `reference_notes` in one place, but the actual detail blob field is `notes`. **The export wins** -- it's the frozen pipeline contract, validated by tests. Do NOT add a `@JsonKey` rename in Flutter to paper over this -- that creates a hidden translation layer
- Warnings use sealed class hierarchy: `BannedSubstanceWarning`, `HarmfulAdditiveWarning`, `AllergenWarning`, `InteractionWarning`, `DrugInteractionWarning`, `DietaryWarning`, `StatusWarning`
- `score_quality_80` can be NULL: every display path needs null guard, never show 0
- Condition/drug chips MUST map exactly to `condition_id`/`drug_class_id` from pipeline taxonomy
- Parse reference_data JSON ONCE at startup, hold in memory via singleton provider
- Use drift (NOT raw sqflite) for compile-time type safety on medical data
- Validate the clinical risk taxonomy at startup via a dedicated service/provider so condition and drug-class chips cannot silently drift from pipeline IDs.
- Use a consistent local form-state strategy for Profile and Stack edit flows (`flutter_hooks` + `Form`/validators, or an equivalent explicit pattern). Do not let each screen invent its own form state management.
- Search needs “latest query wins” behavior in addition to the 300ms debounce. A slower older query must never overwrite a newer result set in the UI.
- Add parser smoke tests before UI work starts: one SAFE product, one BLOCKED/B0 product, one NOT_SCORED product, one PDF image URL, and one interaction_summary payload from real export fixtures.

---

## Phase 5: Documentation and Path Alignment

### 5.1 Documents to Update

| Document                    | Action                                           |
| --------------------------- | ------------------------------------------------ |
| `CLAUDE.md`                 | Add `sync_to_supabase.py` to Commands table      |
| `PIPELINE_ARCHITECTURE.md`  | Add Stage 4 (Sync/Distribution) section          |
| `DATABASE_SCHEMA.md`        | Add Supabase schema section (4 tables + Storage) |
| `FINAL_EXPORT_SCHEMA_V1.md` | Add Supabase Storage paths and versioning        |

### 5.2 New Documentation

One new file: `scripts/SUPABASE_SYNC_README.md`

- Supabase project setup instructions (tables, RLS, storage bucket)
- `sync_to_supabase.py` usage guide
- Environment variables: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- Troubleshooting: version conflicts, partial uploads, rollback procedures

### 5.3 Documents That Do NOT Need Changes

- **PharmaGuide Flutter MVP Spec v5.3** -- Already complete and pipeline-contract-aligned
- **SCORING_ENGINE_SPEC.md** -- Scoring logic unchanged by Supabase integration
- **Data file schemas** -- Already documented in DATABASE_SCHEMA.md
- **API audit tools** -- Unaffected by distribution layer

---

## Implementation Order

The spec already defines a 7-week Flutter build schedule. This roadmap's phases map to the spec's timeline:

| Roadmap Phase                          | When                       | Dependency                                                  |
| -------------------------------------- | -------------------------- | ----------------------------------------------------------- |
| Phase 1 (Data Finalization)            | Done                       | Pipeline audit complete, identifiers added to export        |
| Phase 2 (Supabase Setup + Sync Script) | Before Flutter Phase 1     | Needed for Flutter to have a Supabase project to connect to |
| Phase 3 (Flutter Data Architecture)    | Flutter Phase 1 (Week 1-2) | drift setup, SQLite bundling, Supabase client init          |
| Phase 4 (Clinical Data UI)             | Flutter Phase 2 (Week 2-4) | 5 pillar smart cards, sealed class warnings                 |
| Phase 5 (Documentation)                | Concurrent with Phase 2    | Can be done alongside Supabase setup                        |

### Critical Path

1. Create Supabase project + run schema SQL
2. Write and test `sync_to_supabase.py`
3. Push first export to Supabase
4. **Supabase connectivity gate:** Verify the Flutter dev can read the manifest table and download a detail blob via anon key before starting Flutter networking code. Without this gate, the entire data layer could be built against mocked data and break on real Supabase access.
5. Begin Flutter Phase 1 with real Supabase credentials

### Future Enhancements (Do Not Build Now)

- **Concurrent uploads:** `concurrent.futures.ThreadPoolExecutor` for >10K products. Sequential is fine for MVP.
- **CI/CD pipeline:** GitHub Action on merge to main. Build after manual workflow is trusted.

### Seed Data Requirement (From Spec)

> products_core must have at least 100 products with fully populated breakdown JSON before Phase 2 scan testing can begin.

This is satisfied by the current pipeline output (5K-50K products ready).
