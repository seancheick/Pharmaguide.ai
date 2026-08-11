#!/usr/bin/env bash
# Fail-closed regression tests for the TestFlight release preflight.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/validate_ios_release.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

ok() { printf '  PASS %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

expect() {
  local expected="$1" label="$2"; shift 3
  if "$@" >/dev/null 2>&1; then
    actual=0
  else
    actual=1
  fi
  if [[ "$actual" == "$expected" ]]; then
    ok "$label"
  else
    bad "$label (wanted exit-class $expected, got $actual)"
  fi
}

PUBSPEC="$TMP/pubspec.yaml"
printf 'name: release_fixture\nversion: 1.2.3+45\n' > "$PUBSPEC"

expect 0 'TestFlight environment and matching Sentry release pass' -- \
  env SENTRY_ENVIRONMENT=testflight \
    SENTRY_RELEASE=com.pharmaguide.app@1.2.3+45 \
    bash "$SCRIPT" "$PUBSPEC"

expect 1 'non-TestFlight beta environment is rejected' -- \
  env SENTRY_ENVIRONMENT=production \
    SENTRY_RELEASE=com.pharmaguide.app@1.2.3+45 \
    bash "$SCRIPT" "$PUBSPEC"

expect 1 'Sentry release with a different iOS build is rejected' -- \
  env SENTRY_ENVIRONMENT=testflight \
    SENTRY_RELEASE=com.pharmaguide.app@1.2.3+44 \
    bash "$SCRIPT" "$PUBSPEC"

expect 1 'missing Sentry release is rejected' -- \
  env SENTRY_ENVIRONMENT=testflight \
    SENTRY_RELEASE= \
    bash "$SCRIPT" "$PUBSPEC"

printf 'name: release_fixture\nversion: invalid\n' > "$PUBSPEC"
expect 1 'invalid iOS version is rejected' -- \
  env SENTRY_ENVIRONMENT=testflight \
    SENTRY_RELEASE=com.pharmaguide.app@1.2.3+45 \
    bash "$SCRIPT" "$PUBSPEC"

if grep -Fq 'validate_ios_release.sh' "$REPO_ROOT/scripts/build_ios_release.sh"; then
  ok 'distribution build invokes the preflight'
else
  bad 'distribution build does not invoke the preflight'
fi

if grep -Fq 'PHARMAGUIDE_IOS_DISTRIBUTION=testflight' "$REPO_ROOT/Makefile"; then
  ok 'TestFlight build targets declare their distribution channel'
else
  bad 'TestFlight build targets do not declare their distribution channel'
fi

echo
echo "ios release preflight: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
