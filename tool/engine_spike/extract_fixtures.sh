#!/usr/bin/env bash
# Extract ONLY the rows the spike fixture needs from the bundled SQLite DBs.
# Run from the repo root. Requires the gitignored assets/db/interaction_db.sqlite.
# Rows are dumped in rowid order: the app's un-ordered SELECTs scan in rowid
# order, so the fixture-backed shim returns rows in the same order.
set -euo pipefail
OUT=tool/engine_spike/fixtures
IDB=assets/db/interaction_db.sqlite
CDB=assets/db/pharmaguide_core.db
count() { python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$1"; }

# Live interaction rules touching any canonical id in the fixture (candidate +
# stack supplements). Same predicate as InteractionDatabase.lookupByCanonicalId.
sqlite3 -json "$IDB" "
  SELECT * FROM interactions
  WHERE retired_at IS NULL
    AND (lower(agent1_canonical_id) IN ('ginkgo','garlic','fish_oil')
      OR lower(agent2_canonical_id) IN ('ginkgo','garlic','fish_oil'))
  ORDER BY rowid;" > "$OUT/interactions.json"

# drug_class_map is tiny; drugClassesForRxcui scans the whole table.
sqlite3 -json "$IDB" "SELECT * FROM drug_class_map ORDER BY rowid;" > "$OUT/drug_class_map.json"

# products_core rows: candidate (Ginkgo 15699) + stack (Fish Oil 12043, Garlic 12009).
# Only the columns the engine reads.
sqlite3 -json "$CDB" "
  SELECT dsld_id, product_name, key_ingredient_tags, ingredient_fingerprint,
         contains_stimulants, contains_sedatives, contains_blood_thinners,
         mapped_coverage
  FROM products_core WHERE dsld_id IN ('15699','12043','12009') ORDER BY dsld_id;" > "$OUT/products.json"

# Benchmark-only: EVERY live interaction rule. The whole safety ruleset is this
# small; the 25 MB file is research_pairs + FTS, which these checks never read.
sqlite3 -json "$IDB" "SELECT * FROM interactions WHERE retired_at IS NULL ORDER BY rowid;" > "$OUT/interactions_all_live.json"


echo "interactions=$(count $OUT/interactions.json) drug_class_map=$(count $OUT/drug_class_map.json) products=$(count $OUT/products.json) interactions_all_live=$(count $OUT/interactions_all_live.json)"
