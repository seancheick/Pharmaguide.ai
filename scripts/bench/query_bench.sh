#!/usr/bin/env bash
#
# query_bench.sh — sqlite3 timing harness for PharmaGuide's hot queries.
#
# Benchmarks the EXACT SQL the app runs (copied verbatim from
# lib/data/database/core_database.dart and interaction_database.dart).
# Opens both DBs strictly read-only via the file: URI so the bundled
# assets can never be modified.
#
# Usage:
#   scripts/bench/query_bench.sh [core_db_path] [interaction_db_path]
#
# Defaults:
#   core DB:        assets/db/pharmaguide_core.db
#   interaction DB: assets/db/interaction_db.sqlite
#
# Output per query: EXPLAIN QUERY PLAN + average wall-clock ms over 5 runs
# (timed with sqlite3's .timer inside a single session, so process startup
# is excluded).
#
# NOTE on findByUpc: the app creates an expression index
# idx_core_upc_normalized at open time (_ensureAppIndexes). The bundled
# asset is opened read-only here, so if the snapshot was built without that
# index the plan will show SCAN — that is the true cold-open cost.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORE_DB="${1:-$REPO_ROOT/assets/db/pharmaguide_core.db}"
INTERACTION_DB="${2:-$REPO_ROOT/assets/db/interaction_db.sqlite}"
RUNS=5

for db in "$CORE_DB" "$INTERACTION_DB"; do
  if [[ ! -f "$db" ]]; then
    echo "ERROR: database not found: $db" >&2
    exit 1
  fi
done

ro() { # ro <db> <sql>  — single read-only query, raw output
  sqlite3 "file:$1?mode=ro" "$2"
}

bench() { # bench <name> <db> <sql>
  local name="$1" db="$2" sql="$3"
  echo
  echo "=== $name ==="
  echo "--- EXPLAIN QUERY PLAN ---"
  sqlite3 "file:$db?mode=ro" "EXPLAIN QUERY PLAN $sql" | sed 's/^/    /'
  # 5 timed runs in ONE sqlite3 session (.timer prints: Run Time: real X user Y sys Z)
  local script="" i
  for ((i = 0; i < RUNS; i++)); do
    script+="$sql;"$'\n'
  done
  local avg_ms
  avg_ms=$(printf '.timer on\n.output /dev/null\n%s' "$script" \
    | sqlite3 "file:$db?mode=ro" 2>&1 \
    | awk '/Run Time: real/ {sum += $4; n++} END {if (n) printf "%.3f", (sum / n) * 1000; else print "ERR"}')
  echo "--- avg over $RUNS runs: ${avg_ms} ms ---"
}

echo "PharmaGuide query benchmark"
echo "core DB:        $CORE_DB ($(du -h "$CORE_DB" | cut -f1 | tr -d ' '), $(ro "$CORE_DB" 'SELECT COUNT(*) FROM products_core') products)"
echo "interaction DB: $INTERACTION_DB ($(ro "$INTERACTION_DB" 'SELECT COUNT(*) FROM interactions WHERE retired_at IS NULL') live interactions, $(ro "$INTERACTION_DB" 'SELECT COUNT(*) FROM research_pairs') research pairs)"
echo "sqlite3: $(sqlite3 --version | cut -d' ' -f1-2)"

# ---------------------------------------------------------------------------
# Self-discover sample parameter values so the bench works on any snapshot.
# ---------------------------------------------------------------------------
SAMPLE_UPC=$(ro "$CORE_DB" "SELECT REPLACE(REPLACE(REPLACE(REPLACE(upc_sku, ' ', ''), '-', ''), '.', ''), '/', '') FROM products_core WHERE upc_sku IS NOT NULL AND upc_sku != '' LIMIT 1")
read -r SAMPLE_CAT SAMPLE_TYPE SAMPLE_DSLD SAMPLE_SCORE <<<"$(ro "$CORE_DB" "SELECT primary_category, COALESCE(supplement_type, primary_category), dsld_id, CAST(COALESCE(quality_score_v4_100,0) AS INT) FROM products_core WHERE primary_category IS NOT NULL AND quality_score_v4_100 IS NOT NULL LIMIT 1" | tr '|' ' ')"
SAMPLE_CANON=$(ro "$INTERACTION_DB" "SELECT lower(agent1_canonical_id) FROM interactions WHERE agent1_canonical_id IS NOT NULL AND agent1_canonical_id != '' AND retired_at IS NULL LIMIT 1")
SAMPLE_RXCUI=$(ro "$INTERACTION_DB" "SELECT agent1_id FROM interactions WHERE agent1_type = 'drug' AND retired_at IS NULL LIMIT 1")
SAMPLE_CLASS=$(ro "$INTERACTION_DB" "SELECT agent1_id FROM interactions WHERE agent1_type = 'drug_class' AND retired_at IS NULL LIMIT 1")
read -r PAIR_A1 PAIR_T1 PAIR_A2 PAIR_T2 <<<"$(ro "$INTERACTION_DB" "SELECT agent1_id, agent1_type, agent2_id, agent2_type FROM interactions WHERE retired_at IS NULL AND agent1_id != '' AND agent2_id != '' LIMIT 1" | tr '|' ' ')"
SAMPLE_RP_CANON=$(ro "$INTERACTION_DB" "SELECT lower(canonical_id_a) FROM research_pairs WHERE canonical_id_a IS NOT NULL AND canonical_id_a != '' LIMIT 1")
SAMPLE_RP_RXCUI=$(ro "$INTERACTION_DB" "SELECT rxcui_a FROM research_pairs WHERE rxcui_a IS NOT NULL AND rxcui_a != '' LIMIT 1")

echo
echo "sample params: upc=$SAMPLE_UPC cat=$SAMPLE_CAT type=$SAMPLE_TYPE dsld=$SAMPLE_DSLD score=$SAMPLE_SCORE"
echo "               canonical=$SAMPLE_CANON rxcui=$SAMPLE_RXCUI class=$SAMPLE_CLASS pair=($PAIR_A1/$PAIR_T1 x $PAIR_A2/$PAIR_T2)"
echo "               rp_canonical=$SAMPLE_RP_CANON rp_rxcui=$SAMPLE_RP_RXCUI"

# ---------------------------------------------------------------------------
# (a) findByUpc — REPLACE-chain normalized UPC lookup
#     (core_database.dart findByUpc / upcNormalizeSql)
# ---------------------------------------------------------------------------
bench "(a) findByUpc — REPLACE-chain UPC lookup" "$CORE_DB" "
SELECT * FROM products_core
WHERE REPLACE(REPLACE(REPLACE(REPLACE(upc_sku, ' ', ''), '-', ''), '.', ''), '/', '') = '$SAMPLE_UPC'
ORDER BY (product_status = 'active') DESC,
         COALESCE(quality_score_v4_100, 0) DESC
LIMIT 1"

# ---------------------------------------------------------------------------
# (b) FTS5 search — searchProducts happy path
#     (tokenized, prefix-matched, AND-joined; rank + score ordering)
# ---------------------------------------------------------------------------
bench "(b) FTS5 search via products_fts" "$CORE_DB" "
SELECT p.* FROM products_fts f
JOIN products_core p ON p.rowid = f.rowid
WHERE products_fts MATCH '\"vitamin\"* AND \"d\"*'
ORDER BY rank,
         COALESCE(p.quality_score_v4_100, 0) DESC
LIMIT 50"

# ---------------------------------------------------------------------------
# (c) LIKE fallback — searchProducts degraded path (_likeFallback,
#     3-column form incl. ingredients_text, prefix-only patterns)
# ---------------------------------------------------------------------------
bench "(c) LIKE fallback search" "$CORE_DB" "
SELECT * FROM products_core
WHERE product_name LIKE 'vitamin%' OR brand_name LIKE 'vitamin%' OR ingredients_text LIKE 'vitamin%'
ORDER BY COALESCE(quality_score_v4_100, 0) DESC
LIMIT 50"

# ---------------------------------------------------------------------------
# (d) Better alternatives — BOTH current query forms:
#     d1: legacy findAlternatives (deprecated but still on the class)
#     d2: fetchBetterAlternativesPool (Phase 11.7L.F pool query)
# ---------------------------------------------------------------------------
bench "(d1) better alternatives — legacy findAlternatives" "$CORE_DB" "
SELECT * FROM products_core
WHERE primary_category = '$SAMPLE_CAT'
  AND quality_score_v4_100 >= $SAMPLE_SCORE
  AND NOT (dsld_id = '$SAMPLE_DSLD')
ORDER BY quality_score_v4_100 DESC
LIMIT 5"

bench "(d2) better alternatives — fetchBetterAlternativesPool" "$CORE_DB" "
SELECT * FROM products_core
WHERE (primary_category = '$SAMPLE_CAT' OR supplement_type = '$SAMPLE_TYPE')
  AND quality_score_v4_100 > $SAMPLE_SCORE
  AND NOT (dsld_id = '$SAMPLE_DSLD')
  AND quality_score_status = 'scored'
  AND (discontinued_date IS NULL OR discontinued_date = '')
  AND (has_banned_substance IS NULL OR has_banned_substance = 0)
  AND (has_recalled_ingredient IS NULL OR has_recalled_ingredient = 0)
ORDER BY quality_score_v4_100 DESC
LIMIT 50"

# ---------------------------------------------------------------------------
# (e) Interaction DB lookups (interaction_database.dart)
# ---------------------------------------------------------------------------
bench "(e1) interaction lookupByCanonicalId" "$INTERACTION_DB" "
SELECT *
FROM interactions
WHERE retired_at IS NULL
  AND (
    lower(agent1_canonical_id) = '$SAMPLE_CANON'
    OR lower(agent2_canonical_id) = '$SAMPLE_CANON'
  )"

bench "(e2) interaction lookupByRxcui" "$INTERACTION_DB" "
SELECT * FROM interactions
WHERE ((agent1_type = 'drug' AND agent1_id = '$SAMPLE_RXCUI')
    OR (agent2_type = 'drug' AND agent2_id = '$SAMPLE_RXCUI'))
  AND retired_at IS NULL"

bench "(e3) interaction lookupByDrugClass" "$INTERACTION_DB" "
SELECT * FROM interactions
WHERE (((agent1_type = 'drug_class' AND agent1_id = '$SAMPLE_CLASS')
     OR (agent2_type = 'drug_class' AND agent2_id = '$SAMPLE_CLASS'))
    OR (agent1_drug_class = '$SAMPLE_CLASS' OR agent2_drug_class = '$SAMPLE_CLASS'))
  AND retired_at IS NULL"

bench "(e4) interaction lookupPair (symmetric)" "$INTERACTION_DB" "
SELECT * FROM interactions
WHERE (((agent1_id = '$PAIR_A1' AND agent1_type = '$PAIR_T1' AND agent2_id = '$PAIR_A2' AND agent2_type = '$PAIR_T2')
     OR (agent1_id = '$PAIR_A2' AND agent1_type = '$PAIR_T2' AND agent2_id = '$PAIR_A1' AND agent2_type = '$PAIR_T1')))
  AND retired_at IS NULL"

bench "(e5) research pairs by canonical id" "$INTERACTION_DB" "
SELECT *
FROM research_pairs
WHERE lower(canonical_id_a) = '$SAMPLE_RP_CANON'
   OR lower(canonical_id_b) = '$SAMPLE_RP_CANON'
ORDER BY paper_count DESC,
         clinical_study_count DESC,
         human_study_count DESC,
         latest_paper_year DESC NULLS LAST,
         pair_id ASC
LIMIT 20"

bench "(e6) research pairs by rxcui" "$INTERACTION_DB" "
SELECT *
FROM research_pairs
WHERE rxcui_a = '$SAMPLE_RP_RXCUI'
   OR rxcui_b = '$SAMPLE_RP_RXCUI'
ORDER BY paper_count DESC,
         clinical_study_count DESC,
         human_study_count DESC,
         latest_paper_year DESC NULLS LAST,
         pair_id ASC
LIMIT 20"

echo
echo "done."
