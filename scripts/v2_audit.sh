#!/usr/bin/env bash
# v2 design-system governance audit.
#
# Run from repo root:
#     bash scripts/v2_audit.sh
#     make v2-audit
#
# Exits non-zero on the first violation, suitable for CI.
#
# What it checks across v2 code paths (lib/core/components/,
# lib/core/theme/v2/, lib/features/**/v2/, lib/dev/):
#
# 1. No `Color(0xFF…)` literals outside v2_colors.dart / v2_shadows.dart
#    — token files are the only allowed owners of raw hex.
# 2. No raw `TextStyle(` outside v2_typography.dart — every text style
#    must flow through V2Typography helpers (governance: weight discipline
#    400/500 only, serif-as-accent-only).
# 3. No inline `EdgeInsets.only(` / `EdgeInsets.fromLTRB(` /
#    `EdgeInsets.symmetric(` with raw numeric literals — must reference
#    V2Spacing.spaceXX tokens.
# 4. Newsreader serif (V2Typography.display*) usage is limited to hero /
#    headline / empty-state / celebration / splash contexts. The
#    onboarding-emotional-headline case is also allowed.
#
# Flags violations to stdout with file:line:source so reviewers can jump.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

violations=0

# ---------------------------------------------------------------------------
# Path globs that constitute the "v2 codebase". Adjust as v2 expands.
# ---------------------------------------------------------------------------
V2_PATHS=(
  "lib/core/components/"
  "lib/core/theme/v2/"
  "lib/dev/"
)
# Plus any lib/features/**/v2/ subtree. Portable read-loop instead of
# `mapfile` (macOS ships bash 3.x where mapfile isn't available).
while IFS= read -r path; do
  V2_PATHS+=("$path")
done < <(find lib/features -type d -name v2 2>/dev/null)

# Allowlist files (token owners that ARE the canonical source for raw values).
ALLOW_COLORS_FILES=(
  "lib/core/theme/v2/v2_colors.dart"
  "lib/core/theme/v2/v2_shadows.dart"
)
ALLOW_TEXTSTYLE_FILES=(
  "lib/core/theme/v2/v2_typography.dart"
)
# v2_spacing.dart owns raw numeric spacing constants; v2_motion.dart owns
# raw Duration constants — they need explicit numbers by definition.
ALLOW_NUMERIC_EDGEINSETS_FILES=(
  "lib/core/theme/v2/v2_spacing.dart"
)

is_allowlisted() {
  local file="$1"
  shift
  local -a list=("$@")
  for entry in "${list[@]}"; do
    if [[ "$file" == "$entry" ]]; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Check 1: hardcoded Color(0xFF…)
# ---------------------------------------------------------------------------
bold "→ Check 1: hardcoded Color(0xFF) outside v2 token owners"
hits_color=""
for p in "${V2_PATHS[@]}"; do
  [ -d "$p" ] || continue
  while IFS= read -r line; do
    file="$(printf '%s' "$line" | cut -d: -f1)"
    if ! is_allowlisted "$file" "${ALLOW_COLORS_FILES[@]}"; then
      hits_color+="$line"$'\n'
    fi
  done < <(grep -rn "Color(0xFF" "$p" --include="*.dart" 2>/dev/null || true)
done
if [ -n "$hits_color" ]; then
  red "  Violations:"
  printf '%s' "$hits_color" | sed 's/^/    /'
  violations=$((violations + 1))
else
  green "  OK"
fi

# ---------------------------------------------------------------------------
# Check 2: raw `TextStyle(` outside v2_typography.dart
# ---------------------------------------------------------------------------
bold "→ Check 2: raw TextStyle( outside v2_typography.dart"
hits_ts=""
for p in "${V2_PATHS[@]}"; do
  [ -d "$p" ] || continue
  while IFS= read -r line; do
    file="$(printf '%s' "$line" | cut -d: -f1)"
    if ! is_allowlisted "$file" "${ALLOW_TEXTSTYLE_FILES[@]}"; then
      hits_ts+="$line"$'\n'
    fi
  done < <(grep -rn "TextStyle(" "$p" --include="*.dart" 2>/dev/null \
           | grep -v "AnimatedDefaultTextStyle\|DefaultTextStyle(" || true)
done
if [ -n "$hits_ts" ]; then
  red "  Violations:"
  printf '%s' "$hits_ts" | sed 's/^/    /'
  violations=$((violations + 1))
else
  green "  OK"
fi

# ---------------------------------------------------------------------------
# Check 3: numeric-literal EdgeInsets in v2 code (must use V2Spacing tokens)
#
# Heuristic: grep for EdgeInsets with bare integer arguments. We allow
# named-arg references that already point at V2Spacing.* — those don't
# match our regex because the spacing token name appears between the
# parens. Matches bare numbers in the most common patterns:
#     EdgeInsets.all(12)
#     EdgeInsets.symmetric(horizontal: 24, vertical: 8)
#     EdgeInsets.only(top: 16, ...)
#     EdgeInsets.fromLTRB(24, 8, 24, 16)
# ---------------------------------------------------------------------------
bold "→ Check 3: numeric-literal EdgeInsets in v2 code (use V2Spacing)"
hits_ei=""
for p in "${V2_PATHS[@]}"; do
  [ -d "$p" ] || continue
  while IFS= read -r line; do
    file="$(printf '%s' "$line" | cut -d: -f1)"
    if ! is_allowlisted "$file" "${ALLOW_NUMERIC_EDGEINSETS_FILES[@]}"; then
      hits_ei+="$line"$'\n'
    fi
  done < <(grep -rEn "EdgeInsets\.(all|symmetric|only|fromLTRB)\([^)]*\b[0-9]+\b[^)]*\)" "$p" --include="*.dart" 2>/dev/null \
           | grep -v "V2Spacing\." || true)
done
if [ -n "$hits_ei" ]; then
  yellow "  Violations (advisory — replace with V2Spacing):"
  printf '%s' "$hits_ei" | sed 's/^/    /'
  # Treat as warning, not failure — some places (test/golden viewports,
  # logical-pixel constants) legitimately want literal numbers. Fail only
  # on Check 1 and Check 2 in CI mode.
  if [ "${V2_AUDIT_STRICT:-0}" = "1" ]; then
    violations=$((violations + 1))
  fi
else
  green "  OK"
fi

# ---------------------------------------------------------------------------
# Check 4: Newsreader serif scope.
#
# `V2Typography.display(...)` / `displaySm(...)` / `displayXs(...)` are
# the Newsreader-serif methods. Their use is governance-restricted to
# emotional contexts: hero headlines, onboarding moments, empty states,
# celebrations, splash, scanner verdict reveal, key takeaways.
#
# Allowlist by directory — anything under these paths may call display*:
# ---------------------------------------------------------------------------
bold "→ Check 4: Newsreader serif (display*) usage scope"
ALLOW_SERIF_PATHS=(
  "lib/core/theme/v2/v2_typography.dart"
  "lib/core/theme/v2/v2_theme.dart"
  "lib/core/components/pg_celebration.dart"
  "lib/core/components/pg_empty_state.dart"
  "lib/core/components/pg_section_header.dart"
  "lib/core/components/pg_verdict_reveal.dart"
  "lib/dev/v2_gallery.dart"
  "lib/features/splash/v2/"
  "lib/features/onboarding/v2/"
  "lib/features/auth/v2/"
  "lib/features/home/v2/"
  "lib/features/settings/v2/"
  "lib/features/scanner/v2/"
  "lib/features/stack/v2/"
  "lib/features/product_detail/v2/"
  # These are onboarding-style profile setup flows even though their files
  # live under the profile feature.
  "lib/features/profile/v2/profile_setup_v2_screen.dart"
  "lib/features/profile/v2/profile_wizard_v2_screen.dart"
)
hits_serif=""
for p in "${V2_PATHS[@]}"; do
  [ -d "$p" ] || continue
  while IFS= read -r line; do
    file="$(printf '%s' "$line" | cut -d: -f1)"
    allowed=false
    for allow in "${ALLOW_SERIF_PATHS[@]}"; do
      if [[ "$file" == "$allow"* ]] || [[ "$file" == "$allow" ]]; then
        allowed=true
        break
      fi
    done
    if ! $allowed; then
      hits_serif+="$line"$'\n'
    fi
  done < <(grep -rEn "V2Typography\.display(Sm|Xs)?\(" "$p" --include="*.dart" 2>/dev/null || true)
done
if [ -n "$hits_serif" ]; then
  red "  Violations:"
  printf '%s' "$hits_serif" | sed 's/^/    /'
  violations=$((violations + 1))
else
  green "  OK"
fi

# ---------------------------------------------------------------------------
echo
if [ $violations -eq 0 ]; then
  green "✓ v2 governance audit passed"
  exit 0
fi
red "✗ v2 governance audit failed ($violations check(s) had violations)"
exit 1
