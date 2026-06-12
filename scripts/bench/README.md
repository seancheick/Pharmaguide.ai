# PharmaGuide Benchmark Suite

Local SQLite query benchmarks + k6 load tests for the Supabase endpoints.
Nothing here modifies the bundled databases — `query_bench.sh` opens them
strictly read-only, and `synth_inflate.py` only ever works on a copy.

## Contents

| File | Purpose |
|---|---|
| `query_bench.sh` | Times the app's actual hot queries (exact SQL from `lib/data/database/core_database.dart` + `interaction_database.dart`) against the bundled DBs. EXPLAIN QUERY PLAN + avg ms over 5 runs. |
| `synth_inflate.py` | Copies the catalog to a temp path and inflates `products_core` to N rows (default 250,000) with unique synthetic `dsld_id`/`upc_sku`, rebuilds `products_fts`, runs `ANALYZE`. Originals untouched. |
| `k6/` | Supabase load tests (manifest check, blob fetch, catalog OTA download). See `k6/README.md`. |

## Usage

```bash
# Bench the bundled catalogs (defaults)
scripts/bench/query_bench.sh

# Bench a different core DB (e.g. an inflated copy); optional 2nd arg = interaction DB
scripts/bench/query_bench.sh /tmp/pharmaguide_core_synth.db

# Build a 250K-row synthetic catalog copy
python3 scripts/bench/synth_inflate.py
python3 scripts/bench/synth_inflate.py --rows 500000 --out /tmp/pg_500k.db
```

## Baseline — bundled DBs, 2026-06-11

Machine: macOS (Darwin 25.5), sqlite3 3.45.3.
Core DB: 40 MB, 9,270 products. Interaction DB: 21 MB, 148 live interactions, 30,474 research pairs.
Averages over 5 runs (first run includes cold page-cache cost).

| Query | Plan | Avg ms |
|---|---|---|
| (a) findByUpc REPLACE-chain | SCAN products_core + temp B-tree (no `idx_core_upc_normalized` in bundled snapshot — the app builds it at first open) | 22.8 (warm ~10) |
| (b) FTS5 `products_fts` search | SCAN fts virtual table + rowid SEARCH join | 13.0 |
| (c) LIKE fallback (3-col prefix) | SCAN products_core + temp B-tree | 9.8 |
| (d1) findAlternatives (legacy) | SEARCH via `idx_core_primary_category` | 1.0 |
| (d2) fetchBetterAlternativesPool | MULTI-INDEX OR (`idx_core_primary_category` + `idx_core_type`) | 3.0 |
| (e1) interaction lookupByCanonicalId | SCAN interactions (lower() wrapper defeats indexes; only 148 live rows, harmless) | 0.4 |
| (e2) interaction lookupByRxcui | MULTI-INDEX OR (`idx_int_a1_id`/`idx_int_a2_id`) | 0.2 |
| (e3) interaction lookupByDrugClass | MULTI-INDEX OR (4 indexes) | <0.1 |
| (e4) interaction lookupPair | MULTI-INDEX OR (`idx_int_a2_id`) | <0.1 |
| (e5) research pairs by canonical id | SCAN research_pairs + temp B-tree (lower() wrapper, 30K rows) | 9.8 |
| (e6) research pairs by rxcui | MULTI-INDEX OR (`idx_rp_rxcui_a`/`idx_rp_rxcui_b`) | <0.1 |

Notes:
- (a) shows SCAN against the *bundled* snapshot because the
  `idx_core_upc_normalized` expression index is created app-side at first
  open (`_ensureAppIndexes`). Re-run against an opened/inflated copy to see
  the SEARCH plan.
- (e1)/(e5) full-scan because of the `lower(...)` wrappers; cheap today,
  worth expression indexes if `research_pairs` keeps growing.
- Re-run after `synth_inflate.py` to see 250K-row behavior before the
  catalog actually grows.

## k6 load tests

See `k6/README.md`. **Warning: k6 runs against Supabase consume real
egress and API quota — use staging or off-peak.** Secrets are referenced by
env var name only (`SUPABASE_URL`, `SUPABASE_ANON_KEY`); never paste values.
