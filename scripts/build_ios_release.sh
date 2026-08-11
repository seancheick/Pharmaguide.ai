#!/usr/bin/env bash
# Build a release IPA and verify that the exported artifact matches the build
# number reserved in pubspec.yaml. If Flutter archives successfully but does not
# export an IPA, retry the export with Xcode provisioning updates enabled.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="${PHARMAGUIDE_IOS_BUILD_ROOT:-$(cd "$script_dir/.." && pwd)}"
flutter_bin="${1:?usage: build_ios_release.sh <flutter-binary> [flutter-options...]}"
shift

cd "$repo_root"

pubspec="$repo_root/pubspec.yaml"
ipa="$repo_root/build/ios/ipa/pharmaguide.ipa"
archive="$repo_root/build/ios/archive/Runner.xcarchive"
export_options="$script_dir/../ios/ExportOptions.plist"
xcodebuild_bin="${PHARMAGUIDE_XCODEBUILD_BIN:-xcodebuild}"

plist_value() {
  local key_path="$1"
  local plist_path="${2:-}"
  python3 -c '
import plistlib
import sys

key_path = sys.argv[1]
value = (
    plistlib.load(open(sys.argv[2], "rb"))
    if len(sys.argv) > 2
    else plistlib.loads(sys.stdin.buffer.read())
)
for key in key_path.split("."):
    value = value[key]
print(value)
' "$key_path" ${plist_path:+"$plist_path"}
}

PHARMAGUIDE_IOS_IPA_PATH="$ipa" \
  bash "$script_dir/prepare_ios_build_number.sh" "$pubspec"

version_line="$(grep -E '^version: ' "$pubspec" | head -1)"
expected_version_name="${version_line#version: }"
expected_version_name="${expected_version_name%%+*}"
expected_build="${version_line##*+}"

distribution="${PHARMAGUIDE_IOS_DISTRIBUTION:-app-store}"
case "$distribution" in
  testflight)
    sentry_environment="testflight"
    ;;
  app-store)
    sentry_environment="production"
    ;;
  *)
    echo "build_ios_release: PHARMAGUIDE_IOS_DISTRIBUTION must be 'testflight' or 'app-store'" >&2
    exit 1
    ;;
esac

sentry_release="com.pharmaguide.app@${expected_version_name}+${expected_build}"
PHARMAGUIDE_IOS_DISTRIBUTION="$distribution" \
  SENTRY_ENVIRONMENT="$sentry_environment" \
  SENTRY_RELEASE="$sentry_release" \
  bash "$script_dir/validate_ios_release.sh" "$pubspec"

# The build number can be reserved above, so derive both Sentry identifiers
# from the final pubspec rather than trusting pre-reservation dart-defines.
# Remove any caller-supplied values to leave one unambiguous release identity.
flutter_options=(
  "--dart-define=SENTRY_ENVIRONMENT=${sentry_environment}"
  "--dart-define=SENTRY_RELEASE=${sentry_release}"
)
for option in "$@"; do
  case "$option" in
    --dart-define=SENTRY_ENVIRONMENT=*|--dart-define=SENTRY_RELEASE=*) ;;
    *) flutter_options+=("$option") ;;
  esac
done

ipa_build_number() {
  local candidate="$1"
  [[ -f "$candidate" ]] || return 1
  unzip -p "$candidate" Payload/Runner.app/Info.plist |
    plist_value CFBundleVersion
}

ipa_version_name() {
  local candidate="$1"
  [[ -f "$candidate" ]] || return 1
  unzip -p "$candidate" Payload/Runner.app/Info.plist |
    plist_value CFBundleShortVersionString
}

matching_ipa_exists() {
  local actual_build actual_version_name
  actual_build="$(ipa_build_number "$ipa" 2>/dev/null || true)"
  actual_version_name="$(ipa_version_name "$ipa" 2>/dev/null || true)"
  [[ "$actual_build" == "$expected_build" &&
    "$actual_version_name" == "$expected_version_name" ]]
}

python3 -c \
  'import plistlib, sys; plistlib.load(open(sys.argv[1], "rb"))' \
  "$export_options"

if ! "$flutter_bin" build ipa "${flutter_options[@]}" \
  --export-options-plist="$export_options" \
  --release; then
  echo "Flutter did not finish the IPA export; checking the archive fallback." >&2
fi

if ! matching_ipa_exists; then
  archive_info="$archive/Info.plist"
  archive_build=""
  archive_version_name=""
  if [[ -f "$archive_info" ]]; then
    archive_build="$(plist_value ApplicationProperties.CFBundleVersion "$archive_info" 2>/dev/null || true)"
    archive_version_name="$(plist_value ApplicationProperties.CFBundleShortVersionString "$archive_info" 2>/dev/null || true)"
  fi

  if [[ "$archive_build" == "$expected_build" &&
    "$archive_version_name" == "$expected_version_name" ]]; then
    export_dir="$(mktemp -d "${TMPDIR:-/tmp}/pharmaguide-ios-export.XXXXXX")"
    trap 'rm -rf "$export_dir"' EXIT

    if "$xcodebuild_bin" -exportArchive \
      -archivePath "$archive" \
      -exportPath "$export_dir" \
      -exportOptionsPlist "$export_options" \
      -allowProvisioningUpdates; then
      shopt -s nullglob
      exported_ipas=("$export_dir"/*.ipa)
      shopt -u nullglob
      if ((${#exported_ipas[@]} == 1)); then
        mkdir -p "$(dirname "$ipa")"
        cp "${exported_ipas[0]}" "$ipa"
      fi
    fi
  fi
fi

if ! matching_ipa_exists; then
  echo "build_ios_release: no App Store IPA matching reserved version ${expected_version_name}+${expected_build} was exported" >&2
  echo "The build number remains reserved and will be reused on the next attempt." >&2
  exit 1
fi

echo "App Store IPA ready: build +${expected_build} at $ipa"
