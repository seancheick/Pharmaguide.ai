#!/usr/bin/env bash
#
# import_catalog_artifact.sh — copy a verified pipeline release into assets/db/
#
# Usage:
#     scripts/import_catalog_artifact.sh <pipeline_dist_dir>
#
# Where <pipeline_dist_dir> is the output of the pipeline's
# `release_catalog_artifact.py`, e.g.:
#     scripts/import_catalog_artifact.sh ../dsld_clean/scripts/dist
#
# The script performs every validation gate locally before it writes
# anything to assets/db/. If any check fails, assets/db/ is left untouched
# and the script exits non-zero with a clear error. A broken pipeline build
# can never replace a good bundled DB.
#
# ## Validation gates (all must pass)
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
# Only after all eight gates pass does the script copy the DB and manifest
# into assets/db/ via a staged rename. The previous bundled DB (if any) is
# moved aside to assets/db/pharmaguide_core.db.previous so you can diff or
# roll back.
#
# ## Flags
#
#     --min-products N    Require at least N rows (default 2000)
#     --allow-schema V    Add schema version V to the accepted list (repeatable)
#     --dry-run           Validate only, do not copy anything
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
DRY_RUN=0
DIST_DIR=""

# Schema versions this app is known to understand. When the app adds a new
# column or changes semantics, append here. The bridge refuses to import a
# schema it doesn't recognize, to prevent shipping a DB the app can't read.
APP_SUPPORTED_SCHEMAS=("1.3.1" "1.3.2")

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
    --allow-schema)
      APP_SUPPORTED_SCHEMAS+=("${2:?--allow-schema requires a value}")
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

DIST_DIR="$(cd "$DIST_DIR" && pwd)"
SRC_DB="$DIST_DIR/pharmaguide_core.db"
SRC_MANIFEST="$DIST_DIR/export_manifest.json"

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

# ---------------------------------------------------------------------------
# Dry run exit
# ---------------------------------------------------------------------------

if (( DRY_RUN == 1 )); then
  ok "--dry-run: all gates passed, no files written"
  info "would copy:"
  info "  $SRC_DB → $TARGET_DB"
  info "  $SRC_MANIFEST → $TARGET_MANIFEST"
  exit 0
fi

# ---------------------------------------------------------------------------
# Staged copy with rollback backup
# ---------------------------------------------------------------------------

mkdir -p "$ASSETS_DB_DIR"

# Copy to .new siblings first, then atomic mv. If anything explodes mid-copy,
# the existing bundled files are untouched.
STAGING_DB="$TARGET_DB.new"
STAGING_MANIFEST="$TARGET_MANIFEST.new"
rm -f "$STAGING_DB" "$STAGING_MANIFEST"

cp "$SRC_DB" "$STAGING_DB"
cp "$SRC_MANIFEST" "$STAGING_MANIFEST"

# Re-verify the staged copy matches the source checksum. Guards against
# filesystem corruption during copy (rare but possible).
STAGED_CHECKSUM="$(shasum -a 256 "$STAGING_DB" | awk '{print $1}')"
if [[ "$STAGED_CHECKSUM" != "$MANIFEST_CHECKSUM" ]]; then
  err "staged copy checksum mismatch — copy corrupted"
  err "  expected: $MANIFEST_CHECKSUM"
  err "  got:      $STAGED_CHECKSUM"
  rm -f "$STAGING_DB" "$STAGING_MANIFEST"
  exit 2
fi
ok "staged copy checksum re-verified"

# Back up the previous bundled DB if one exists, so a botched release can be
# rolled back with a single `mv assets/db/pharmaguide_core.db.previous assets/db/pharmaguide_core.db`.
if [[ -f "$TARGET_DB" ]]; then
  mv "$TARGET_DB" "$TARGET_DB.previous"
  info "previous bundled DB moved to pharmaguide_core.db.previous"
fi
if [[ -f "$TARGET_MANIFEST" ]]; then
  mv "$TARGET_MANIFEST" "$TARGET_MANIFEST.previous"
fi

mv "$STAGING_DB" "$TARGET_DB"
mv "$STAGING_MANIFEST" "$TARGET_MANIFEST"

ok "bundled artifacts updated:"
info "  $TARGET_DB"
info "  $TARGET_MANIFEST"
echo
info "Next steps:"
info "  1. Review 'git status' in the Flutter repo — assets/db/ should show"
info "     a modified DB via Git LFS (run 'git lfs ls-files' to confirm)."
info "  2. git add assets/db/"
info "  3. git commit -m \"chore(catalog): bundle v$DB_VERSION (schema $SCHEMA_VERSION, $ACTUAL_ROW_COUNT products)\""
info "  4. Delete the .previous backup files once CI is green."
