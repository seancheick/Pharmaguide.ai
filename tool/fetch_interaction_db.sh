#!/usr/bin/env bash
#
# fetch_interaction_db.sh — build-time hydration of assets/db/interaction_db.sqlite.
#
# The clinical interaction DB is distributed as a versioned GitHub Release asset
# (NOT Git LFS). This script fetches + VERIFIES it so the app can bundle a real,
# correct SQLite for offline use. It is build-time only: developer setup (when
# the file is missing), CI, and release packaging. The shipped app never
# downloads this database at runtime.
#
# Fail-closed: any integrity or content failure exits nonzero and leaves the
# destination untouched. A truncated download, an LFS pointer, a wrong checksum,
# or a DB missing the Sprint-3 classes must NEVER be activated or packaged.
#
# The pin (tag / url / sha256 / size) lives in tool/interaction_db.release.json —
# the single source of these values, shared with the CI step and the packaging
# guard test. The sha256 is the integrity authority (a release asset can be
# replaced under the same tag).
#
# Usage: bash tool/fetch_interaction_db.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PIN_FILE="$REPO_ROOT/tool/interaction_db.release.json"
DEST="$REPO_ROOT/assets/db/interaction_db.sqlite"

info() { printf '\033[36m[fetch-interaction-db]\033[0m %s\n' "$*"; }
err()  { printf '\033[31m[fetch-interaction-db] ERROR:\033[0m %s\n' "$*" >&2; }

[ -f "$PIN_FILE" ] || { err "pin file missing: $PIN_FILE"; exit 1; }

# --- read the pin (python3 is required; it is also used for DB validation) ---
command -v python3 >/dev/null 2>&1 || { err "python3 is required"; exit 1; }
read -r URL SHA256 SIZE_BYTES MIN_SIZE TAG < <(python3 - "$PIN_FILE" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
print(p["url"], p["sha256"], p["size_bytes"], p["min_size_bytes"], p["tag"])
PY
)

# --- portable sha256 (macOS: shasum, Linux: sha256sum) ---
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# --- content validation: header + size + the Sprint-3 clinical taxonomy ---
# Queries drug_class_map directly. Does NOT rely only on row existence/counts —
# it asserts safety-critical positive AND negative membership.
validate_db() {
  local f="$1"
  # header
  if [ "$(head -c 15 "$f" 2>/dev/null)" != "SQLite format 3" ]; then
    err "not a SQLite database (header mismatch) — likely a truncated download or an LFS pointer"; return 1
  fi
  # size floor
  local bytes; bytes=$(wc -c < "$f" | tr -d ' ')
  if [ "$bytes" -lt "$MIN_SIZE" ]; then err "too small ($bytes < $MIN_SIZE bytes)"; return 1; fi
  # clinical content
  python3 - "$f" <<'PY'
import sqlite3, sys, json
db = sys.argv[1]
con = sqlite3.connect(db); con.row_factory = sqlite3.Row
try:
    rows = {r["class_id"]: set(json.loads(r["drug_rxcuis_json"]))
            for r in con.execute("SELECT class_id, drug_rxcuis_json FROM drug_class_map")}
finally:
    con.close()
REQUIRED = ["class:loop_and_thiazide_diuretics", "class:proton_pump_inhibitors",
            "class:enzyme_inducing_antiseizure_medications", "class:loop_diuretics"]
POS = [("class:loop_and_thiazide_diuretics", "4603", "furosemide"),
       ("class:loop_and_thiazide_diuretics", "5487", "hydrochlorothiazide"),
       ("class:proton_pump_inhibitors", "7646", "omeprazole"),
       ("class:proton_pump_inhibitors", "40790", "pantoprazole"),
       ("class:enzyme_inducing_antiseizure_medications", "8183", "phenytoin"),
       ("class:enzyme_inducing_antiseizure_medications", "2002", "carbamazepine"),
       ("class:loop_diuretics", "4603", "furosemide")]
NEG = [("class:loop_and_thiazide_diuretics", "9997", "spironolactone"),
       ("class:loop_and_thiazide_diuretics", "644", "amiloride"),
       ("class:loop_and_thiazide_diuretics", "298869", "eplerenone"),
       ("class:loop_and_thiazide_diuretics", "10763", "triamterene"),
       ("class:enzyme_inducing_antiseizure_medications", "40254", "valproate"),
       ("class:enzyme_inducing_antiseizure_medications", "32624", "oxcarbazepine"),
       ("class:loop_diuretics", "5487", "hydrochlorothiazide"),
       ("class:loop_diuretics", "9997", "spironolactone")]
errs = []
for cid in REQUIRED:
    if cid not in rows or not rows[cid]:
        errs.append(f"missing/empty class {cid}")
for cid, rx, name in POS:
    if rx not in rows.get(cid, set()):
        errs.append(f"{name} ({rx}) MISSING from {cid}")
for cid, rx, name in NEG:
    if rx in rows.get(cid, set()):
        errs.append(f"{name} ({rx}) PRESENT in {cid} (hazard)")
if errs:
    print("CLINICAL VALIDATION FAILED:", file=sys.stderr)
    for e in errs: print("  -", e, file=sys.stderr)
    sys.exit(1)
print("clinical drug_class_map validated: 3 classes, positive+negative membership OK")
PY
}

# --- optional: validate an existing file and exit (tests / CI guard, no network) ---
if [ "${1:-}" = "--validate" ]; then
  [ -n "${2:-}" ] || { err "--validate requires a file path"; exit 2; }
  [ -f "$2" ] || { err "file not found: $2"; exit 1; }
  validate_db "$2"
  info "validation OK: $2"
  exit 0
fi

# --- 1. up-to-date? skip. ---
if [ -f "$DEST" ] && [ "$(sha256_of "$DEST")" = "$SHA256" ]; then
  info "already up to date (sha256 matches pin) — no download."
  validate_db "$DEST" >/dev/null
  info "local DB re-validated. Done."
  exit 0
fi

info "hydrating $TAG → $DEST"

# --- 2. download to a temp in the SAME dir (so the move is atomic) ---
mkdir -p "$(dirname "$DEST")"
TMP="$(mktemp "$(dirname "$DEST")/.interaction_db.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

downloaded=0
for attempt in 1 2 3; do
  info "download attempt $attempt/3…"
  if curl -fSL --retry 2 --retry-delay 2 --connect-timeout 20 --max-time 300 -o "$TMP" "$URL"; then
    downloaded=1; break
  fi
  err "download attempt $attempt failed"
  sleep $((attempt * 3))
done
[ "$downloaded" -eq 1 ] || { err "could not download after 3 attempts: $URL"; exit 1; }

# --- 3–8. verify sha256, then header/size/clinical content BEFORE activation ---
actual="$(sha256_of "$TMP")"
if [ "$actual" != "$SHA256" ]; then
  err "sha256 mismatch — expected $SHA256, got $actual (rejecting; will not activate)"; exit 1
fi
validate_db "$TMP"

# --- 9. atomic move into place ---
mv -f "$TMP" "$DEST"
trap - EXIT
info "hydrated + verified $DEST (sha256 $SHA256)"
