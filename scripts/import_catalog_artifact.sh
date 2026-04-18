#!/usr/bin/env bash
#
# import_catalog_artifact.sh — copy verified pipeline releases into assets/db/
#
# Usage:
#     scripts/import_catalog_artifact.sh <pipeline_dist_dir>
#
# Where <pipeline_dist_dir> is the output of one or both pipeline release
# scripts:
#     - `release_catalog_artifact.py`     → pharmaguide_core.db + export_manifest.json
#     - `release_interaction_artifact.py` → interaction_db.sqlite + interaction_db_manifest.json
#
# Example:
#     scripts/import_catalog_artifact.sh ../dsld_clean/scripts/dist
#
# The script performs every validation gate locally before it writes
# anything to assets/db/. If any check fails, assets/db/ is left untouched
# and the script exits non-zero with a clear error. A broken pipeline build
# can never replace a good bundled DB.
#
# **Catalog DB is required.** **Interaction DB is optional but validated
# when present** — if interaction_db.sqlite + interaction_db_manifest.json
# are in the same dist dir, they go through their own gate chain and are
# staged atomically alongside the catalog. If any interaction gate fails,
# nothing ships, including the catalog. Both bundles fail or both ship.
#
# ## Catalog DB validation gates (all must pass)
#
# 1. Source dist/ exists and contains both pharmaguide_core.db and
#    export_manifest.json.
# 2. export_manifest.json is valid JSON with required keys:
#      db_version, schema_version, pipeline_version, scoring_version,
#      product_count, min_app_version, checksum_sha256, generated_at.
# 3. schema_version is one of the APP_SUPPORTED_SCHEMAS values below.
# 4. SHA-256 of pharmaguide_core.db matches the manifest's checksum_sha256.
# 5. SQLite opens cleanly and `PRAGMA integrity_check` returns `ok`.
# 6. `SELECT COUNT(*) FROM products_core` returns at least
#    MIN_PRODUCT_COUNT (defaults to 2000; override with --min-products).
# 7. SQLite's internal `export_manifest` table agrees with the JSON manifest
#    on db_version and schema_version (guards against split-brain).
# 8. At least one row in products_core has a non-empty export_version.
#
# ## Interaction DB validation gates (only run if files present)
#
# I1. interaction_db_manifest.json is valid JSON with required keys:
#       built_at, checksum_sha256, schema_version, db_version,
#       total_interactions, source_drafts_count, source_suppai_count,
#       interaction_db_version, pipeline_version, min_app_version.
#     (override_count and resolved_conflict_count live in the embedded
#     interaction_db_metadata kv table only — verified by gate I7.)
# I2. schema_version is in APP_SUPPORTED_INTERACTION_SCHEMAS.
# I3. SHA-256 of interaction_db.sqlite matches manifest's checksum_sha256.
# I4. PRAGMA integrity_check returns 'ok'.
# I5. PRAGMA user_version returns 1 (matches the pipeline's pinned value).
# I6. SELECT COUNT(*) FROM interactions WHERE retired_at IS NULL is at least
#     MIN_INTERACTION_COUNT (defaults to 1; override with --min-interactions).
# I7. The embedded interaction_db_metadata kv table agrees with the JSON
#     manifest on schema_version and total_interactions.
# I8. The embedded sha256_checksum key is **NOT** present (T7 fix —
#     storing the file's hash inside the file would invalidate the hash).
#
# Only after every required gate passes does the script copy files into
# assets/db/ via a staged rename. The previous bundled files (if any) are
# moved aside to *.previous so you can diff or roll back.
#
# ## Flags
#
#     --min-products N      Require at least N catalog rows (default 2000)
#     --min-interactions N  Require at least N live interaction rows (default 1)
#     --allow-schema V      Add catalog schema version V (repeatable)
#     --allow-interaction-schema V
#                           Add interaction schema version V (repeatable)
#     --dry-run             Validate only, do not copy anything
#
# ## Exit codes
#
#     0   success — bundled artifacts updated
#     1   validation failed
#     2   unexpected error (filesystem, permissions, missing tools)
#
# Dependencies: bash, sqlite3, shasum, python3 (for JSON parsing).
# All are standard on macOS and default Linux installs.
#

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

MIN_PRODUCT_COUNT=2000
MIN_INTERACTION_COUNT=1
DRY_RUN=0
DIST_DIR=""

# Schema versions this app is known to understand. When the app adds a new
# column or changes semantics, append here. The bridge refuses to import a
# schema it doesn't recognize, to prevent shipping a DB the app can't read.
APP_SUPPORTED_SCHEMAS=("1.3.1" "1.3.2" "1.4.0")

# Interaction DB schema versions the Flutter Drift wrapper supports. The
# pipeline pins schema_version="1.0.0" / PRAGMA user_version=1 — both must
# match what `lib/data/database/interaction_database.dart` declares.
APP_SUPPORTED_INTERACTION_SCHEMAS=("1.0.0")
APP_SUPPORTED_INTERACTION_USER_VERSION=1

# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-2}"
}

err() {
  printf '\033[31m[import] ERROR:\033[0m %s\n' "$*" >&2
}

info() {
  printf '[import] %s\n' "$*"
}

ok() {
  printf '\033[32m[import] OK:\033[0m %s\n' "$*"
}

while (($# > 0)); do
  case "$1" in
    --min-products)
      MIN_PRODUCT_COUNT="${2:?--min-products requires a value}"
      shift 2
      ;;
    --min-interactions)
      MIN_INTERACTION_COUNT="${2:?--min-interactions requires a value}"
      shift 2
      ;;
    --allow-schema)
      APP_SUPPORTED_SCHEMAS+=("${2:?--allow-schema requires a value}")
      shift 2
      ;;
    --allow-interaction-schema)
      APP_SUPPORTED_INTERACTION_SCHEMAS+=("${2:?--allow-interaction-schema requires a value}")
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    --*)
      err "unknown flag: $1"
      usage 1
      ;;
    *)
      if [[ -z "$DIST_DIR" ]]; then
        DIST_DIR="$1"
      else
        err "unexpected positional argument: $1"
        usage 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$DIST_DIR" ]]; then
  err "missing required argument: pipeline_dist_dir"
  usage 1
fi

# Resolve script and repo root (the bridge always writes relative to the repo
# root, regardless of where the user invokes it from).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_DB_DIR="$REPO_ROOT/assets/db"
TARGET_DB="$ASSETS_DB_DIR/pharmaguide_core.db"
TARGET_MANIFEST="$ASSETS_DB_DIR/export_manifest.json"
TARGET_INTERACTION_DB="$ASSETS_DB_DIR/interaction_db.sqlite"
TARGET_INTERACTION_MANIFEST="$ASSETS_DB_DIR/interaction_db_manifest.json"

DIST_DIR="$(cd "$DIST_DIR" && pwd)"
SRC_DB="$DIST_DIR/pharmaguide_core.db"
SRC_MANIFEST="$DIST_DIR/export_manifest.json"
SRC_INTERACTION_DB="$DIST_DIR/interaction_db.sqlite"
SRC_INTERACTION_MANIFEST="$DIST_DIR/interaction_db_manifest.json"

# The interaction DB is OPTIONAL — old pipeline runs that predate M2 only
# emit catalog artifacts. Detect it once up front; downstream gate and
# staging blocks branch on this flag.
HAS_INTERACTION=0
if [[ -f "$SRC_INTERACTION_DB" || -f "$SRC_INTERACTION_MANIFEST" ]]; then
  # If one is present, both must be — partial interaction artifacts mean
  # the pipeline run was interrupted and we should refuse to proceed.
  [[ -f "$SRC_INTERACTION_DB" ]] || {
    err "found $SRC_INTERACTION_MANIFEST but missing $SRC_INTERACTION_DB"
    exit 1
  }
  [[ -f "$SRC_INTERACTION_MANIFEST" ]] || {
    err "found $SRC_INTERACTION_DB but missing $SRC_INTERACTION_MANIFEST"
    exit 1
  }
  HAS_INTERACTION=1
fi

# ---------------------------------------------------------------------------
# Tool checks
# ---------------------------------------------------------------------------

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    err "required tool '$1' not found on PATH"
    exit 2
  }
}

require_tool sqlite3
require_tool shasum
require_tool python3

# ---------------------------------------------------------------------------
# Source checks
# ---------------------------------------------------------------------------

[[ -f "$SRC_DB" ]] || { err "missing $SRC_DB"; exit 1; }
[[ -f "$SRC_MANIFEST" ]] || { err "missing $SRC_MANIFEST"; exit 1; }
ok "found source artifacts in $DIST_DIR"

# ---------------------------------------------------------------------------
# Manifest parsing (python3 is more reliable than jq availability)
# ---------------------------------------------------------------------------

read_manifest_field() {
  python3 - "$SRC_MANIFEST" "$1" <<'PY'
import json, sys
with open(sys.argv[1]) as fh:
    manifest = json.load(fh)
value = manifest.get(sys.argv[2])
if value is None:
    sys.exit(42)
print(value)
PY
}

# Validate JSON is parseable and required keys are present.
REQUIRED_KEYS=(
  db_version
  schema_version
  pipeline_version
  scoring_version
  product_count
  min_app_version
  checksum_sha256
  generated_at
)

for key in "${REQUIRED_KEYS[@]}"; do
  if ! read_manifest_field "$key" >/dev/null 2>&1; then
    err "manifest missing required key: $key"
    exit 1
  fi
done

DB_VERSION="$(read_manifest_field db_version)"
SCHEMA_VERSION="$(read_manifest_field schema_version)"
PIPELINE_VERSION="$(read_manifest_field pipeline_version)"
SCORING_VERSION="$(read_manifest_field scoring_version)"
PRODUCT_COUNT="$(read_manifest_field product_count)"
MIN_APP_VERSION="$(read_manifest_field min_app_version)"
MANIFEST_CHECKSUM="$(read_manifest_field checksum_sha256)"
GENERATED_AT="$(read_manifest_field generated_at)"

ok "manifest parsed: db_version=$DB_VERSION schema=$SCHEMA_VERSION products=$PRODUCT_COUNT"

# ---------------------------------------------------------------------------
# Gate 1: schema compatibility
# ---------------------------------------------------------------------------

schema_accepted=0
for s in "${APP_SUPPORTED_SCHEMAS[@]}"; do
  if [[ "$s" == "$SCHEMA_VERSION" ]]; then
    schema_accepted=1
    break
  fi
done

if (( schema_accepted == 0 )); then
  err "schema_version '$SCHEMA_VERSION' is not in APP_SUPPORTED_SCHEMAS: ${APP_SUPPORTED_SCHEMAS[*]}"
  err "update APP_SUPPORTED_SCHEMAS in this script, or pass --allow-schema $SCHEMA_VERSION if you're intentionally importing a new schema."
  exit 1
fi
ok "schema_version $SCHEMA_VERSION is supported"

# ---------------------------------------------------------------------------
# Gate 2: SHA-256 match
# ---------------------------------------------------------------------------

ACTUAL_CHECKSUM="$(shasum -a 256 "$SRC_DB" | awk '{print $1}')"
if [[ "$ACTUAL_CHECKSUM" != "$MANIFEST_CHECKSUM" ]]; then
  err "SHA-256 mismatch"
  err "  manifest: $MANIFEST_CHECKSUM"
  err "  actual:   $ACTUAL_CHECKSUM"
  err "the pipeline dist/ is tampered or corrupted. re-run release_catalog_artifact.py"
  exit 1
fi
ok "SHA-256 matches manifest ($ACTUAL_CHECKSUM)"

# ---------------------------------------------------------------------------
# Gate 3: SQLite PRAGMA integrity_check
# ---------------------------------------------------------------------------

INTEGRITY="$(sqlite3 "$SRC_DB" 'PRAGMA integrity_check;' 2>/dev/null || echo "FAILED")"
if [[ "$INTEGRITY" != "ok" ]]; then
  err "SQLite integrity_check returned: $INTEGRITY"
  exit 1
fi
ok "SQLite integrity_check: ok"

# ---------------------------------------------------------------------------
# Gate 4: product count threshold
# ---------------------------------------------------------------------------

ACTUAL_ROW_COUNT="$(sqlite3 "$SRC_DB" 'SELECT COUNT(*) FROM products_core;' 2>/dev/null || echo 0)"
if (( ACTUAL_ROW_COUNT < MIN_PRODUCT_COUNT )); then
  err "products_core has only $ACTUAL_ROW_COUNT rows, minimum is $MIN_PRODUCT_COUNT"
  err "refusing to bundle a partial catalog"
  exit 1
fi
ok "products_core row count: $ACTUAL_ROW_COUNT (min $MIN_PRODUCT_COUNT)"

# ---------------------------------------------------------------------------
# Gate 5: manifest-embedded product_count matches actual row count
# ---------------------------------------------------------------------------

if [[ "$ACTUAL_ROW_COUNT" != "$PRODUCT_COUNT" ]]; then
  err "product_count mismatch between manifest and DB"
  err "  manifest: $PRODUCT_COUNT"
  err "  actual:   $ACTUAL_ROW_COUNT"
  exit 1
fi
ok "product_count agrees between manifest and DB"

# ---------------------------------------------------------------------------
# Gate 6: embedded export_manifest table agrees with JSON manifest
# ---------------------------------------------------------------------------

read_embedded() {
  sqlite3 "$SRC_DB" "SELECT value FROM export_manifest WHERE key='$1';" 2>/dev/null || true
}

EMBEDDED_DB_VERSION="$(read_embedded db_version)"
EMBEDDED_SCHEMA_VERSION="$(read_embedded schema_version)"

if [[ -z "$EMBEDDED_DB_VERSION" || -z "$EMBEDDED_SCHEMA_VERSION" ]]; then
  err "SQLite export_manifest table is missing db_version or schema_version"
  err "this is not a valid pipeline-produced DB"
  exit 1
fi

if [[ "$EMBEDDED_DB_VERSION" != "$DB_VERSION" ]]; then
  err "db_version split-brain between manifest JSON and SQLite table"
  err "  manifest: $DB_VERSION"
  err "  embedded: $EMBEDDED_DB_VERSION"
  exit 1
fi

if [[ "$EMBEDDED_SCHEMA_VERSION" != "$SCHEMA_VERSION" ]]; then
  err "schema_version split-brain between manifest JSON and SQLite table"
  err "  manifest: $SCHEMA_VERSION"
  err "  embedded: $EMBEDDED_SCHEMA_VERSION"
  exit 1
fi
ok "embedded SQLite manifest agrees with JSON manifest"

# ---------------------------------------------------------------------------
# Gate 7: at least one row has a non-empty export_version
# ---------------------------------------------------------------------------

VERSIONED_ROW_COUNT="$(sqlite3 "$SRC_DB" "SELECT COUNT(*) FROM products_core WHERE export_version IS NOT NULL AND export_version != '';" 2>/dev/null || echo 0)"
if (( VERSIONED_ROW_COUNT == 0 )); then
  err "no rows in products_core have a non-empty export_version"
  err "Flutter validateCatalogSnapshot will reject this DB"
  exit 1
fi
ok "$VERSIONED_ROW_COUNT rows have export_version populated"

# ===========================================================================
# Interaction DB validation gates (I1–I8) — only if files are present.
# ===========================================================================

INTERACTION_SCHEMA_VERSION=""
INTERACTION_DB_VERSION=""
INTERACTION_TOTAL=""
INTERACTION_MANIFEST_CHECKSUM=""
INTERACTION_LIVE_COUNT=""

if (( HAS_INTERACTION == 1 )); then
  ok "interaction DB artifacts found — running interaction gate chain"

  # ---------------------------------------------------------------------------
  # Gate I1: interaction manifest is parseable JSON with required keys
  # ---------------------------------------------------------------------------

  read_interaction_manifest_field() {
    python3 - "$SRC_INTERACTION_MANIFEST" "$1" <<'PY'
import json, sys
with open(sys.argv[1]) as fh:
    manifest = json.load(fh)
value = manifest.get(sys.argv[2])
if value is None:
    sys.exit(42)
print(value)
PY
  }

  # Keys the pipeline writes to the JSON manifest (file/transport metadata).
  # Build counters like override_count + resolved_conflict_count live in the
  # embedded interaction_db_metadata kv table inside the SQLite — not the
  # sidecar JSON — and are validated separately at gate I7 via SQL query.
  REQUIRED_INTERACTION_KEYS=(
    built_at
    checksum_sha256
    schema_version
    db_version
    total_interactions
    source_drafts_count
    source_suppai_count
    interaction_db_version
    pipeline_version
    min_app_version
  )

  for key in "${REQUIRED_INTERACTION_KEYS[@]}"; do
    if ! read_interaction_manifest_field "$key" >/dev/null 2>&1; then
      err "interaction manifest missing required key: $key"
      exit 1
    fi
  done

  INTERACTION_SCHEMA_VERSION="$(read_interaction_manifest_field schema_version)"
  INTERACTION_DB_VERSION="$(read_interaction_manifest_field db_version)"
  INTERACTION_TOTAL="$(read_interaction_manifest_field total_interactions)"
  INTERACTION_MANIFEST_CHECKSUM="$(read_interaction_manifest_field checksum_sha256)"
  INTERACTION_PIPELINE_VERSION="$(read_interaction_manifest_field pipeline_version)"
  INTERACTION_BUILT_AT="$(read_interaction_manifest_field built_at)"

  ok "interaction manifest parsed: db_version=$INTERACTION_DB_VERSION schema=$INTERACTION_SCHEMA_VERSION rows=$INTERACTION_TOTAL"

  # ---------------------------------------------------------------------------
  # Gate I2: interaction schema_version is in the supported list
  # ---------------------------------------------------------------------------

  interaction_schema_accepted=0
  for s in "${APP_SUPPORTED_INTERACTION_SCHEMAS[@]}"; do
    if [[ "$s" == "$INTERACTION_SCHEMA_VERSION" ]]; then
      interaction_schema_accepted=1
      break
    fi
  done

  if (( interaction_schema_accepted == 0 )); then
    err "interaction schema_version '$INTERACTION_SCHEMA_VERSION' is not in"
    err "  APP_SUPPORTED_INTERACTION_SCHEMAS: ${APP_SUPPORTED_INTERACTION_SCHEMAS[*]}"
    err "update the Drift wrapper in lib/data/database/interaction_database.dart"
    err "to handle this schema, then add it here, OR pass"
    err "  --allow-interaction-schema $INTERACTION_SCHEMA_VERSION"
    exit 1
  fi
  ok "interaction schema_version $INTERACTION_SCHEMA_VERSION is supported"

  # ---------------------------------------------------------------------------
  # Gate I3: SHA-256 of interaction_db.sqlite matches manifest checksum
  # ---------------------------------------------------------------------------

  ACTUAL_INTERACTION_CHECKSUM="$(shasum -a 256 "$SRC_INTERACTION_DB" | awk '{print $1}')"
  if [[ "$ACTUAL_INTERACTION_CHECKSUM" != "$INTERACTION_MANIFEST_CHECKSUM" ]]; then
    err "interaction DB SHA-256 mismatch"
    err "  manifest: $INTERACTION_MANIFEST_CHECKSUM"
    err "  actual:   $ACTUAL_INTERACTION_CHECKSUM"
    err "the pipeline dist/ is tampered or corrupted. re-run release_interaction_artifact.py"
    exit 1
  fi
  ok "interaction DB SHA-256 matches manifest ($ACTUAL_INTERACTION_CHECKSUM)"

  # ---------------------------------------------------------------------------
  # Gate I4: SQLite PRAGMA integrity_check
  # ---------------------------------------------------------------------------

  INTERACTION_INTEGRITY="$(sqlite3 "$SRC_INTERACTION_DB" 'PRAGMA integrity_check;' 2>/dev/null || echo "FAILED")"
  if [[ "$INTERACTION_INTEGRITY" != "ok" ]]; then
    err "interaction DB SQLite integrity_check returned: $INTERACTION_INTEGRITY"
    exit 1
  fi
  ok "interaction DB SQLite integrity_check: ok"

  # ---------------------------------------------------------------------------
  # Gate I5: PRAGMA user_version matches the pipeline-pinned value
  # ---------------------------------------------------------------------------

  INTERACTION_USER_VERSION="$(sqlite3 "$SRC_INTERACTION_DB" 'PRAGMA user_version;' 2>/dev/null || echo "?")"
  if [[ "$INTERACTION_USER_VERSION" != "$APP_SUPPORTED_INTERACTION_USER_VERSION" ]]; then
    err "interaction DB PRAGMA user_version mismatch"
    err "  expected: $APP_SUPPORTED_INTERACTION_USER_VERSION"
    err "  actual:   $INTERACTION_USER_VERSION"
    err "the pipeline build_interaction_db.py must pin user_version to match"
    err "what the Flutter Drift wrapper declares as schemaVersion."
    exit 1
  fi
  ok "interaction DB PRAGMA user_version: $INTERACTION_USER_VERSION"

  # ---------------------------------------------------------------------------
  # Gate I6: live (non-tombstoned) interactions row count threshold
  # ---------------------------------------------------------------------------

  INTERACTION_LIVE_COUNT="$(sqlite3 "$SRC_INTERACTION_DB" 'SELECT COUNT(*) FROM interactions WHERE retired_at IS NULL;' 2>/dev/null || echo 0)"
  if (( INTERACTION_LIVE_COUNT < MIN_INTERACTION_COUNT )); then
    err "interactions table has only $INTERACTION_LIVE_COUNT live rows,"
    err "  minimum is $MIN_INTERACTION_COUNT"
    err "refusing to bundle an empty interaction DB"
    exit 1
  fi
  ok "interaction DB live row count: $INTERACTION_LIVE_COUNT (min $MIN_INTERACTION_COUNT)"

  # ---------------------------------------------------------------------------
  # Gate I7: embedded interaction_db_metadata kv table agrees with JSON
  # ---------------------------------------------------------------------------

  read_interaction_embedded() {
    sqlite3 "$SRC_INTERACTION_DB" "SELECT value FROM interaction_db_metadata WHERE key='$1';" 2>/dev/null || true
  }

  EMBEDDED_INTERACTION_SCHEMA="$(read_interaction_embedded schema_version)"
  EMBEDDED_INTERACTION_TOTAL="$(read_interaction_embedded total_interactions)"

  if [[ -z "$EMBEDDED_INTERACTION_SCHEMA" || -z "$EMBEDDED_INTERACTION_TOTAL" ]]; then
    err "interaction_db_metadata table is missing schema_version or total_interactions"
    err "this is not a valid release_interaction_artifact.py output"
    exit 1
  fi

  if [[ "$EMBEDDED_INTERACTION_SCHEMA" != "$INTERACTION_SCHEMA_VERSION" ]]; then
    err "interaction schema_version split-brain between manifest JSON and SQLite"
    err "  manifest: $INTERACTION_SCHEMA_VERSION"
    err "  embedded: $EMBEDDED_INTERACTION_SCHEMA"
    exit 1
  fi

  if [[ "$EMBEDDED_INTERACTION_TOTAL" != "$INTERACTION_TOTAL" ]]; then
    err "interaction total_interactions split-brain between manifest JSON and SQLite"
    err "  manifest: $INTERACTION_TOTAL"
    err "  embedded: $EMBEDDED_INTERACTION_TOTAL"
    exit 1
  fi
  ok "embedded interaction_db_metadata agrees with JSON manifest"

  # ---------------------------------------------------------------------------
  # Gate I8: embedded sha256_checksum key MUST be absent (T7 fix)
  # ---------------------------------------------------------------------------
  #
  # Storing the file's own SHA-256 inside the file would change the file's
  # bytes after the hash is computed and invalidate it. The pipeline's
  # release_interaction_artifact.py was patched in T7 to drop this key
  # entirely; if it ever comes back, every checksum check downstream is a
  # lie. Catch the regression here.

  EMBEDDED_INTERACTION_SELF_HASH="$(read_interaction_embedded sha256_checksum)"
  if [[ -n "$EMBEDDED_INTERACTION_SELF_HASH" ]]; then
    err "interaction_db_metadata contains forbidden key 'sha256_checksum' = '$EMBEDDED_INTERACTION_SELF_HASH'"
    err "this is the T7 self-reference bug. The pipeline regressed."
    err "fix scripts/build_interaction_db.py and re-run release_interaction_artifact.py."
    exit 1
  fi
  ok "interaction_db_metadata correctly omits sha256_checksum (T7)"
fi

# ---------------------------------------------------------------------------
# Dry run exit
# ---------------------------------------------------------------------------

if (( DRY_RUN == 1 )); then
  ok "--dry-run: all gates passed, no files written"
  info "would copy:"
  info "  $SRC_DB → $TARGET_DB"
  info "  $SRC_MANIFEST → $TARGET_MANIFEST"
  if (( HAS_INTERACTION == 1 )); then
    info "  $SRC_INTERACTION_DB → $TARGET_INTERACTION_DB"
    info "  $SRC_INTERACTION_MANIFEST → $TARGET_INTERACTION_MANIFEST"
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Staged copy with rollback backup
#
# Catalog and (optional) interaction artifacts are staged together. If any
# stage step fails, all .new files are removed before exit so the live
# bundle stays untouched. Promotion to .previous + atomic rename happens
# only after every staged file passes a re-verification checksum.
# ---------------------------------------------------------------------------

mkdir -p "$ASSETS_DB_DIR"

STAGING_DB="$TARGET_DB.new"
STAGING_MANIFEST="$TARGET_MANIFEST.new"
STAGING_INTERACTION_DB="$TARGET_INTERACTION_DB.new"
STAGING_INTERACTION_MANIFEST="$TARGET_INTERACTION_MANIFEST.new"

cleanup_staging() {
  rm -f "$STAGING_DB" "$STAGING_MANIFEST" \
        "$STAGING_INTERACTION_DB" "$STAGING_INTERACTION_MANIFEST"
}
trap cleanup_staging ERR

cleanup_staging

cp "$SRC_DB" "$STAGING_DB"
cp "$SRC_MANIFEST" "$STAGING_MANIFEST"

# Re-verify the staged catalog copy matches the source checksum. Guards
# against filesystem corruption during copy (rare but possible).
STAGED_CHECKSUM="$(shasum -a 256 "$STAGING_DB" | awk '{print $1}')"
if [[ "$STAGED_CHECKSUM" != "$MANIFEST_CHECKSUM" ]]; then
  err "staged catalog copy checksum mismatch — copy corrupted"
  err "  expected: $MANIFEST_CHECKSUM"
  err "  got:      $STAGED_CHECKSUM"
  cleanup_staging
  exit 2
fi
ok "staged catalog copy checksum re-verified"

if (( HAS_INTERACTION == 1 )); then
  cp "$SRC_INTERACTION_DB" "$STAGING_INTERACTION_DB"
  cp "$SRC_INTERACTION_MANIFEST" "$STAGING_INTERACTION_MANIFEST"

  STAGED_INTERACTION_CHECKSUM="$(shasum -a 256 "$STAGING_INTERACTION_DB" | awk '{print $1}')"
  if [[ "$STAGED_INTERACTION_CHECKSUM" != "$INTERACTION_MANIFEST_CHECKSUM" ]]; then
    err "staged interaction copy checksum mismatch — copy corrupted"
    err "  expected: $INTERACTION_MANIFEST_CHECKSUM"
    err "  got:      $STAGED_INTERACTION_CHECKSUM"
    cleanup_staging
    exit 2
  fi
  ok "staged interaction copy checksum re-verified"
fi

trap - ERR

# Back up the previous bundled artifacts so a botched release can be rolled
# back with a single `mv *.previous *`. Catalog and interaction backups are
# independent — the catalog .previous is touched whether or not we're also
# replacing the interaction bundle.
if [[ -f "$TARGET_DB" ]]; then
  mv "$TARGET_DB" "$TARGET_DB.previous"
  info "previous bundled catalog DB moved to pharmaguide_core.db.previous"
fi
if [[ -f "$TARGET_MANIFEST" ]]; then
  mv "$TARGET_MANIFEST" "$TARGET_MANIFEST.previous"
fi

mv "$STAGING_DB" "$TARGET_DB"
mv "$STAGING_MANIFEST" "$TARGET_MANIFEST"

if (( HAS_INTERACTION == 1 )); then
  if [[ -f "$TARGET_INTERACTION_DB" ]]; then
    mv "$TARGET_INTERACTION_DB" "$TARGET_INTERACTION_DB.previous"
    info "previous bundled interaction DB moved to interaction_db.sqlite.previous"
  fi
  if [[ -f "$TARGET_INTERACTION_MANIFEST" ]]; then
    mv "$TARGET_INTERACTION_MANIFEST" "$TARGET_INTERACTION_MANIFEST.previous"
  fi

  mv "$STAGING_INTERACTION_DB" "$TARGET_INTERACTION_DB"
  mv "$STAGING_INTERACTION_MANIFEST" "$TARGET_INTERACTION_MANIFEST"
fi

ok "bundled artifacts updated:"
info "  $TARGET_DB"
info "  $TARGET_MANIFEST"
if (( HAS_INTERACTION == 1 )); then
  info "  $TARGET_INTERACTION_DB"
  info "  $TARGET_INTERACTION_MANIFEST"
fi
echo
info "Next steps:"
info "  1. Review 'git status' in the Flutter repo — assets/db/ should show"
info "     a modified DB via Git LFS (run 'git lfs ls-files' to confirm)."
info "  2. git add assets/db/"
if (( HAS_INTERACTION == 1 )); then
  info "  3. git commit -m \"chore(catalog): bundle catalog v$DB_VERSION + interaction v$INTERACTION_DB_VERSION ($ACTUAL_ROW_COUNT products, $INTERACTION_LIVE_COUNT interactions)\""
else
  info "  3. git commit -m \"chore(catalog): bundle v$DB_VERSION (schema $SCHEMA_VERSION, $ACTUAL_ROW_COUNT products)\""
fi
info "  4. Delete the .previous backup files once CI is green."
