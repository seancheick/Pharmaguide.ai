#!/usr/bin/env bash
# Fail closed before a TestFlight distribution build if Sentry would receive
# the wrong environment tag or release identity for the iOS app version.
set -euo pipefail

pubspec="${1:-pubspec.yaml}"
version_line="$(grep -E '^version: ' "$pubspec" | head -1)"

if [[ ! "$version_line" =~ ^version:\ ([^+[:space:]]+)\+([0-9]+)$ ]]; then
  echo "validate_ios_release: could not parse 'version: <name>+<build>' from '$version_line'" >&2
  exit 1
fi

version_name="${BASH_REMATCH[1]}"
build_number="${BASH_REMATCH[2]}"
expected_release="com.pharmaguide.app@${version_name}+${build_number}"
distribution="${PHARMAGUIDE_IOS_DISTRIBUTION:-testflight}"

case "$distribution" in
  testflight)
    expected_environment="testflight"
    ;;
  app-store)
    expected_environment="production"
    ;;
  *)
    echo "validate_ios_release: PHARMAGUIDE_IOS_DISTRIBUTION must be 'testflight' or 'app-store'" >&2
    exit 1
    ;;
esac

if [[ "${SENTRY_ENVIRONMENT:-}" != "$expected_environment" ]]; then
  echo "validate_ios_release: SENTRY_ENVIRONMENT must be '$expected_environment' for $distribution distribution" >&2
  exit 1
fi

if [[ "${SENTRY_RELEASE:-}" != "$expected_release" ]]; then
  echo "validate_ios_release: SENTRY_RELEASE must match the iOS build: $expected_release" >&2
  exit 1
fi

echo "iOS TestFlight preflight passed for $expected_release"
