#!/usr/bin/env bash
# Capture the 4 marketing screenshots from the iOS simulator.
#
#   ./scripts/capture_screenshots.sh
#   ./scripts/capture_screenshots.sh --device "iPhone 15 Pro Max"
#   ./scripts/capture_screenshots.sh --out /tmp/shots
#
# Requirements (Mac only):
#   - Xcode + iOS simulator
#   - Flutter SDK on PATH (or set FLUTTER env var)
#   - `.env` at repo root with SUPABASE_URL / SUPABASE_ANON_KEY etc.
#   - `assets/db/pharmaguide_core.db` materialized: `git lfs pull`
#
# What it does:
#   For each of the 4 marketing routes, the script launches `flutter
#   run` with SCREENSHOT_MODE=true (which triggers
#   ScreenshotSeeder.maybeRun) and SCREENSHOT_ROUTE=<path> (which
#   overrides GoRouter.initialLocation), waits for the app to render,
#   then captures via `xcrun simctl io booted screenshot`.
#
#   The seeder is idempotent — re-running the script does not duplicate
#   stack entries.
#
# Output: PNG files at 1179×2556 (iPhone 15 Pro native resolution).
# Drop them into https://shots.so for device-framed marketing shots.

set -euo pipefail

# ─── Args ─────────────────────────────────────────────────────────────────────
DEVICE="iPhone 15 Pro"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docs/screenshots/raw"
READY_TIMEOUT=120  # seconds to wait for `Flutter run key commands` line
RENDER_BUFFER=8    # extra seconds after ready for first paint + seed

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --ready-timeout) READY_TIMEOUT="$2"; shift 2 ;;
    --render-buffer) RENDER_BUFFER="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# ─── Preflight ────────────────────────────────────────────────────────────────
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: iOS simulator only runs on macOS." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null; then
  echo "error: xcrun not found. Install Xcode." >&2
  exit 1
fi

FLUTTER_BIN="${FLUTTER:-flutter}"
if ! command -v "$FLUTTER_BIN" >/dev/null; then
  echo "error: '$FLUTTER_BIN' not on PATH. Set FLUTTER=/path/to/flutter." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -f .env ]]; then
  echo "error: .env not found at repo root." >&2
  exit 1
fi

# Refuse to run when the bundled core DB is an LFS pointer — the seeder
# needs real product rows.
DB_FILE="assets/db/pharmaguide_core.db"
if [[ ! -f "$DB_FILE" ]] || head -c 50 "$DB_FILE" | grep -q "git-lfs"; then
  echo "error: $DB_FILE is missing or an LFS pointer. Run: git lfs pull" >&2
  exit 1
fi

# Source .env and build the dart-defines list. The Makefile does this
# too; we duplicate it here so screenshots don't depend on `make`.
set -a
# shellcheck disable=SC1091
source .env
set +a

DEFINES=(
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}"
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"
  --dart-define=GEMINI_API_KEY="${GEMINI_API_KEY:-}"
  --dart-define=SENTRY_DSN="${SENTRY_DSN:-}"
  --dart-define=SENTRY_ENVIRONMENT="${SENTRY_ENVIRONMENT:-development}"
  --dart-define=SENTRY_RELEASE="${SENTRY_RELEASE:-}"
  --dart-define=SCREENSHOT_MODE=true
)

mkdir -p "$OUT_DIR"

# ─── Simulator ────────────────────────────────────────────────────────────────
echo "→ Booting $DEVICE…"
DEVICE_ID="$(xcrun simctl list devices available | \
  awk -v d="$DEVICE" '$0 ~ d {match($0, /\(([0-9A-F-]+)\)/, m); print m[1]; exit}')"
if [[ -z "$DEVICE_ID" ]]; then
  echo "error: simulator '$DEVICE' not found. List options:" >&2
  echo "  xcrun simctl list devices available" >&2
  exit 1
fi

# Boot is idempotent — `simctl boot` errors if already booted, swallow it.
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$DEVICE_ID" -b >/dev/null

# ─── Capture loop ─────────────────────────────────────────────────────────────
# (label, route, filename) tuples. Comma-separated so the loop stays
# legible in bash.
SHOTS=(
  "scan,/scan,01-scan.png"
  "stack,/stack,02-my-stack.png"
  "product,RESOLVE_HERO,03-product-fitscore.png"
  "interaction,RESOLVE_INTERACTION,04-interaction-warning.png"
)

capture_one() {
  local label="$1" route="$2" filename="$3"
  local log="/tmp/pharmaguide-screenshot-${label}.log"

  echo "→ [$label] launching flutter run for $route…"
  : > "$log"

  "$FLUTTER_BIN" run \
    "${DEFINES[@]}" \
    --dart-define=SCREENSHOT_ROUTE="$route" \
    -d "$DEVICE_ID" \
    > "$log" 2>&1 &
  local pid=$!

  # Wait for the "Flutter run key commands" banner, which only prints
  # once the app is attached + first frame is rendering.
  local elapsed=0
  while (( elapsed < READY_TIMEOUT )); do
    if grep -q "Flutter run key commands" "$log" 2>/dev/null; then
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "error: flutter run for $label exited early. Log:" >&2
      tail -40 "$log" >&2
      return 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  if (( elapsed >= READY_TIMEOUT )); then
    echo "error: flutter run for $label did not become ready within ${READY_TIMEOUT}s." >&2
    kill -INT "$pid" 2>/dev/null || true
    return 1
  fi

  echo "   waiting ${RENDER_BUFFER}s for first paint + seed…"
  sleep "$RENDER_BUFFER"

  local out="$OUT_DIR/$filename"
  xcrun simctl io "$DEVICE_ID" screenshot "$out"
  echo "   ✓ $out"

  # SIGINT triggers flutter's graceful shutdown.
  kill -INT "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

# The hero / interaction routes need a real dsldId. Resolve them by
# launching the app once at /stack (the seeder runs and we read the
# resulting stack from user_data.db), or — simpler — just route to the
# search screen with the relevant query string. We use the search
# screen because it shows top-ranked products immediately and the user
# can tap into them. For the website, however, we want the *product
# detail* screen as the screenshot — so we need dsldIds.
#
# The cleanest way: the seeder populates the stack with these very
# products, so we can read /stack and pull the first/second item's
# dsldId from `flutter logs`. Even cleaner: extend the seeder to print
# the resolved dsldIds to debug log, and the script greps them.
#
# For v1 we accept a small manual step: the seeder logs each resolved
# product. The script captures the My-Stack screenshot first (which
# triggers seeding), then parses the log to discover the hero +
# interaction dsldIds.

HERO_DSLD=""
INTERACTION_DSLD=""

discover_dsld_ids() {
  local seed_log="/tmp/pharmaguide-screenshot-seed-discovery.log"
  echo "→ priming seeder + discovering dsldIds (one-time launch at /stack)…"
  : > "$seed_log"

  "$FLUTTER_BIN" run \
    "${DEFINES[@]}" \
    --dart-define=SCREENSHOT_ROUTE=/stack \
    -d "$DEVICE_ID" \
    > "$seed_log" 2>&1 &
  local pid=$!

  local elapsed=0
  while (( elapsed < READY_TIMEOUT )); do
    if grep -q "Flutter run key commands" "$seed_log" 2>/dev/null; then break; fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  sleep "$RENDER_BUFFER"

  HERO_DSLD="$(grep -oE 'seeded hero-vitamin-d3: dsldId=[^ ]+' "$seed_log" \
    | head -1 | sed -E 's/.*dsldId=//')"
  INTERACTION_DSLD="$(grep -oE 'seeded interaction-st-johns-wort: dsldId=[^ ]+' "$seed_log" \
    | head -1 | sed -E 's/.*dsldId=//')"

  kill -INT "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true

  # The seeder is idempotent — if the items already existed it won't
  # print "seeded" lines. In that case, fall back to reading the user
  # DB via sqlite3 in the simulator container.
  if [[ -z "$HERO_DSLD" || -z "$INTERACTION_DSLD" ]]; then
    echo "   (seeder log empty — items likely pre-existing, querying user_data.db…)"
    local container
    container="$(xcrun simctl get_app_container "$DEVICE_ID" \
      ai.pharmaguide.app data 2>/dev/null || true)"
    if [[ -n "$container" && -f "$container/Documents/user_data.db" ]]; then
      HERO_DSLD="$(sqlite3 "$container/Documents/user_data.db" \
        "SELECT dsld_id FROM user_stacks_local \
         WHERE id LIKE 'hero-vitamin-d3%' AND deleted_at IS NULL LIMIT 1;" 2>/dev/null || true)"
      INTERACTION_DSLD="$(sqlite3 "$container/Documents/user_data.db" \
        "SELECT dsld_id FROM user_stacks_local \
         WHERE id LIKE 'interaction-st-johns-wort%' AND deleted_at IS NULL LIMIT 1;" 2>/dev/null || true)"
    fi
  fi

  if [[ -z "$HERO_DSLD" || -z "$INTERACTION_DSLD" ]]; then
    echo "error: could not resolve hero/interaction dsldIds. Inspect $seed_log" >&2
    exit 1
  fi
  echo "   hero=$HERO_DSLD  interaction=$INTERACTION_DSLD"
}

discover_dsld_ids

for entry in "${SHOTS[@]}"; do
  IFS=',' read -r label route filename <<< "$entry"
  case "$route" in
    RESOLVE_HERO) route="/product/$HERO_DSLD" ;;
    RESOLVE_INTERACTION) route="/product/$INTERACTION_DSLD?section=interactions" ;;
  esac
  capture_one "$label" "$route" "$filename"
done

echo
echo "✓ Done. 4 PNGs in $OUT_DIR"
echo "  Next: drag them into https://shots.so for device frames."
