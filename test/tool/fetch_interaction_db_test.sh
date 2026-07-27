#!/usr/bin/env bash
#
# Fail-closed tests for tool/fetch_interaction_db.sh validation logic.
# Uses local fixtures — no network. Exercises the `--validate` path, which is
# the same validate_db() the download path runs before activating a file.
#
# Run: bash test/tool/fetch_interaction_db_test.sh
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/tool/fetch_interaction_db.sh"
REAL_DB="$REPO_ROOT/assets/db/interaction_db.sqlite"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }

# expect_exit <expected-nonzero-or-zero> <label> -- <cmd...>
expect() {
  local want="$1" label="$2"; shift 3
  if "$@" >/dev/null 2>&1; then local got=0; else local got=1; fi
  if [ "$got" = "$want" ]; then ok "$label"; else bad "$label (wanted exit-class $want, got $got)"; fi
}

[ -f "$REAL_DB" ] || { echo "prereq: hydrate the DB first (bash tool/fetch_interaction_db.sh)"; exit 2; }

# 1. the real hydrated DB validates
expect 0 "real DB passes --validate" -- bash "$SCRIPT" --validate "$REAL_DB"

# 2. an LFS pointer is rejected (header check)
printf 'version https://git-lfs.github.com/spec/v1\noid sha256:deadbeef\nsize 23269376\n' > "$TMP/pointer.sqlite"
expect 1 "133-byte LFS pointer rejected" -- bash "$SCRIPT" --validate "$TMP/pointer.sqlite"

# 3. a truncated download is rejected (size floor)
head -c 4096 "$REAL_DB" > "$TMP/truncated.sqlite"
expect 1 "truncated file rejected" -- bash "$SCRIPT" --validate "$TMP/truncated.sqlite"

# 4. a real SQLite that is MISSING a Sprint-3 class is rejected (content check,
#    not just header/size) — copy the real DB and drop one required class.
cp "$REAL_DB" "$TMP/wrongcontent.sqlite"
python3 - "$TMP/wrongcontent.sqlite" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("DELETE FROM drug_class_map WHERE class_id = 'class:loop_and_thiazide_diuretics'")
con.commit(); con.close()
PY
expect 1 "valid SQLite missing a required class rejected" -- bash "$SCRIPT" --validate "$TMP/wrongcontent.sqlite"

# 5. a real SQLite where a potassium-sparing agent leaked INTO loop+thiazide is
#    rejected (negative-membership / hazard check).
cp "$REAL_DB" "$TMP/hazard.sqlite"
python3 - "$TMP/hazard.sqlite" <<'PY'
import sqlite3, sys, json
con = sqlite3.connect(sys.argv[1]); con.row_factory = sqlite3.Row
row = con.execute("SELECT drug_rxcuis_json FROM drug_class_map WHERE class_id='class:loop_and_thiazide_diuretics'").fetchone()
m = json.loads(row["drug_rxcuis_json"]); m.append("9997")  # spironolactone
con.execute("UPDATE drug_class_map SET drug_rxcuis_json=? WHERE class_id='class:loop_and_thiazide_diuretics'", (json.dumps(m),))
con.commit(); con.close()
PY
expect 1 "potassium-sparing leak into loop+thiazide rejected" -- bash "$SCRIPT" --validate "$TMP/hazard.sqlite"

# 6. A plausible SQLite that omits the new valproate runtime scope is rejected.
cp "$REAL_DB" "$TMP/missing-valproate.sqlite"
python3 - "$TMP/missing-valproate.sqlite" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("DELETE FROM drug_class_map WHERE class_id = 'class:valproate'")
con.commit(); con.close()
PY
expect 1 "missing valproate class rejected" -- bash "$SCRIPT" --validate "$TMP/missing-valproate.sqlite"

# 7. A valproate form leaking into the enzyme-inducing class is rejected.
cp "$REAL_DB" "$TMP/valproate-leak.sqlite"
python3 - "$TMP/valproate-leak.sqlite" <<'PY'
import sqlite3, sys, json
con = sqlite3.connect(sys.argv[1]); con.row_factory = sqlite3.Row
row = con.execute("SELECT drug_rxcuis_json FROM drug_class_map WHERE class_id='class:enzyme_inducing_antiseizure_medications'").fetchone()
members = json.loads(row["drug_rxcuis_json"]); members.append("40254")
con.execute("UPDATE drug_class_map SET drug_rxcuis_json=? WHERE class_id='class:enzyme_inducing_antiseizure_medications'", (json.dumps(members),))
con.commit(); con.close()
PY
expect 1 "valproate leak into enzyme-inducing class rejected" -- bash "$SCRIPT" --validate "$TMP/valproate-leak.sqlite"

echo
echo "fetch_interaction_db validation: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
