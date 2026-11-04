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

# Execute the canonical Make target in a fixture: no Flutter, secrets, signing
# or network. The user's chosen distribution must reach the shared builder,
# and hydration must happen before packaging.
FIXTURE="$TMP/make-repo"
mkdir -p "$FIXTURE/scripts" "$FIXTURE/tool"
cp "$REPO_ROOT/Makefile" "$FIXTURE/Makefile"
printf 'SUPABASE_URL=https://fixture.invalid\nSUPABASE_ANON_KEY=fixture-anon\n' > "$FIXTURE/.env"
printf 'echo hydration >> "$PROBE_CALLS"\n' > "$FIXTURE/tool/fetch_interaction_db.sh"
cat > "$FIXTURE/scripts/build_ios_release.sh" <<'BUILDER'
echo "build:${PHARMAGUIDE_IOS_DISTRIBUTION:-app-store}" >> "$PROBE_CALLS"
[[ "$1" == /fixture/flutter ]] || exit 31
[[ "$*" == *"--dart-define=SUPABASE_URL=https://fixture.invalid"* ]] || exit 32
[[ "$*" == *"--dart-define=SUPABASE_ANON_KEY=fixture-anon"* ]] || exit 33
[[ "$*" != *USE_V2_* ]] || exit 34
BUILDER
# The real key check, on a fixture key list: a store build needs a key, TestFlight doesn't.
cp "$REPO_ROOT/scripts/require_alert_feed_key.sh" "$FIXTURE/scripts/require_alert_feed_key.sh"
mkdir -p "$FIXTURE/lib/services"
fixture_keys() {
  printf 'const Map<String, String> _kProductionAlertFeedKeys = %s;\n' "$1" \
    > "$FIXTURE/lib/services/release_manifest.dart"
}
packages() {
  local channel="$1" calls="$2"
  (cd "$FIXTURE" && PROBE_CALLS="$calls" PHARMAGUIDE_IOS_DISTRIBUTION="$channel" \
    make build-ios FLUTTER=/fixture/flutter) >/dev/null 2>&1 \
    && [[ "$(cat "$calls")" == "$(printf 'hydration\nbuild:%s' "$channel")" ]]
}
PINNED="{'alert-feed-2026-11': '$(printf 'ab%.0s' {1..32})'}"

fixture_keys '{}'
if packages testflight "$TMP/calls-testflight-no-key"; then
  ok 'build-ios packages a TestFlight build with no alert-feed key'
else
  bad 'build-ios failed canonical testflight packaging contract with no alert-feed key'
fi
if (cd "$FIXTURE" && PROBE_CALLS="$TMP/calls-store-no-key" PHARMAGUIDE_IOS_DISTRIBUTION=app-store \
     make build-ios FLUTTER=/fixture/flutter) >/dev/null 2>&1; then
  bad 'build-ios packaged an App Store build with no alert-feed key'
elif [[ -e "$TMP/calls-store-no-key" ]]; then
  bad 'build-ios refused an App Store build only after starting work'
else
  ok 'build-ios refuses an App Store build with no alert-feed key, before any work'
fi

fixture_keys "$PINNED"
for channel in testflight app-store; do
  if packages "$channel" "$TMP/calls-$channel"; then
    ok "build-ios hydrates then invokes shared builder for $channel with required defines"
  else
    bad "build-ios failed canonical $channel packaging contract"
  fi
done

# An Android bundle is a store build, whatever the iOS setting in the shell says.
fixture_keys '{}'
if (cd "$FIXTURE" && PROBE_CALLS="$TMP/calls-android" PHARMAGUIDE_IOS_DISTRIBUTION=testflight \
     make build-android FLUTTER=/usr/bin/true) >/dev/null 2>&1; then
  bad 'build-android packaged with no alert-feed key under the TestFlight setting'
else
  ok 'build-android refuses with no alert-feed key, even under the TestFlight setting'
fi
fixture_keys "$PINNED"
if (cd "$FIXTURE" && PROBE_CALLS="$TMP/calls-android" PHARMAGUIDE_IOS_DISTRIBUTION=testflight \
     make build-android FLUTTER=/usr/bin/true) >/dev/null 2>&1; then
  ok 'build-android packages with a pinned alert-feed key'
else
  bad 'build-android failed with a pinned alert-feed key'
fi
(cd "$FIXTURE" && make -qp) > "$TMP/make-database" 2>/dev/null || true
if grep -Eq '^(run-v2(pd|pf|med|search|qc|all)(-ios)?|build-ipa[^:]*):' "$TMP/make-database"; then
  bad 'retired UI-flag targets remain callable'
else
  ok 'retired UI-flag targets are removed'
fi
(cd "$FIXTURE" && make help) > "$TMP/make-help"
if grep -Eq 'run-v2[[:space:]]' "$TMP/make-help"; then
  ok 'make help includes the supported gallery preview with a digit in its name'
else
  bad 'make help hides supported targets whose names contain digits'
fi

echo
echo "ios release preflight: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
